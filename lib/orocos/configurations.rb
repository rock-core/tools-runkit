require 'stringio'
require 'yaml'
module Orocos
    # Class handling multiple possible configuration for a single task
    #
    # It can load configuration files that are structured as follows:
    #
    # A configuration file is a YAML file that contains multiple sections. Each
    # section starts with --- and can contain options of the form
    # option_name:value. The section header can be omitted for the very first
    # section
    #
    # For instance
    #
    #   --- name:default merge:true chain:default,test
    #
    # The following options are possible:
    #
    # name:: 
    #   it is optional for the first section and mandatory for further
    #   sections. It gives a name to the section, that can then be used
    #   to refer to the configuration information in TaskConfigurations#apply
    #   and TaskConfigurations#conf. If ommitted for the first section, the name
    #   'default' is used
    # merge::
    #   If set to true, the section will be merged with previous configuration
    #   data previously stored under the same name. Otherwise, it replaces
    #   existing information. The default is false.
    # chain::
    #   If set, it has to be a comma-separated list of configuration names. It
    #   tells the configuration class that this configuration section should
    #   always be merged with the ones listed. The name of the current
    #   configuration section can be listed, in which case it will be merged in
    #   the specified order. Otherwise, it is added at the end.
    # 
    class TaskConfigurations
        attr_reader :sections
        attr_reader :conf_options
        attr_reader :model

        def initialize(task_model)
            @model = task_model
            @sections = Hash.new
            @merged_conf = Hash.new
        end

        # Loads the configurations from a YAML file
        #
        # Multiple configurations can be saved in the file, in which case each
        # configuration set must be separated by a line of the form
        #
        #   --- name:configuration_name
        #
        # The first YAML document has, by default, the name 'default'. One can
        # also be provided if needed.
        def load_from_yaml(file)
            document_lines = File.readlines(file)

            headers = document_lines.enum_for(:each_with_index).
                find_all { |line, _| line =~ /^---/ }
            if headers.empty? || headers.first[1] != 0
                headers.unshift ["--- name:default", 0]
            end

            options = headers.map do |line, line_number|
                line_options = Hash.new
                line = line.chomp
                line.split(/\s+/)[1..-1].each do |opt|
                    if opt =~ /^(\w+):(.*)$/
                        line_options[$1] = $2
                    else
                        raise ArgumentError, "#{file}:#{line_number}: wrong format #{opt}, expected option_name:value, where 'value' has no spaces"
                    end
                end
                line_options['merge'] = (line_options['merge'] == 'true')
                line_options['chain'] = (line_options['chain'] || '').split(',')
                [line_options, line_number]
            end
            options[0][0]['name'] ||= 'default'

            options.each do |line_options, line_number|
                if !line_options['name']
                    raise ArgumentError, "#{file}:#{line_number}: missing a 'name' option"
                end
            end

            sections = []
            options.each_cons(2) do |(_, line0), (_, line1)|
                sections << document_lines[line0 + 1, line1 - line0 - 1]
            end
            sections << document_lines[options[-1][1] + 1, document_lines.size - options[-1][1] - 1]

            changed_sections = []
            @conf_options = options
            sections.each_with_index do |doc, idx|
                doc = doc.join("")
                result = YAML.load(StringIO.new(doc))
                if result
                    conf = config_from_hash(result)
                else
                    conf = Hash.new
                end

                conf_options = options[idx].first
                name = conf_options['name']
                if self.sections[name]
                    if conf_options['merge']
                        conf = merge_conf(self.sections[name], conf, true)
                    end
                    if self.sections[name] != conf
                        changed_sections << name
                    end
                end
                self.sections[name] = conf
            end
	    if !changed_sections.empty?
	    	@merged_conf.clear
	    end
            changed_sections
        rescue Exception => e
            raise e, "error loading #{file}: #{e.message}", e.backtrace
        end

        def config_from_array(array, value_t)
            element_t = value_t.deference
            array.map do |value|
                if value.kind_of?(Hash)
                    config_from_hash(value, element_t)
                elsif value.respond_to?(:to_ary)
                    config_from_array(value, element_t)
                else
                    Typelib.from_ruby(value, element_t)
                end
            end
        end

        # Normalizes a configuration object in a hash form into a form that can
        # be used by #configuration
        #
        # It is an internal helper method used by #load_from_yaml
        def config_from_hash(hash, base = nil) # :nodoc:
            result = Hash.new
            hash.each do |key, value|
                if base
                    value_t = base[key]
                else
                    prop = model.find_property(key)
                    if !prop
                        raise ArgumentError, "#{key} is not a property of #{model.name}"
                    end
                    value_t = Orocos.typelib_type_for(prop.type)
                end

                value =
                    if value.kind_of?(Hash)
                        config_from_hash(value, value_t)
                    elsif value.respond_to?(:to_ary)
                        config_from_array(value, value_t)
                    else
			begin
			    Typelib.from_ruby(value, value_t)
			rescue Exception => e 
			    raise ArgumentError, "could not convert value for #{key}. #{e}"
			end
                    end

                result[key] = value
            end
            result
        end

        def merge_conf_array(a, b, override)
            result = []
            a.each_with_index do |v1, idx|
                v2 = b[idx]

                if !v2
                    result << v1
                    next
                end

                if v1.kind_of?(Hash) && v2.kind_of?(Hash)
                    result << merge_conf(v1, v2, override)
                elsif v1.respond_to?(:to_ary) && v2.respond_to?(:to_ary)
                    result << merge_conf_array(v1, v2, override)
                elsif v1 != v2
                    raise ArgumentError, "cannot merge configuration: conflict in [#{idx}] between v1=#{v1} and v2=#{v2}"
                end
            end

            if b.size > a.size
                result.concat(b[a.size..-1])
            end
            result
        end

        # Helper method that adds the configuration of +b+ into the existing
        # configuration hash +a+
        def merge_conf(a, b, override)
            result = if override
                a.recursive_merge(b) do |k, v1, v2|
                    if v1.respond_to?(:to_ary) && v2.respond_to?(:to_ary)
                        merge_conf_array(v1, v2, true)
                    else
                        v2
                    end
                end
            else
                a.recursive_merge(b) do |k, v1, v2|
                    if v1.respond_to?(:to_ary) && v2.respond_to?(:to_ary)
                        merge_conf_array(v1, v2, false)
                    elsif v1 != v2
                        raise ArgumentError, "cannot merge configuration: conflict in field #{k} between v1=#{v1} and v2=#{v2}"
                    else
                        v1
                    end
                end
            end
            result
        end

        # Returns the task configuration that is the combination of the
        # configurations listed in +names+
        #
        # If +override+ is false (the default), a requested configuration
        # cannot override a value set by another (the set of fields they are
        # setting must be disjoint)
        #
        # Otherwise, the configurations are merged in the same order than listed
        # in +names+
        #
        # For instance, let's assume that the following configurations are
        # available
        #
        #   --- name:default
        #   threshold: 20
        #   --- name: fast
        #   speed: 10
        #   --- name: slow
        #   speed: 1
        #
        # Then
        # 
        #   configuration(['default', 'fast'])
        #
        # returns { 'threshold' => 20, 'speed' => 10 } regardless of the value
        # of the override parameter, while
        # 
        #   configuration(['default', 'fast', 'slow'])
        #
        # will raise ArgumentError and 
        # 
        #   configuration(['default', 'fast', 'slow'], true)
        #
        # returns { 'threshold' => 20, 'speed' => 1 }
        def conf(names, override = false)
            if names.size == 1
                return sections[names.first]
            elsif cached = @merged_conf[[names, override]]
                return cached
            else
                if !sections[names.last]
                    raise ArgumentError, "#{names.last} is not a known configuration section"
                end
                config = conf(names[0..-2], override)
                config = merge_conf(config, sections[names.last], override)

                @merged_conf[[names, override]] = config
                return config
            end
        end

        def apply_configuration_hash_to_value(value, conf)
            conf.each do |conf_key, conf_value|
                value[conf_key] = apply_configuration_to_value(value.raw_get_field(conf_key), conf_value)
            end
            value
        end

        def apply_configuration_array_to_value(value, conf)
            conf.each_with_index do |element, idx|
                while value.size <= idx
                    new_value = value.class.deference.new
                    new_value.zero!
                    value.push(new_value)
                end
                value[idx] = apply_configuration_to_value(value.raw_get(idx), element)
            end
            value
        end

        # Helper method for #apply_configuration
        def apply_configuration_to_value(value, conf) # :nodoc:
            if conf.kind_of?(Hash)
                apply_configuration_hash_to_value(value, conf)
            elsif conf.respond_to?(:to_ary)
                apply_configuration_array_to_value(value, conf)
            else
                conf
            end
        end

        # Applies the specified configuration to the given task
        #
        # See #configuration for a description of +names+ and +override+ 
        def apply(task, names, override = false)
            if names.respond_to?(:to_ary)
                config = conf(names, override)
            elsif names.respond_to?(:to_str)
                config = conf([names], override)
            else
                config = names
            end

            if !config
                if names == ['default']
                    ConfigurationManager.info "required to apply configuration #{names.join(", ")} on #{task.name} of type #{task.model.name}, but this configuration is not registered or empty. Not changing anything."
                    return
                else
                    raise ArgumentError, "no configuration #{names.join(", ")} for #{task.model.name}"
                end
            end
            
            timestamp = Time.now
            config.each do |prop_name, conf|
                p = task.property(prop_name)
                result = p.raw_read
                result = apply_configuration_to_value(result, conf)
                p.write(result, timestamp)
            end
        end

        def self.typelib_to_yaml_value(value)
            if value.kind_of?(Typelib::CompoundType)
                result = Hash.new
                value.raw_each_field do |field_name, field_value|
                    result[field_name] = typelib_to_yaml_value(field_value)
                end
                result
            elsif value.kind_of?(Symbol)
                value.to_s
            elsif value.respond_to?(:to_str)
                value.to_str
            elsif value.kind_of?(Typelib::ArrayType) || value.kind_of?(Typelib::ContainerType)
                value.raw_each.map(&method(:typelib_to_yaml_value))
            elsif value.kind_of?(Typelib::Type)
                Typelib.to_ruby(value)
            else value
            end
        end

        def self.config_as_hash(task)
            current_config = Hash.new
            task.each_property do |prop|
                current_config[prop.name] = typelib_to_yaml_value(prop.raw_read)
            end
            current_config
        end

        def save(task, file, name)
            config_hash = self.class.save(task, file, name)
            sections[name] = config_from_hash(config_hash)
        end

        # Saves the current configuration of +task+ in the provided file. +name+
        # is the name of the new section.
        def self.save(task, file, name)
            if File.directory?(file)
                file = File.join(file, "#{task.model.name}.yml")
            else
                FileUtils.mkdir_p(File.dirname(file))
            end
            name ||= task.name

            current_config = config_as_hash(task)

            parts = []
            current_config.keys.sort.each do |property_name|
                doc = task.model.find_property(property_name).doc
                if doc
                    parts << doc.split("\n").map { |s| "# #{s}" }.join("\n")
                else
                    parts << "# no documentation available for this property"
                end

                property_hash = { property_name => current_config[property_name] }
                yaml = YAML.dump(property_hash)
                parts << yaml.split("\n")[1..-1].join("\n")
            end

            File.open(file, 'a') do |io|
                io.write("--- name:#{name}\n")
                io.write(parts.join("\n"))
                io.puts
            end
            current_config
        end
    end

    # @deprecated use Orocos.apply_conf instead
    def self.apply_conf_file(task, path, names = ['default'], overrides = true)
        conf = TaskConfigurations.new(task.model)
        conf.load_from_yaml(path)
        conf.apply(task, names, overrides)
        task
    end

    # Applies the configuration stored in +path+ on +task+. The selected
    # sections can be listed in +names+ (by default, uses the default
    # configuration).
    #
    # +overrides+ controls whether the sections listed in +names+ can override
    # each other, if a value set in one of them can be overriden by another one.
    #
    # +path+ can either be a file or a directory. In the latter case, the
    # configuration stored in path/model_name.yml will be used
    def self.apply_conf(task, path, names = ['default'], overrides = true)
        if File.directory?(path)
            path = File.join(path, "#{task.model.name}.yml")
            if !File.file?(path)
                return
            end
        end

        conf = TaskConfigurations.new(task.model)
        conf.load_from_yaml(path)
        conf.apply(task, names, overrides)
        task
    end

    # Class that manages a set of configurations
    class ConfigurationManager
        extend Logger::Forward
        extend Logger::Hierarchy

        # A mapping from the task model names to the corresponding
        # TaskConfigurations object
        attr_reader :conf

        def initialize
            @conf = Hash.new
        end

        # Loads all configuration files present in the given directory
        #
        # The directory is assumed to be populated with files of the form
        #
        #   orogen_project::TaskName.yml
        #
        # each file being a YAML file that follows the format described in
        # the documentation of TaskConfigurations.
        def load_dir(dir)
            changed = Hash.new
            Dir.glob(File.join(dir, '*.yml')) do |file|
                configuration = load_file(file)
                if configuration
                    changed[configuration.model.name] = configuration
                    ConfigurationManager.info "  #{configuration.model.name} available configurations: #{conf[configuration.model.name].sections.keys.join(", ")}"
                end
            end
            changed
        end

        # Loads the configuration from the given yml file
        #
        # The file is assumed to be named of the form
        #
        #   orogen_project::TaskName.yml
        #
        # or a the task_model name has to be provided
        #
        # returns false if nothing was loaded or if the configuration was already loaded 
        # otherwise it returns the loaded configuration
        def load_file(file,model_name = nil)
            return if !File.file?(file)
            model_name ||= File.basename(file, '.yml')

            begin
                model = Orocos.task_model_from_name(model_name)
            rescue Orocos::NotFound
                ConfigurationManager.warn "ignoring configuration file #{file} as there are no corresponding task model"
                return false
            end

            ConfigurationManager.info "loading configuration file #{file} for #{model.name}"
            conf[model.name] ||= TaskConfigurations.new(model)

            changed_configurations = conf[model.name].load_from_yaml(file)
            ConfigurationManager.info "  #{model.name} available configurations: #{conf[model.name].sections.keys.join(", ")}"
            if !changed_configurations.empty?
                changed_configurations
            else
                false
            end
        end

        def find_task_configuration_object(task)
            if !task.model
                raise ArgumentError, "cannot use ConfigurationManager#apply for non-orogen tasks"
            end
            conf[task.model.name]
        end

        # Applies the specified configuration on +task+
        #
        # See TaskConfigurations#apply for a description of the process
        def apply(task, names, override = false)
            task_conf = find_task_configuration_object(task)
            if !task_conf
                if names == ['default']
                    ConfigurationManager.info "required default configuration on #{task.name} of type #{task.model.name}, but #{task.model.name} has no registered configurations"
                    return
                else
                    raise ArgumentError, "no configuration available for #{task.model.name}"
                end
            end

            ConfigurationManager.info "applying configuration #{names.join(", ")} on #{task.name} of type #{task.model.name}"
            task_conf.apply(task, names, override)
            true
        end

        # Dumps the configuration of +task+ on the specified path
        #
        # If +path+ is a directory, the configuration is saved in
        # a file called project_name::TaskName.yml. Otherwise, it is saved in
        # the file
        #
        # If +name+ is given, it is used as the new configuration name.
        # Otherwise, the task's name is used
        def save(task, path, name = nil)
            task_conf = find_task_configuration_object(task)
            if !task_conf
                task_conf = conf[task.model.name] = TaskConfigurations.new(task.model)
            end
            task_conf.save(task, path, name)
        end
    end
end

