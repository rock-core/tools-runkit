require 'typelib'

module Orocos
    class << self
        # The Typelib::Registry instance that is the union of all the loaded
        # component's type registries
        attr_reader :registry

        # The set of orogen projects that are available, as a mapping from a
        # name into the project's orogen description file
        attr_reader :available_projects

        # The set of available deployments, as a mapping from the deployment
        # name into the Utilrb::PkgConfig object that represen it
        attr_reader :available_deployments

        # The set of available task libraries, as a mapping from the task
        # library name into the Utilrb::PkgConfig object that represent it
        attr_reader :available_task_libraries

        # The set of available task models, as a mapping from the model name
        # into the task library name that defines it
        attr_reader :available_task_models
    end

    def self.orocos_target
        if ENV['OROCOS_TARGET']
            ENV['OROCOS_TARGET']
        else
            'gnulinux'
        end
    end

    # Helper method for initialize
    def self.add_project_from(pkg) # :nodoc:
        if pkg.project_name.empty?
            Orocos.warn "#{pkg_name}.pc does not have a project_name field"
        elsif pkg.deffile.empty?
            Orocos.warn "#{pkg_name}.pc does not have a deffile field"
        else
            available_projects[pkg.project_name] = pkg.deffile
        end
    end

    # Initialize the Orocos communication layer and read all the oroGen models
    # that are available.
    def self.initialize
        Orocos::CORBA.init

        @registry = Typelib::Registry.new
        registry.import File.join(`orogen --base-dir`.chomp, 'orogen', 'orocos.tlb')

        @available_projects ||= Hash.new

        # Load the name of all available task libraries
        if !available_task_libraries
            @available_task_libraries = Hash.new
            Utilrb::PkgConfig.each_package(/-tasks-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                tasklib_name = pkg_name.gsub(/-tasks-#{Orocos.orocos_target}$/, '')
                available_task_libraries[tasklib_name] = pkg

                add_project_from(pkg)
            end
        end

        if !available_deployments
            @available_deployments = Hash.new
            Utilrb::PkgConfig.each_package(/^orogen-\w+$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                deployment_name = pkg_name.gsub(/^orogen-/, '')
                available_deployments[deployment_name] = pkg

                add_project_from(pkg)
                end
        end

        # Create a class_name => tasklib mapping for all task models available
        # on this sytem
        if !available_task_models
            @available_task_models = Hash.new
            available_task_libraries.each do |tasklib_name, tasklib_pkg|
                tasklib_pkg.task_models.split(",").
                    each { |class_name| available_task_models[class_name] = tasklib_name }
            end
        end
    end

    # This method assumes that #add_logger has been called at the end of each
    # static_deployment block.
    def self.log_all_ports(options = Hash.new)
        exclude_ports = options[:exclude_ports]
        exclude_types = options[:exclude_types]

        each_process do |process|
            begin
                logger = process.task 'Logger'
                report = logger.rtt_method 'reportPort'

                process.each_task do |task|
                    next if task == logger
                    task.each_port do |port|
                        next unless port.kind_of?(OutputPort)
                        next if exclude_ports && exclude_ports === port.name
                        next if exclude_types && exclude_types === port.type.name
                        Orocos.info "logging % 50s of type %s" % ["#{task.name}:#{port.name}", port.type.name]
                        report.call task.name, port.name
                    end
                end
                logger.file = "#{process.name}.log"
                logger.start

            rescue Orocos::NotFound
                STDERR.puts "WARN: no logger defined on #{process.name}"
            end
        end
    end

    # call-seq:
    #   Orocos.each_task do |task| ...
    #   end
    #
    # Enumerates the tasks that are currently available on this sytem (i.e.
    # registered on the name server). They are provided as TaskContext
    # instances.
    def self.each_task
        task_names.each do |name|
            task = begin TaskContext.get(name)
                   rescue Orocos::NotFound
                       CORBA.unregister(name)
                   end
            yield(task) if task
        end
    end
end

