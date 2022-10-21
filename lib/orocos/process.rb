# frozen_string_literal: true

require "utilrb/pkgconfig"
require "orogen"
require "fcntl"
require "json"

module Orocos
    # Exception raised when there is no IOR registered for a given task name.
    class IORNotRegisteredError < Orocos::NotFound; end

    # Exception raised when the received IOR message is invalid.
    class InvalidIORMessage < Orocos::NotFound; end

    # The working directory that should be used by default in Orocos.run
    def self.default_working_directory
        @default_working_directory || Dir.pwd
    end

    # Resets the working directory that should be used by default in Orocos.run
    # to its default, that is the current directory at the time where Orocos.run
    # is called is used.
    def self.reset_working_directory
        @default_working_directory = nil
    end

    # Sets the working directory that should be used by default in Orocos.run.
    # By default, the current directory at the time where Orocos.run is called
    # is used.
    #
    # Use #reset_working_directory to use the default of using the current
    # directory.
    def self.default_working_directory=(value)
        value = File.expand_path(value)
        raise ArgumentError, "#{value} is not an existing directory" unless File.directory?(value)

        @default_working_directory = value
    end

    # The default commandline arguments that will be passed by default in Orocos.run
    def self.default_cmdline_arguments
        @default_cmdline_arguments || {}
    end

    # Resets the default arguments that should be used by default in Orocos.run
    # which is the default setting of the underlying oroGen components
    def self.reset_default_cmdline_arguments
        @default_cmdline_arguments = {}
    end

    # Sets the default commandline arguments that will be passed by default in Orocos.run
    #
    # Use #reset_default_arguments to use the default of the underlying oroGen components
    def self.default_cmdline_arguments=(value)
        raise ArgumentError, "Orocos::default_cmdline_arguments expects to be set as hash" unless default_cmdline_arguments.kind_of?(Hash)

        @default_cmdline_arguments = value
    end

    def self.tracing?
        !!@tracing_enabled
    end

    def self.tracing=(flag)
        @tracing_enabled = flag
    end

    def self.tracing_library_path
        File.join(Utilrb::PkgConfig.new("orocos-rtt-#{Orocos.orocos_target}").libdir, "liborocos-rtt-traces-#{Orocos.orocos_target}.so")
    end

    # call-seq:
    #   Orocos.run('mod1', 'mod2')
    #   Orocos.run('mod1', 'mod2', wait: false, output: '%m-%p.log')
    #   Orocos.run('mod1', 'mod2', wait: false, output: '%m-%p.log') do |mod1, mod2|
    #   end
    #
    # @overload Orocos.run 'mod1', 'mod2'
    #   Starts a list of deployments. The deployment names are as given to the
    #   'deployment' statement in oroGen
    #
    #   @param (see .parse_run_options)
    #   @yield a block that is evaluated, ensuring that all tasks and processes
    #     are killed when the execution flow leaves the block. The block is given
    #     to {Orocos.guard}
    #
    # @overload Orocos.run 'mod1', 'mod2' => 'prefix'
    #   Starts a list of deployments. The prefix is prepended to all tasks in
    #   the 'mod2' deployment. The deployment names are as given to the
    #   'deployment' statement in oroGen
    #
    #   @param (see .parse_run_options)
    #   @yield a block that is evaluated, ensuring that all tasks and processes
    #     are killed when the execution flow leaves the block. The block is given
    #     to {Orocos.guard}
    #
    # @overload Orocos.run 'mod1', 'mod2' => 'prefix', 'project::Task' => 'task_name'
    #   Starts a list of deployments. The prefix is prepended to all tasks in
    #   the 'mod2' deployment, and a process is spawned to deploy a single task
    #   of model 'project::Task' (as defined in oroGen). task_name in this case
    #   becomes the task's name, as can be resolved by Orocos.get.
    #
    #   @param (see Process.parse_run_options)
    #   @yield a block that is evaluated, ensuring that all tasks and processes
    #     are killed when the execution flow leaves the block. The block is given
    #     to {Orocos.guard}
    #
    # Valid options are:
    # wait::
    #   wait that number of seconds (can be floating-point) for the
    #   processes to be ready. If it did not start into the provided
    #   timeout, an Orocos::NotFound exception raised.
    # output::
    #   redirect the process output to the given file. The %m and %p
    #   patterns will be replaced by respectively the name and the PID of
    #   each process.
    # valgrind::
    #   start some or all the processes under valgrind. It can either be an
    #   array of process names (e.g. valgrind: ['p1', 'p2']) or 'true'.
    #   In the first case, the listed processes will be added to the list of
    #   processes to start (if they are not already in it) and will be
    #   started under valgrind. In the second case, all processes are
    #   started under valgrind.
    # valgrind_options::
    #   an array of options that should be passed to valgrind, e.g.
    #
    #     valgrind_options: ["--track-origins=yes"]
    # cmdline_args::
    #   When command line arguments are available to deployments, they can be
    #   set using the following option:
    #      cmdline_args: { "sd-domain" => '_robot._tcp', "prefix" => "test" }
    #   This will be mapped to '--sd-domain=_robot._tcp --prefix=test'
    #
    #   Existing commandline arguments:
    #   --sd-domain
    #   the service discovery domain in which this process should be published
    #   This is only supported by deployments and orogen if the service_discovery
    #   package has been installed along with orogen
    #   The sd domain is of the format: <name>.<suffix> where the suffix has to
    #   be one of _tcp or _udp
    #
    def self.run(*args, **options, &block)
        Process.run(*args, **options, &block)
    end

    # Deprecated. Use Orocos.run instead.
    def self.spawn(*args, &block)
        STDERR.puts "#{caller(1)}: Orocos.spawn is deprecated, use Orocos.run instead"
        run(*args, &block)
    end

    # Base class for process representation objects
    class ProcessBase
        # The process name
        # @return [String]
        attr_reader :name
        # The deployment oroGen model
        # @return [OroGen::Spec::Deployment]
        attr_reader :model
        # @deprecated
        # For backward compatibility only
        def orogen;
            model
        end
        # A set of mappings from task names in the deployment model to the
        # actual name in the running process
        attr_reader :name_mappings
        # The set of [task_name, port_name] that represent the ports being
        # currently logged by this process' default logger
        attr_reader :logged_ports
        # The set of task contexts for this process. This is valid only after
        # the process is actually started
        attr_reader :tasks
        attr_reader :ior_mappings

        def initialize(name, model, name_mappings: {})
            @name = name
            @model = model
            @name_mappings = {}
            self.name_mappings = name_mappings
            @logged_ports = Set.new
            @tasks = []
            @ior_mappings = nil
            @ior_message = ""
            @ior_read_fd = nil
        end

        # Sets a batch of name mappings
        # @see map_name
        def name_mappings=(mappings)
            mappings.each do |old, new|
                map_name old, new
            end
        end

        # Require that to rename the task called +old+ in this deployment to
        # +new+ during execution
        #
        # @see name_mappings name_mappings=
        def map_name(old, new)
            name_mappings[old] = new
        end

        # @api private
        #
        # use a mapping if exists
        def get_mapped_name(name)
            name_mappings[name] || name
        end

        # Returns the name of the tasks that are running in this process
        #
        # See also #each_task
        def task_names
            unless model
                raise Orocos::NotOrogenComponent,
                      "#{name} does not seem to have been generated by orogen"
            end
            model.task_activities.map do |deployed_task|
                name = deployed_task.name
                get_mapped_name(name)
            end
        end

        # Enumerate the TaskContext instances of the tasks that are running in
        # this process.
        #
        # See also #task_names
        def each_task
            return enum_for(:each_task) unless block_given?

            task_names.each do |name|
                yield(task(name))
            end
        end

        # Returns the TaskContext instance for a task that runs in this process,
        # or raises Orocos::NotFound.
        def task(task_name)
            full_name = "#{name}_#{task_name}"
            if (result = tasks.find { |t| [task_name, full_name].include?(t.basename) })
                return result
            end

            ior = ior_for(task_name) || ior_for(full_name)
            unless ior
                raise Orocos::IORNotRegisteredError,
                      "no IOR is registered for #{task_name}"
            end

            Orocos::TaskContext.new(ior, process: self)
        end

        def register_task(task)
            @tasks.delete_if { |t| t.name == task.name }
            @tasks << task
        end

        def ior_for(task_name)
            @ior_mappings&.fetch(task_name, nil)
        end

        # Requires all known ports of +self+ to be logged by the default logger
        def log_all_ports(options = {})
            @logged_ports |= Orocos.log_all_process_ports(self, options)
        end

        @@logfile_indexes = {}

        # Computes the default log file name for a given orocos name
        def default_log_file_name(orocos_name)
            orocos_name[/.*(?=_[L|l]ogger)/] || orocos_name
        end

        # @api private
        #
        # Sets up the default logger of this process
        def setup_default_logger(logger = default_logger, log_file_name: default_log_file_name(logger.basename), remote: false, log_dir: Orocos.default_working_directory)
            if remote
                index = (@@logfile_indexes[log_file_name] ||= -1) + 1
                @@logfile_indexes[log_file_name] = index
                log_file_path = "#{log_file_name}.#{index}.log"
            else
                index = 0
                while File.file?(log_file_path = File.join(log_dir, "#{log_file_name}.#{index}.log"))
                    index += 1
                end
            end
            logger.property("file").write(log_file_path)
            logger
        end

        # @api private
        #
        # @return [String] the name of the default logger for this process
        def default_logger_name
            candidates = model.task_activities
                              .find_all { |d| d.task_model.name == "logger::Logger" }
                              .map { |c| name_mappings[c.name] || c.name }

            if candidates.size > 1
                if t = candidates.find { |c| c.name == "#{process.name}_Logger" }
                    t.name
                end
            elsif candidates.size == 1
                candidates.first
            end
        end

        # Overrides the default logger usually autodetected by #default_logger
        attr_writer :default_logger

        # @return [#log,false] the logger object that should be used, by
        #    default, to log data coming out of this process, or false if none
        #    can be found
        def default_logger
            return @default_logger unless @default_logger.nil?

            if logger_name = default_logger_name
                begin
                    @default_logger = TaskContext.get logger_name
                rescue Orocos::NotFound
                    Orocos.warn "no default logger defined on #{name}, tried #{logger_name}"
                    @default_logger = false # use false to mark "can not find"
                end
            else
                Orocos.warn "cannot determine the default logger name for process #{name}" if Orocos.warn_for_missing_default_loggers?
                @default_logger = false
            end

            @default_logger
        end

        # @api private
        #
        # Applies a prefix to this process' task names and returns the names
        #
        # @param [OroGen::Spec::Deployment] model the deployment model
        # @param [String,nil] prefix the prefix string, no prefix is going to be
        #   applied if it is nil
        #
        # @return [Hash<String,String>] the name mappings that should be applied
        #   when spawning the process
        def self.resolve_prefix(model, prefix)
            name_mappings = {}
            if prefix
                model.task_activities.each do |act|
                    name_mappings[act.name] = "#{prefix}#{act.name}"
                end
            end
            name_mappings
        end

        # Read the IOR pipe and parse the received message, closing the read file
        # descriptor when end of file is reached.
        #
        # @return [nil, Hash<String, String>] when eof is reached and the message is valid
        #   return a { task name => ior } hash. If the process dies or a IO::WaitReadable
        #   is raised, returns nil.
        def resolve_running_tasks
            return unless alive?

            begin
                loop do
                    @ior_message += @ior_read_fd.read_nonblock(4096)
                end
            rescue IO::WaitReadable
                nil
            rescue EOFError
                @ior_read_fd.close
                load_and_validate_ior_message(@ior_message)
            end
        end

        # Waits the running tasks resolution for a given amount of time.
        #
        # @param [nil, Boolean, Float] timeout when nil, this method blocks until all the
        #   running tasks are resolved or the process crashes. When given a number, it
        #   block for the given amount of time in milliseconds. When given a boolean, false
        #   is equivalent as passing 0 as argument, and true is equivalent to passing nil.
        # @return [Hash<String, String>] mappings of { task name => IOR }
        # @raise Orocos::NotFound if the process dies during execution
        # @raise Orocos::InvalidIORMessage if the message received is invalid
        def wait_running(timeout = nil, &block)
            return block.call if block_given?
            return @ior_mappings if @ior_mappings

            start_time = Time.now
            timeout = transform_timeout(timeout)
            deadline = start_time + timeout unless timeout == Float::INFINITY
            got_alive = alive?
            loop do
                @ior_mappings = resolve_running_tasks
                return @ior_mappings if @ior_mappings
                break if timeout < Time.now - start_time

                raise Orocos::NotFound, "#{name} was started but crashed" if got_alive && !alive?

                time_until_deadline = [deadline - Time.now, 0].max if deadline
                IO.select([@ior_read_fd], nil, nil, time_until_deadline)
            end

            raise Orocos::NotFound, "cannot get a running #{name} module" unless alive?
        end

        def transform_timeout(timeout)
            return timeout if timeout.kind_of?(Numeric)

            return Float::INFINITY if timeout.nil? || timeout == true

            0
        end

        # Load and validate the ior message read from the IOR pipe.
        #
        # @param [String] message the ior message read from the pipe
        # @return [Hash<String, String>, nil] the parsed ior message as a
        #   { task name => ior} hash, or nil if the message could not be parsed.
        # @raise Orocos::InvalidIORMessage raised if any task name present in the message
        #   is not present in the process' task names.
        def load_and_validate_ior_message(message)
            begin
                message = JSON.parse(message)
            rescue JSON::ParserError
                return
            end

            all_included = message.keys.all? { |name| task_names.include?(name) }
            return message if all_included

            raise Orocos::InvalidIORMessage,
                  "the following tasks were present on the ior message but werent in "\
                  "the process task names: #{message.keys - task_names}"
        end
    end

    # The representation of an Orocos process. It manages
    # starting the process and cleaning up when the process
    # dies.
    class Process < ProcessBase
        # The path to the binary file
        attr_reader :binfile
        # The component process ID
        attr_reader :pid

        # Returns the process that has the given PID
        #
        # @param [Integer] pid the PID whose process we are looking for
        # @return [nil,Process] the process object whose PID matches, or nil
        def self.from_pid(pid)
            if result = registered_processes[pid]
                result
            end
        end

        class << self
            # A map of existing running processes
            #
            # @return [{Integer=>Process}] a map from process IDs to the
            #   corresponding Process object
            attr_accessor :registered_processes
        end
        @registered_processes = {}

        # Registers a PID-to-process mapping.
        #
        # This can be called only for running processes
        #
        # @param [Process] process the process that should be registered
        # @return [void]
        # @see deregister each
        def self.register(process)
            raise ArgumentError, "cannot register a non-running process" unless process.alive?

            registered_processes[process.pid] = process
            nil
        end

        # Deregisters a process object that was registered with {register}
        #
        # @param [Integer] pid the process PID
        def self.deregister(pid)
            if process = registered_processes.delete(pid)
                process
            else raise ArgumentError, "no process registered for PID #{pid}"
            end
        end

        # Enumerates all registered processes
        #
        # @yieldparam [Process] process the process object
        def self.each(&block)
            registered_processes.each_value(&block)
        end

        # A string describing the host. It can be used to check if two processes
        # are running on the same host
        def host_id
            "localhost"
        end

        # Returns true if the process is located on the same host than the Ruby
        # interpreter
        def on_localhost?
            host_id == "localhost"
        end

        # Creates a new Process instance which will be able to
        # start and supervise the execution of the given Orocos
        # component
        #
        # @param [String] name the process name
        # @param [OroGen::Spec::Deployment] model the process deployment'
        #
        # @overload initialize(name, model_name = name)
        #   deprecated form
        #   @param [String] name the process name
        #   @param [String] model_name the name of the deployment model
        #
        def initialize(name, model = name,
            loader: Orocos.default_pkgconfig_loader,
            name_mappings: {})
            model = if model.respond_to?(:to_str)
                        loader.deployment_model_from_name(model)
                    else model
                    end

            @binfile =
                if loader.respond_to?(:find_deployment_binfile)
                    loader.find_deployment_binfile(model.name)
                else loader.available_deployments[model.name].binfile
                end
            super(name, model, name_mappings: name_mappings)
        end

        # Waits until the process dies
        #
        # This is valid only if the module has been started
        # under Orocos supervision, using {#spawn}
        def join
            return unless alive?

            begin
                _, exit_status = ::Process.waitpid2(pid)
                dead!(exit_status)
            rescue Errno::ECHILD
            end
        end

        # True if the process is running
        def alive?;
            !!@pid
        end

        # True if the process is running
        def running?;
            alive?
        end

        # Called externally to announce a component dead.
        def dead!(exit_status) # :nodoc:
            exit_status = (@exit_status ||= exit_status)
            if !exit_status
                Orocos.info "deployment #{name} exited, exit status unknown"
            elsif exit_status.success?
                Orocos.info "deployment #{name} exited normally"
            elsif exit_status.signaled?
                if @expected_exit == exit_status.termsig
                    Orocos.info "deployment #{name} terminated with signal #{exit_status.termsig}"
                elsif @expected_exit
                    Orocos.info "deployment #{name} terminated with signal #{exit_status.termsig} but #{@expected_exit} was expected"
                else
                    Orocos.error "deployment #{name} unexpectedly terminated with signal #{exit_status.termsig}"
                    Orocos.error "This is normally a fault inside the component, not caused by the framework."
                    Orocos.error "Try to run your component within gdb or valgrind with"
                    Orocos.error "  Orocos.run 'component', :gdb=>true"
                    Orocos.error "  Orocos.run 'component', :valgrind=>true"
                    Orocos.error "Make also sure that your component is installed by running 'amake' in it"
                end
            else
                Orocos.warn "deployment #{name} terminated with code #{exit_status.to_i}"
            end

            pid = @pid
            @pid = nil
            Process.deregister(pid)

            # Force unregistering the task contexts from CORBA naming
            # service
            # task_names.each do |name|
            #     puts "deregistering #{name}"
            #     Orocos::CORBA.unregister(name)
            # end
        end

        @@logfile_indexes = {}

        class TaskNameRequired < ArgumentError; end

        # Converts the options given to Orocos.run in a more normalized format
        #
        # It returns a triple (deployments, models, options) where
        #
        # * \c deployments is a map from a deployment name to a prefix that should
        #   be used to run this deployment. Prefixes are prepended to all task
        #   names in the deployment. It is set to nil if there are no prefix.
        # * \c models is a mapping from a oroGen model name to a name. It
        #   requests to start the default deployment for the model_name, using
        #   \c name as the task name
        # * options are options that should be passed to #spawn
        #
        # For instance, in
        #
        #   Orocos.run 'xsens', 'xsens_imu::Task' => 'imu', :valgrind => true
        #
        # One deployment called 'xsens' should be called with no prefix, the
        # default deployment for xsens_imu::Task should be started and the
        # corresponding task be renamed to 'imu' and all deployments should be
        # started with the :valgrind => true option. Therefore, the parsed
        # options would be
        #
        #   deployments = { 'xsens' => nil }
        #   models = { 'xsens_imu::Task' => 'imu' }
        #   options = { valgrind => true }
        #
        # In case multiple instances of a single model need to be started, the
        # names can be given as an Array. E.g.
        #
        #   Orocos.run 'xsens_imu::Task' => ['imu1', 'imu2']
        #
        def self.partition_run_options(*names, loader: Orocos.default_loader)
            mapped_names = {}
            mapped_names = names.pop if names.last.kind_of?(Hash)

            deployments = {}
            models = {}
            names.each { |n| mapped_names[n] = nil }
            mapped_names.each do |object, new_name|
                # If given a name, resolve to the corresponding oroGen spec
                # object
                if object.respond_to?(:to_str) || object.respond_to?(:to_sym)
                    object = object.to_s
                    begin
                        object = loader.task_model_from_name(object)
                    rescue OroGen::NotFound
                        begin
                            object = loader.deployment_model_from_name(object)
                        rescue OroGen::NotFound
                            raise OroGen::NotFound, "#{object} is neither a task model nor a deployment name"
                        end
                    end
                end

                case object
                when OroGen::Spec::TaskContext
                    raise TaskNameRequired, "you must provide a task name when starting a component by type, as e.g. Orocos.run 'xsens_imu::Task' => 'xsens'" unless new_name

                    models[object] = Array(new_name)
                when OroGen::Spec::Deployment
                    deployments[object] = new_name
                else raise ArgumentError, "expected a task context model or a deployment model, got #{object}"
                end
            end
            [deployments, models]
        end

        # @api private
        #
        # Apply default parameters for the wait option in {Orocos.run} and
        # {#spawn}
        def self.normalize_wait_option(wait, valgrind, gdb)
            if wait.nil?
                wait =
                    if valgrind then 600
                    elsif gdb then 600
                    else 20
                    end
            elsif !wait
                false
            else wait
            end
        end

        # @api private
        #
        # Separate the list of deployments from the spawn options in options
        # passed to {Orocos.run}
        #
        # Valid options are:
        # @param [Boolean,Numeric] wait
        #   wait that number of seconds (can be floating-point) for the
        #   processes to be ready. If it did not start into the provided
        #   timeout, an Orocos::NotFound exception raised. nil enables waiting
        #   for a predefined number of seconds that depend on the usage or not
        #   of valgrind and gdb. false disables waiting completely, and true
        #   waits forever.
        # @param [String] output
        #   redirect the process output to the given file. The %m and %p
        #   patterns will be replaced by respectively the name and the PID of
        #   each process.
        # @param [Boolean,Array<String>] valgrind
        #   start some or all the processes under valgrind. It can either be an
        #   array of process names (e.g. valgrind: ['p1', 'p2']) or 'true'.
        #   In the first case, the listed processes will be added to the list of
        #   processes to start (if they are not already in it) and will be
        #   started under valgrind. In the second case, all processes are
        #   started under valgrind.
        # @param [Array<String>] valgrind_options
        #   an array of options that should be passed to valgrind, e.g.
        #     valgrind_options: ["--track-origins=yes"]
        # @param [Boolean,Array<String>] gdb
        #   start some or all the processes under gdbserver. It can either be an
        #   array of process names (e.g. gdbserver: ['p1', 'p2']) or 'true'.
        #   In the first case, the listed processes will be added to the list of
        #   processes to start (if they are not already in it) and will be
        #   started under gdbserver. In the second case, all processes are
        #   started under gdbserver.
        # @param [Array<String>] gdb_options
        #   an array of options that should be passed to gdbserver
        #
        # @param [Hash<String>] cmdline_args
        #   When command line arguments are available to deployments, they can be
        #   set using the following option:
        #      cmdline_args: { "sd-domain" => '_robot._tcp', "prefix" => "test" }
        #   This will be mapped to '--sd-domain=_robot._tcp --prefix=test'
        #
        #   One notable command line argument is --sd-domain
        #   The service discovery domain in which this process should be published
        #   This is only supported by deployments and orogen if the service_discovery
        #   package has been installed along with orogen
        #   The sd domain is of the format: <name>.<suffix> where the suffix has to
        #   be one of _tcp or _udp
        #
        # @return [(Array<String,Hash,String,Hash>,Object)] the first returned
        #   element is a list of (deployment_name, name_mappings, process_name,
        #   spawn_options) tuples. The second element is the wait option (either
        #   a Numeric or false)
        def self.parse_run_options(*names, wait: nil, loader: Orocos.default_loader,
            valgrind: false, valgrind_options: {},
            gdb: false, gdb_options: {},
            log_level: nil,
            output: nil, oro_logfile: "orocos.%m-%p.txt",
            working_directory: Orocos.default_working_directory,
            cmdline_args: {})
            deployments, models = partition_run_options(*names, loader: loader)
            wait = normalize_wait_option(wait, valgrind, gdb)

            all_deployments = deployments.keys.map(&:name) + models.values.flatten
            valgrind = parse_cmdline_wrapper_option(
                "valgrind", valgrind, valgrind_options, all_deployments
            )
            gdb = parse_cmdline_wrapper_option(
                "gdbserver", gdb, gdb_options, all_deployments
            )
            log_level = parse_log_level_option(log_level, all_deployments)

            name_mappings = resolve_name_mappings(deployments, models)
            processes = name_mappings.map do |deployment_name, mappings, name|
                output = (output&.gsub "%m", name)

                spawn_options = Hash[
                    working_directory: working_directory,
                    output: output,
                    valgrind: valgrind[name],
                    gdb: gdb[name],
                    cmdline_args: cmdline_args,
                    wait: false,
                    log_level: log_level[name],
                    oro_logfile: oro_logfile]
                [deployment_name, mappings, name, spawn_options]
            end
            [processes, wait]
        end

        # @api private
        #
        # Normalizes the log_level option passed to {Orocos.run}.
        #
        # @param [Hash,Symbol] options is given as a symbol, this is the log
        # level that should be applied to all deployments. Otherwise, it is a
        # hash from a process name to the log level that should be applied for
        # this particular deployment
        # @param [Array<String>] all_deployments the name of all deployments
        # @return [Hash<String,Symbol>] a hash from a name in all_deployments to
        #   the log level for that deployment
        def self.parse_log_level_option(options, all_deployments)
            if !options.respond_to?(:to_hash)
                all_deployments.each_with_object({}) { |name, h| h[name] = options; }
            else
                options
            end
        end

        # @api private
        #
        # Checks that the given command can be resolved
        def self.has_command?(cmd)
            if File.file?(cmd) && File.executable?(cmd)
                nil
            else
                system("which #{cmd} > /dev/null 2>&1")
            end
        end

        # @api private
        #
        # Normalizes the options for command line wrappers such as gdb and
        # valgrind as passed to {Orocos.run}
        #
        # @overload parse_cmdline_wrapper_option(cmd, enable, cmd_options, deployments)
        #   @param [String] cmd the wrapper command string
        #   @param [Boolean] enable whether the wrapper should be enabled or not
        #   @param [Hash] options additional options to pass to the wrapper
        #   @param [Array<String>] deployments the deployments on which the
        #     wrapper should be activated
        #
        # @overload parse_cmdline_wrapper_option(cmd, deployments, cmd_options, all_deployments)
        #   @param [String] cmd the wrapper command string
        #   @param [Array<String>] deployments the name of the deployments on which
        #     the wrapper should be used.
        #   @param [Hash] options additional options to pass to the wrapper
        #   @param [Array<String>] all_deployments ignored in this form
        #
        # @overload parse_cmdline_wrapper_option(cmd, deployments_to_cmd_options, cmd_options, all_deployments)
        #   @param [String] cmd the wrapper command string
        #   @param [Hash<String,Array<String>>] deployments_to_cmd_options
        #     mapping from name of deployments to the list of additional options
        #     that should be passed to the wrapper
        #   @param [Hash] options additional options to pass to the wrapper
        #   @param [Array<String>] all_deployments ignored in this form
        #
        def self.parse_cmdline_wrapper_option(cmd, deployments, options, all_deployments)
            return {} unless deployments

            raise "'#{cmd}' option is specified, but #{cmd} seems not to be installed" unless has_command?(cmd)

            unless deployments.respond_to?(:to_hash)
                if deployments.respond_to?(:to_str)
                    deployments = [deployments]
                elsif !deployments.respond_to?(:to_ary)
                    deployments = all_deployments
                end

                deployments = deployments.each_with_object({}) { |name, h| h[name] = options; }
            end
            deployments.each_key do |name|
                raise ArgumentError, "#{name}, selected to be executed under #{cmd}, is not a known deployment/model" unless all_deployments.include?(name)
            end
        end

        # @api private
        #
        # Resolve the 'prefix' options given to {Orocos.run} into an exhaustive
        # task name mapping
        #
        # @param [Array<(OroGen::Spec::Deployment,String)>] deployments the list
        #   of deployments that should be started along with a prefix string
        #   that should be prepended to the deployment's tasks
        # @param [Array<(OroGen::Spec::TaskContext,String)>] models a list of
        #   task context models that should be deployed, along with the task
        #   name that should be used for these models.
        # @return [Array<(String,Hash,String)>] a tuple of the name of a binary,
        #   the name mappings that should be used when spawning this binary and
        #   the desired process name.
        def self.resolve_name_mappings(deployments, models)
            processes = []
            processes += deployments.map do |deployment, prefix|
                mapped_name   = deployment.name
                name_mappings = {}
                if prefix
                    name_mappings = ProcessBase.resolve_prefix(deployment, prefix)
                    mapped_name = "#{prefix}#{deployment.name}"
                end

                [deployment.name, name_mappings, mapped_name]
            end
            models.each do |model, desired_names|
                desired_names = [desired_names] unless desired_names.kind_of? Array
                desired_names.each do |desired_name|
                    process_name = OroGen::Spec::Project.default_deployment_name(model.name)
                    name_mappings = Hash[
                        process_name => desired_name,
                        "#{process_name}_Logger" => "#{desired_name}_Logger"]

                    processes << [process_name, name_mappings, desired_name]
                end
            end
            processes
        end

        # @deprecated use {Orocos.run} directly instead
        def self.run(*args, **options)
            unless Orocos.initialized?
                # try to initialize orocos before bothering the user
                Orocos.initialize
            end
            raise "CORBA layer is not initialized! There might be problem with the installation." unless Orocos::CORBA.initialized?

            begin
                process_specs, wait = parse_run_options(*args, **options)

                # Then spawn them, but without waiting for them
                processes = process_specs.map do |deployment_name, name_mappings, name, spawn_options|
                    p = Process.new(name, deployment_name)
                    name_mappings.each do |old, new|
                        p.map_name old, new
                    end
                    p.spawn(spawn_options)
                    p
                end

                # Finally, if the user required it, wait for the processes to run
                if wait
                    timeout = if wait.kind_of?(Numeric)
                                  wait
                              else Float::INFINITY
                              end
                    processes.each { |p| p.wait_running(timeout) }
                end
            rescue Exception => original_error
                # Kill the processes that are already running
                if processes
                    begin
                        kill(processes.map { |p| p if p.running? }.compact)
                    rescue Exception => e
                        Orocos.warn "failed to kill the started processes, you will have to kill them yourself"
                        Orocos.warn e.message
                        e.backtrace.each do |l|
                            Orocos.warn "  #{l}"
                        end
                        raise original_error
                    end
                end
                raise
            end

            if block_given?
                Orocos.guard(*processes) do
                    yield(*processes)
                end
            else
                processes
            end
        end

        # Kills the given processes
        #
        # @param [Array<#kill,#join>] processes a list of processes to kill
        # @param [Boolean] wait whether the method should wait for the processes
        #   to die or not
        def self.kill(processes, wait = true)
            processes.each { |p| p.kill if p.running? }
            processes.each(&:join) if wait
        end

        def self.gdb_base_port=(port)
            @@gdb_port = port - 1
        end

        @@gdb_port = 30_000
        def self.allocate_gdb_port
            @@gdb_port += 1
        end

        VALID_LOG_LEVELS = %i[debug info warn error fatal disable].freeze

        CommandLine = Struct.new :env, :command, :args, :working_directory

        # Massages various spawn parameters into the actual deployment command line
        #
        # @return [CommandLine]
        def command_line(
            working_directory: Orocos.default_working_directory,
            log_level: nil,
            cmdline_args: {},
            tracing: Orocos.tracing?, gdb: nil, valgrind: nil,
            name_service_ip: Orocos::CORBA.name_service_ip
        )

            result = CommandLine.new({}, nil, [], working_directory)
            result.command = binfile

            result.env["LD_PRELOAD"] = Orocos.tracing_library_path if tracing
            if log_level
                valid_levels = %i[debug info warn error fatal disable]
                if valid_levels.include?(log_level)
                    result.env["BASE_LOG_LEVEL"] = log_level.to_s.upcase
                else
                    raise ArgumentError, "'#{log_level}' is not a valid log level." +
                                         " Valid options are #{valid_levels}."
                end
            end
            result.env["ORBInitRef"] = "NameService=corbaname::#{name_service_ip}" if name_service_ip

            cmdline_args = cmdline_args.dup
            cmdline_args[:rename] ||= []
            name_mappings.each do |old, new|
                cmdline_args[:rename].push "#{old}:#{new}"
            end

            # Command line arguments have to be of type --<option>=<value>
            # or if <value> is nil a valueless option, i.e. --<option>
            cmdline_args.each do |option, value|
                if value
                    if value.respond_to?(:to_ary)
                        value.each do |v|
                            result.args.push "--#{option}=#{v}"
                        end
                    else
                        result.args.push "--#{option}=#{value}"
                    end
                else
                    result.args.push "--#{option}"
                end
            end

            if gdb
                result.args.unshift(result.command)
                gdb = Process.allocate_gdb_port if gdb == true
                result.args.unshift("0.0.0.0:#{gdb}")
                result.command = "gdbserver"
            elsif valgrind
                result.args.unshift(result.command)
                result.command = "valgrind"
            end

            result
        end

        # Spawns this process
        #
        # @param [Symbol] log_level the log level under which the process should
        #   be run. Must be one of {VALID_LOG_LEVELS}
        # @param [String] working_directory the working directory
        # @param [String] oro_logfile the name of the RTT-generated logfile.
        #   %m will be replaced by the process' name and %p by its PID
        # @param [String] prefix a prefix that should be prepended to all tasks
        #   in the process
        # @param [Boolean] tracing whether the tracing library
        #   {Orocos.tracing_library_path} should be preloaded before executing the
        #   process
        # @param [#get] name_service a name service object that should be used
        #   to resolve the tasks
        # @param [Boolean,Numeric] wait if true, the method will wait forever
        #   for the tasks to be available. If false, it will not wait at all. If
        #   nil, a sane default will be used (the default depends on whether the
        #   process is executed under valgrind or gdb). Finally, if a numerical
        #   value is provided, this value will be used as timeout (in seconds)
        # @param [Boolean,Array<String>] gdb whether the process should be
        #   executed under the supervision of gdbserver. Setting this option to
        #   true will enable gdb support. Setting it to an array of strings will
        #   specify a list of arguments that should be passed to gdbserver. This
        #   is obviously incompatible with the valgrind option. A warning
        #   message is issued, that describes how to connect to the gdbserver
        #   instance.
        # @param [Boolean,Array<String>] valgrind whether the process should be
        #   executed under the supervision of valgrind. Setting this option to
        #   true will enable valgrind support. Setting it to an array of strings will
        #   specify a list of arguments that should be passed to valgrind
        #   itself. This is obviously incompatible with the gdb option.
        def spawn(
            log_level: nil, working_directory: Orocos.default_working_directory,
            cmdline_args: {},
            oro_logfile:  "orocos.%m-%p.txt",
            prefix: nil, tracing: Orocos.tracing?,
            wait: nil,
            output: nil,
            gdb: nil, valgrind: nil,
            name_service: Orocos::CORBA.name_service
        )

            raise "#{name} is already running" if alive?

            Orocos.info "starting deployment #{name}"

            # Setup mapping for prefixed tasks in Process class
            prefix_mappings = ProcessBase.resolve_prefix(model, prefix)
            name_mappings = prefix_mappings.merge(self.name_mappings)
            self.name_mappings = name_mappings

            if wait.nil?
                wait =
                    if valgrind then 600
                    elsif gdb then 600
                    else 20
                    end
            end

            cmdline_args = cmdline_args.dup
            cmdline_args[:rename] ||= []
            name_mappings.each do |old, new|
                cmdline_args[:rename].push "#{old}:#{new}"
            end

            if valgrind
                cmdline_wrapper = "valgrind"
                cmdline_wrapper_options =
                    if valgrind.respond_to?(:to_ary)
                        valgrind
                    else []
                    end
            elsif gdb
                cmdline_wrapper = "gdbserver"
                cmdline_wrapper_options =
                    if gdb.respond_to?(:to_ary)
                        gdb
                    else []
                    end
                gdb_port = Process.allocate_gdb_port
                cmdline_wrapper_options << "localhost:#{gdb_port}"
            end

            ENV["ORBInitRef"] = "NameService=corbaname::#{name_service.ip}" unless name_service.ip.empty?

            cmdline = [binfile]

            # check arguments for log_level
            if log_level
                valid_levels = %i[debug info warn error fatal disable]
                if valid_levels.include?(log_level)
                    log_level = log_level.to_s.upcase
                else
                    raise ArgumentError, "'#{log_level}' is not a valid log level." +
                                         " Valid options are #{valid_levels}."
                end
            end

            @ior_read_fd, ior_write_fd = IO.pipe
            read, write = IO.pipe
            @pid = fork do
                @ior_read_fd.close
                # Pass write file descriptor for the IOR pipe as a commandline argument
                cmdline_args["ior-write-fd"] = ior_write_fd.fileno

                ENV["LD_PRELOAD"] = Orocos.tracing_library_path if tracing

                pid = ::Process.pid
                real_name = get_mapped_name(name)

                ENV["BASE_LOG_LEVEL"] = log_level if log_level

                if output&.respond_to?(:to_str)
                    output_file_name = output
                                       .gsub("%m", real_name)
                                       .gsub("%p", pid.to_s)
                    output_file_name = File.expand_path(output_file_name, working_directory) if working_directory

                    output = File.open(output_file_name, "a")
                end

                if oro_logfile
                    oro_logfile = oro_logfile
                                  .gsub("%m", real_name)
                                  .gsub("%p", pid.to_s)
                    oro_logfile = File.expand_path(oro_logfile, working_directory) if working_directory
                    ENV["ORO_LOGFILE"] = oro_logfile
                else
                    ENV["ORO_LOGFILE"] = "/dev/null"
                end

                if output
                    STDERR.reopen(output)
                    STDOUT.reopen(output)
                end

                cmdline.unshift "--log-file=#{output_file_name}.valgrind" if output_file_name && valgrind

                if cmdline_wrapper
                    cmdline = cmdline_wrapper_options + cmdline
                    cmdline.unshift cmdline_wrapper
                end

                # Command line arguments have to be of type --<option>=<value>
                # or if <value> is nil a valueless option, i.e. --<option>
                cmdline_args&.each do |option, value|
                    if value
                        if value.respond_to?(:to_ary)
                            value.each do |v|
                                cmdline.push "--#{option}=#{v}"
                            end
                        else
                            cmdline.push "--#{option}=#{value}"
                        end
                    else
                        cmdline.push "--#{option}"
                    end
                end

                read.close
                ::Process.setpgrp
                begin
                    exec(*cmdline, ior_write_fd => ior_write_fd, chdir: working_directory)
                rescue Exception
                    write.write("FAILED")
                end
            end
            Process.register(self)

            ior_write_fd.close

            write.close
            raise "cannot start #{name}" if read.read == "FAILED"

            Orocos.warn "process #{name} has been started under gdbserver, port=#{gdb_port}. The components will not be functional until you attach a GDB to the started server" if gdb

            if wait
                timeout = if wait.kind_of?(Numeric)
                              wait
                          elsif wait
                              Float::INFINITY
                          end
                wait_running(timeout)
            end
        end

        # Resolve all the tasks present on the process, creating a new Orocos::TaskContext
        # if the task is not deployed yet.
        #
        # @param [Orocos::Process] process the process object
        # @return [Hash<String, Orocos::TaskContext>] hash with
        #   { task name => task context objet }
        # @raise Orocos::IORNotRegisteredError when an IOR is not registered for the given
        #   task name.
        # @raise Orocos::NotFound if the process dies during execution
        # @raise Orocos::InvalidIORMessage if the message received is invalid
        def self.resolve_all_tasks(process)
            process.task_names.each_with_object({}) do |task_name, resolved_tasks|
                resolved_tasks[task_name] = process.task(task_name)
            end
        end

        # See #Orocos::Process.resolve_all_tasks
        def resolve_all_tasks
            Orocos::Process.resolve_all_tasks(self)
        end

        SIGNAL_NUMBERS = {
            "SIGABRT" => 1,
            "SIGINT" => 2,
            "SIGKILL" => 9,
            "SIGSEGV" => 11
        }.freeze

        # Tries to stop and cleanup the provided task. Returns true if it was
        # successful, and false otherwise
        def self.try_task_cleanup(task)
            begin
                task.stop(false)
                task.cleanup(false) if task.model&.needs_configuration?
            rescue StateTransitionFailed
            end

            task.each_port(&:disconnect_all)

            true
        rescue Exception => e
            Orocos.warn "clean shutdown of #{task.name} failed: #{e.message}"
            e.backtrace.each do |line|
                Orocos.warn line
            end
            false
        end

        # Kills the process either cleanly by requesting a shutdown if signal ==
        # nil, or forcefully by using UNIX signals if signal is a signal name.
        def kill(wait = true, signal = nil, cleanup: !signal, hard: false)
            tpid = pid
            return unless tpid # already dead

            signal ||=
                if hard
                    "SIGKILL"
                else
                    "SIGINT"
                end

            # Stop all tasks and disconnect the ports
            if cleanup
                clean_shutdown = true
                begin
                    tasks.each do |task|
                        unless self.class.try_task_cleanup(task)
                            clean_shutdown = false
                            break
                        end
                    end
                rescue Orocos::NotFound, Orocos::NoModel
                    # We're probably still starting the process. Just go on and
                    # signal it
                    clean_shutdown = false
                end
                Orocos.warn "clean shutdown of process #{name} failed" unless clean_shutdown
            end

            expected_exit = nil
            if signal
                Orocos.warn "sending #{signal} to #{name}" unless expected_exit

                signal = "SIG#{signal}" if signal.respond_to?(:to_str) && signal !~ /^SIG/

                expected_exit ||=
                    if signal.kind_of?(Integer) then signal
                    else SIGNAL_NUMBERS[signal] || signal
                    end

                @expected_exit = expected_exit
                begin
                    ::Process.kill(signal, tpid)
                rescue Errno::ESRCH
                    # Already exited
                    return
                end
            end

            if wait
                join
                if @exit_status&.signaled?
                    if !expected_exit
                        Orocos.warn "#{name} unexpectedly exited with signal #{@exit_status.termsig}"
                    elsif @exit_status.termsig != expected_exit
                        Orocos.warn "#{name} was expected to quit with signal #{expected_exit} but terminated with signal #{@exit_status.termsig}"
                    end
                end
            end
        end
    end

    # Enumerates the Orocos::Process objects that are currently available in
    # this Ruby instance
    def self.each_process(&block)
        Process.each(&block)
    end

    # Evaluates a block, ensuring that a set of processes or tasks are killed
    # when the control flow leaves it
    def self.guard(*processes_or_tasks)
        yield
    rescue Interrupt
    rescue Exception => e
        Orocos.warn "killing running task contexts and deployments because of unhandled exception"
        Orocos.warn "  #{e.backtrace[0]}: #{e.message}"
        e.backtrace[1..-1].each do |line|
            Orocos.warn "    #{line}"
        end
        raise
    ensure
        processes, tasks = processes_or_tasks.partition do |obj|
            obj.kind_of?(Orocos::Process)
        end

        processes = each_process.to_a if processes.empty?
        unless tasks.empty?
            processes.each do |p|
                tasks -= p.each_task.to_a
            end
        end

        # NOTE: Process#kill stops all the tasks from the process first, so
        # that's fine.
        tasks.each do |t|
            Orocos.info "guard: stopping task #{t.name}"
            Orocos::Process.try_task_cleanup(t)
        end
        processes.each do |p|
            if p.running?
                Orocos.info "guard: stopping process #{p.name}"
                p.kill(false)
            end
        end
        processes.each do |p|
            if p.running?
                Orocos.info "guard: joining process #{p.name}"
                p.join
            end
        end
    end
end
