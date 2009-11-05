require 'typelib'

module Orocos
    class << self
        attr_reader :registry

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

    def self.initialize
        Orocos::CORBA.init

        @registry = Typelib::Registry.new
        registry.import File.join(`orogen --base-dir`.chomp, 'orogen', 'orocos.tlb')

        # Load the name of all available task libraries
        if !available_task_libraries
            @available_task_libraries = Hash.new
            Utilrb::PkgConfig.each_package(/-tasks-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                tasklib_name = pkg_name.gsub(/-tasks-#{Orocos.orocos_target}$/, '')
                available_task_libraries[tasklib_name] = pkg
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
                puts "WARN: no logger defined on #{process.name}"
            end
        end
    end
end

