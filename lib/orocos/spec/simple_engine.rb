module Orocos
    class SimpleEngine
        # The configuration as a Hash. It can be loaded from a YAML file by
        # load_config
        attr_reader :configuration
        def load_config(file)
            @configuration = YAML.load(File.read(file))
        end

        def config(name)
            configuration[name]
        end

        # The set of already initialized instances
        attr_reader :instances

        def initialize
            @instances = Hash.new
            @configuration = Hash.new
            @toplevel = Hash.new
            @selections = Hash.new
            @available_tasks = Array.new
            @available_models = Set.new
            @tasks = Hash.new { |h, k| h[k] = Hash.new }

            @subsystems           = Hash.new
            @communication_busses = Hash.new
            @connections          = Array.new

            @log_dir = "log"
            @results_dir = "results"
        end

        attr_reader :log_dir
        attr_reader :results_dir

        attr_accessor :system
        attr_accessor :robot
        attr_reader :selections
        attr_reader :toplevel
        attr_reader :connections

        attr_reader :communication_busses
        attr_reader :subsystems

        def add(model_name, options = Hash.new)
            options, remains = Kernel.filter_options options,
                :as => model_name

            @toplevel[options[:as]]   = system.get(model_name)
            @selections[options[:as]] = remains
            self
        end

        def select(mappings)
            mappings.each do |from_name, to_name|
                @selections[from_name] = system.get(to_name)
            end
        end

        attr_reader :available_tasks
        attr_reader :available_models
        attr_reader :available_deployments
        attr_reader :tasks

        def find_task(model, name)
            if model.name != name && tasks.has_key?(model.name) && tasks[model.name].has_key?(name)
                tasks[model.name][name]
            end
        end

        def register_task(instance)
            return if instance.model.name == instance.name

            system.device_drivers.each_key do |devices|
                if devices.include?(instance.name)
                    devices.each do |device_name|
                        tasks[instance.model.name][device_name] = instance
                    end
                    break
                end
            end
            tasks[instance.model.name][instance.name] = instance
            self
        end

        # Pick up the right system inside +models+
        def disambiguate(required_model, models)
            # Narrow the set of models by looking at the available task contexts
            models.delete_if do |task_model|
                !available_models.include?(task_model.name)
            end

            sel = selections[required_model.name]
            if models.size == 1
                if sel && models.first != sel
                    raise Orocos::Spec::SpecError, "#{sel.name} is explicitely selected for #{required_model.name}, but only #{models.first.name} is available in the running deployments"
                end
                models
            elsif sel
                [sel]
            else
                models
            end
        end

        def task_instance_of(model, name)
            candidates = available_tasks.find_all { |model_name, task| model_name == model.name }
            if candidates.empty?
                raise Orocos::Spec::ConfigError, "no task of model #{model.name} is currently deployed"
            elsif candidates.size > 1
                raise Orocos::Spec::ConfigError, "more than one candidate task found for #{model.name}: #{candidates.join(", ")}"
            end
            candidates.first.last
        end

        def com_bus(bus)
            if task = communication_busses[bus.name]
                task
            else
                if handling_model = system.driver_for(bus.name)
                    communication_busses[bus.name] = handling_model.instanciate(self, bus.name)
                else
                    raise Spec::SpecError, "no device driver for #{bus.name.inspect}"
                end
            end
        end

        def connect(scope, connection_set)
            connections.concat(connection_set)
        end

        def get_project_deployments(name)
            result = Array.new
            Orocos.available_deployments.each do |deployment_name, pkg|
                if pkg.project_name == name
                    result << deployment_name
                end
            end
            result
        end

        def save_log_dir
            return if !File.directory?(log_dir)

            FileUtils.mkdir_p results_dir unless File.directory?(results_dir)

            if File.exists?(File.join(log_dir, "timestamp"))
                timestamp = File.read(File.join(log_dir, "timestamp"))
            else
                timestamp = Time.now.strftime('%Y%m%d-%H%M')
            end
            basename  = File.join(results_dir, timestamp)

            index = 0
            name = basename.dup
            while File.directory?(name)
                name = basename + ".#{index}"
                index += 1
            end

            STDERR.puts "moving the log directory to #{name}"
            FileUtils.mv log_dir, name
        end

        def create_log_dir
            FileUtils.mkdir_p log_dir
            File.open(File.join(log_dir, "timestamp"), 'w') do |io|
                io.write Time.now.strftime('%Y%m%d-%H%M')
            end
        end

        def run(*deployments)
            if deployments.last.kind_of?(Hash)
                options = deployments.pop
                options = Kernel.validate_options options, :from => nil

                if projects = options[:from]
                    Array[*projects].each do |project_name|
                        deployments.concat(get_project_deployments(project_name))
                    end
                end
            end

            # Save the current log directory
            save_log_dir
            # ... and create a new one
            create_log_dir

            # Now start the modules
            Dir.chdir(log_dir) do
                deployments = deployments.to_set.to_a
                deployments << Hash[:wait => 5, :output => '%m-log.txt']
                Orocos::Process.spawn(*deployments) do
                    available_tasks.clear
                    available_models.clear
                    tasks.clear

                    Orocos.each_task do |task|
                        model = task.getModelName
                        available_tasks << [model, task]
                        available_models << model
                    end

                    @connections = Array.new
                    # Instanciate all required subsystems
                    @instances = toplevel.map do |name, sys|
                        sys.instanciate(self, name)
                    end

                    yield if block_given?
                end
            end
        end

        def pretty_print(pp)
            pp.text "Instance selection:"
            pp.nest(2) do
                instances.each do |sys|
                    pp.breakable
                    sys.pretty_print(pp)
                end
            end

            pp.breakable
            pp.breakable
            pp.text "Connections"
            pp.nest(2) do
                connections.each do |outp, inp, policy|
                    pp.breakable
                    pp.text "#{outp.task.name}.#{outp.name}#{"[D]" if outp.kind_of?(DynamicPortStub)} => #{inp.task.name}.#{inp.name}#{"[D]" if inp.kind_of?(DynamicPortStub)} (#{policy.inspect})"
                end
            end
        end
    end
end

