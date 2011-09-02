require 'logger'
require 'utilrb/logger'
module Orocos
    extend Logger::Root("Orocos.rb", Logger::WARN)

    def self.log_all
        log_all_ports
        log_all_configuration
    end

    # This method assumes that #add_logger has been called at the end of each
    # static_deployment block.
    def self.log_all_ports(options = Hash.new)
        exclude_ports = options[:exclude_ports]
        exclude_types = options[:exclude_types]

        each_process do |process|
            process.log_all_ports(options)
        end
    end

    class << self
        attr_accessor :configuration_log_name
    end
    @configuration_log_name = "task_configuration"

    # The Pocolog::Logfiles object used by default by
    # Orocos.log_all_configuration. It will automatically be created by
    # Oroocs.configuration_log if Orocos.log_all_configuration is called without
    # an argument
    attr_writer :configuration_log

    # If Orocos.configuration_log is not set, it creates a new configuration log
    # file that will be used by default by Orocos.log_all_configuration. The log
    # file is named as Orocos.configuration_log_name ('task_configuration' by
    # default). This log file becomes the new default log file for all following
    # calls to Orocos.log_all_configuration
    def self.configuration_log
        if !HAS_POCOLOG
            raise ArgumentError, "the pocolog Ruby library is not available, configuration logging cannot be used"
        end
        @configuration_log ||= Pocolog::Logfiles.create(Orocos.configuration_log_name)
    end

    def self.log_all_configuration(logfile = nil)
        logfile ||= configuration_log
        each_process do |process|
            process.each_task do |t|
                t.log_all_configuration(logfile)
            end
        end
    end

    # Common implementation of log_all_ports for a single process
    #
    # This is shared by local and remote processes alike
    def self.log_all_process_ports(process, options = Hash.new)
        options, logger_options = Kernel.filter_options options,
            :tasks => nil, :exclude_ports => nil, :exclude_types => nil

        tasks = options[:tasks]
        exclude_ports = options[:exclude_ports]
        exclude_types = options[:exclude_types]

        if !(logger = setup_default_logger(process, logger_options))
            return Set.new
        end

        logged_ports = Set.new
        process.task_names.each do |task_name|
            task = TaskContext.get(task_name)
            next if task == logger
            next if tasks && !(tasks === task_name)

            task.each_output_port do |port|
                next if exclude_ports && exclude_ports === port.name
                next if exclude_types && exclude_types === port.type.name
                next if block_given? && !yield(port)

                Orocos.info "logging % 50s of type %s" % ["#{task.name}:#{port.name}", port.type.name]
                logged_ports << [task.name, port.name]
                logger.reportPort(task.name, port.name)
            end
        end
        if !logger.running?
            logger.start
        end

        logged_ports
    end

    @@logfile_indexes = Hash.new

    # Sets up the process' default logger component
    #
    # Returns true if there is a logger on this process, and false otherwise
    def self.setup_default_logger(process, options)
        options = Kernel.validate_options options,
            :remote => false, :log_dir => Dir.pwd

        is_remote     = options[:remote]
        log_dir       = options[:log_dir]

        logger =
            begin
                TaskContext.get "#{process.name}_Logger"
            rescue Orocos::NotFound
                Orocos.warn "no logger defined on #{process.name}"
                return
            end

        index = 0
        if options[:remote]
            index = (@@logfile_indexes[process.name] ||= -1) + 1
            @@logfile_indexes[process.name] = index
            logger.file = "#{process.name}.#{index}.log"
        else
            while File.file?( logfile = File.join(log_dir, "#{process.name}.#{index}.log"))
                index += 1
            end
            logger.file = logfile 
        end
        logger
    end
end

