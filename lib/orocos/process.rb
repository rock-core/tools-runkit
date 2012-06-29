require 'utilrb/pkgconfig'
require 'orogen'
require 'fcntl'

module Orocos
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
        if !File.directory?(value)
            raise ArgumentError, "#{value} is not an existing directory"
        end
        @default_working_directory = value
    end

    # call-seq:
    #   Orocos.run('mod1', 'mod2')
    #   Orocos.run('mod1', 'mod2', :wait => false, :output => '%m-%p.log')
    #   Orocos.run('mod1', 'mod2', :wait => false, :output => '%m-%p.log') do |mod1, mod2|
    #   end
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
    #   array of process names (e.g. :valgrind => ['p1', 'p2']) or 'true'.
    #   In the first case, the listed processes will be added to the list of
    #   processes to start (if they are not already in it) and will be
    #   started under valgrind. In the second case, all processes are
    #   started under valgrind.
    # valgrind_options::
    #   an array of options that should be passed to valgrind, e.g.
    #
    #     :valgrind_options => ["--track-origins=yes"]
    # cmdline_args::
    #   When command line arguments are available to deployments, they can be 
    #   set using the following option:
    #      :cmdline_args => { "sd-domain" => '_robot._tcp', "prefix" => "test" }
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
    # 
    def self.run(*args, &block)
        Process.run(*args, &block)
    end

    # Deprecated. Use Orocos.run instead.
    def self.spawn(*args, &block)
        STDERR.puts "#{caller(1)}: Orocos.spawn is deprecated, use Orocos.run instead"
        run(*args, &block)
    end

    # The representation of an Orocos process. It manages
    # starting the process and cleaning up when the process
    # dies.
    class Process
        # The component name
        attr_reader :name
        # The component PkgConfig instance
        attr_reader :pkg
        # The component process ID
        attr_reader :pid
        # The orogen description
        def orogen; model end
        # The Orocos::Generation::StaticDeployment instance that represents
        # this process
        attr_reader :model
        # The set of task contexts for this process. This is valid only after
        # the process is actually started
        attr_reader :tasks

        # A mapping from the original (= declared in the deployment
        # specification) to the new name (= the one in which the task has been
        # started)
        attr_reader :name_mappings

	def self.from_pid(pid)
	    ObjectSpace.enum_for(:each_object, Orocos::Process).find { |mod| mod.pid == pid }
	end

        # A string describing the host. It can be used to check if two processes
        # are running on the same host
        def host_id
            'localhost'
        end

        # Returns true if the process is located on the same host than the Ruby
        # interpreter
        def on_localhost?
            host_id == 'localhost'
        end

        # Creates a new Process instance which will be able to
        # start and supervise the execution of the given Orocos
        # component
        def initialize(name)
            @name  = name
            @tasks = []
            @name_mappings = Hash.new
            @pkg = Orocos.available_deployments[name]
            if !pkg
                raise NotFound, "deployment #{name} does not exist or its pkg-config orogen-#{name} is not found by pkg-config\ncheck your PKG_CONFIG_PATH environment var. Current value is #{ENV['PKG_CONFIG_PATH']}"
            end

            # Load the orogen's description
            orogen_project = Orocos.master_project.using_project(pkg.project_name)
            @model = orogen_project.deployers.find do |d|
                d.name == name
            end
	    if !model
	    	Orocos.warn "cannot locate deployment #{name} in #{orogen_project.name}"
	    end
        end


        # Waits until the process dies
        #
        # This is valid only if the module has been started
        # under rOrocos supervision, using #spawn
        def join
            return unless alive?

	    begin
		::Process.waitpid(pid)
                exit_status = $?
                dead!(exit_status)
	    rescue Errno::ECHILD
	    end
        end
        
        # True if the process is running
        def alive?; !!@pid end
        # True if the process is running
        def running?; alive? end

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
                    Orocos.warn "deployment #{name} unexpectedly terminated with signal #{exit_status.termsig}"
                end
            else
                Orocos.warn "deployment #{name} terminated with code #{exit_status.to_i}"
            end

	    @pid = nil 

            # Force unregistering the task contexts from CORBA naming
            # service
            # task_names.each do |name|
            #     puts "deregistering #{name}"
            #     Orocos::CORBA.unregister(name)
            # end
	end

	@@logfile_indexes = Hash.new

        # The set of [task_name, port_name] that represent the ports being
        # currently logged by this process' default logger
        attr_reader :logged_ports

        # Requires all known ports of +self+ to be logged by the default logger
        def log_all_ports(options = Hash.new)
            @logged_ports |= Orocos.log_all_process_ports(self, options)
        end

        def setup_default_logger(options)
            Orocos.setup_default_logger(self, options)
        end

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
        def self.parse_run_options(*names)
            options = names.last.kind_of?(Hash) ? names.pop : Hash.new
            options, mapped_names = filter_options options,
                :wait => nil, :output => nil, :working_directory => Orocos.default_working_directory,
                :gdb => false, :gdb_options => [],
                :valgrind => false, :valgrind_options => [],
                :cmdline_args => nil,
                :oro_logfile => nil

            deployments, models = Hash.new, Hash.new
            names.each { |n| mapped_names[n] = nil }
            mapped_names.each do |name, new_name|
                if Orocos.available_task_models[name.to_s]
                    if !new_name
                        raise ArgumentError, "you must provide a task name when starting a component by type, as e.g. Orocos.run 'xsens_imu::Task' => 'xsens'"
                    end
                    models[name.to_s] = new_name.to_s
                else
                    deployments[name.to_s] = (new_name.to_s if new_name)
                end
            end

            if options[:wait].nil?
                options[:wait] =
                    if options[:valgrind] then 60
                    elsif options[:gdb] then 600
                    else 20
                    end
            end

            if options[:cmdline_args].nil?
                options[:cmdline_args] = Hash.new
            end
            return deployments, models, options
        end

        def self.parse_cmdline_wrapper_option(cmd, deployments, options, all_deployments)
            if !deployments
                return Hash.new
            end

            # Check if the valgrind option is specified, no matter if 
            # set to true or false
            if !system("which #{cmd}")
                raise "'#{cmd}' option is specified, but #{cmd} seems not to be installed"
            end

            if !deployments.respond_to?(:to_hash)
                if deployments.respond_to?(:to_str)
                    deployments = [deployments]
                elsif !deployments.respond_to?(:to_ary)
                    deployments = all_deployments
                end

                deployments.inject(Hash.new) { |h, name| h[name] = options; h }
            else
                deployments
            end
        end
        
        # Deprecated
        #
        # Use Orocos.run directly instead
        def self.run(*names)
            if !Orocos.initialized?
                #try to initialize orocos before bothering the user
                Orocos.initialize
            end
            if !Orocos::CORBA.initialized?
                raise "CORBA layer is not initialized! There might be problem with the installation."
            end

            begin
                deployments, models, options = parse_run_options(*names)
		    
                if valgrind = options[:valgrind]
                    valgrind = parse_cmdline_wrapper_option('valgrind', options[:valgrind], options[:valgrind_options], deployments.keys + models.values)
                else
                    valgrind = Hash.new
                end

                if gdb = options[:gdb]
                    gdb = parse_cmdline_wrapper_option('gdbserver', options[:gdb], options[:gdb_options], deployments.keys + models.values)
                else
                    gdb = Hash.new
                end

                # First thing, do create all the named processes
                processes = []
                processes += deployments.map do |process_name, prefix|
                    process = Process.new(process_name)
                    if prefix
                        process.task_names.each do |task_name|
                            process.map_name(task_name, "#{prefix}_#{task_name}")
                        end
                        process_name = "#{prefix}_#{process_name}"

                        # Main prefix option overwrites prefix
                        if options[:cmdline_args][:prefix]
                            raise "Script prefix option: '#{prefix}' is set. An additional prefix cmdline argument cannot be passed"
                        end
                    end

                    [process_name, process]
                end
                processes += models.map do |model_name, desired_name|
                    process = Process.new(Orocos::Generation.default_deployment_name(model_name))
                    process.map_name(Orocos::Generation.default_deployment_name(model_name), desired_name)
                    process.map_name("#{Orocos::Generation.default_deployment_name(model_name)}_Logger", "#{desired_name}_Logger")
                    [desired_name, process]
                end
                # Then spawn them, but without waiting for them
                processes.each do |name, p|
                    output = if options[:output]
                                 options[:output].gsub '%m', name
                             end

                    p.spawn(:working_directory => options[:working_directory],
                            :output => output,
                            :valgrind => valgrind[name],
                            :gdb => gdb[name],
                            :cmdline_args => options[:cmdline_args],
                            :wait => false,
                            :oro_logfile => options[:oro_logfile])
                end

                # Finally, if the user required it, wait for the processes to run
                if options[:wait]
                    timeout = if options[:wait].kind_of?(Numeric)
                                  options[:wait]
                              end
                    processes.each { |_, p| p.wait_running(timeout) }
                end

            rescue Exception => original_error
                # Kill the processes that are already running
                if processes
		    begin
			kill(processes.map { |name, p| p if p.running? }.compact)
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

            processes = processes.map { |_, p| p }
            if block_given?
                Orocos.guard(*processes) do
                    yield(*processes)
                end
            else
                processes
            end
        end
        
        # Kills the given processes. If +wait+ is true, will also wait for the
        # processes to be destroyed.
        def self.kill(processes, wait = true)
            processes.each { |p| p.kill if p.running? }
            if wait
                processes.each { |p| p.join }
            end
        end

        def self.gdb_base_port=(port)
            @@gdb_port = port - 1
        end

        @@gdb_port = 30000
        def self.allocate_gdb_port
            @@gdb_port += 1
        end

        # Spawns this process
        #
        # Valid options:
        # output::
        #   if non-nil, the process output is redirected towards that
        #   file. Special patterns %m and %p are replaced respectively by the
        #   process name and the process PID value.
        # valgrind::
        #   if true, the process is started under valgrind. If :output is set
        #   as well, valgrind's output is redirected towards the value of output
        #   with a .valgrind extension added.
        def spawn(options = Hash.new)
	    raise "#{name} is already running" if alive?
	    Orocos.info "starting deployment #{name}"

            options = Kernel.validate_options options, :output => nil,
                :gdb => nil, :valgrind => nil,
                :working_directory => nil,
                :cmdline_args => Hash.new, :wait => nil,
                :oro_logfile => "orocos.%m-%p.txt"

            # Setup mapping for prefixed tasks in Process class
            prefix = options[:cmdline_args][:prefix]

            if prefix
                model.task_activities.each do |task|
                    map_name(task.name, "#{prefix}#{task.name}")
                end
            end

            # If possible, check that we won't clash with an already running
            # process
            task_names.each do |name|
                if TaskContext.reachable?(name)
                    raise ArgumentError, "there is already a running task called #{name}, are you starting the same component twice ?"
                end
            end

            if !options.has_key?(:wait)
                if options[:valgrind]
                    options[:wait] = 60
                elsif options[:gdb]
                    options[:wait] = 600
                else
                    options[:wait] = 20
                end
            end

            cmdline_args = options[:cmdline_args].dup

            if name_mappings.size > 0
                cmdline_args['rename'] = []
            end
            name_mappings.each do |old, new|
                cmdline_args['rename'].push "#{old}:#{new}"
            end

            output   = options[:output]
            oro_logfile = options[:oro_logfile]

            if options[:valgrind]
                cmdline_wrapper = 'valgrind'
                cmdline_wrapper_options =
                    if options[:valgrind].respond_to?(:to_ary)
                        options[:valgrind]
                    else []
                    end
            elsif options[:gdb]
                cmdline_wrapper = 'gdbserver'
                cmdline_wrapper_options =
                    if options[:gdb].respond_to?(:to_ary)
                        options[:gdb]
                    else []
                    end
                gdb_port = Process.allocate_gdb_port
                cmdline_wrapper_options << "localhost:#{gdb_port}"
            end

            workdir  = options[:working_directory]

	    if CORBA.name_service
		ENV['ORBInitRef'] = "NameService=corbaname::#{CORBA.name_service}"
	    end

            module_bin = pkg.binfile
            if !module_bin # assume an older orogen version
                module_bin = "#{pkg.exec_prefix}/bin/#{name}"
            end
            cmdline = [module_bin]
		    
	    read, write = IO.pipe
	    @pid = fork do 
                pid = ::Process.pid
                real_name = (name_mappings[name] || name)

		if output && output.respond_to?(:to_str)
		    output_file_name = output.
			gsub('%m', real_name).
			gsub('%p', pid.to_s)
                    if workdir
                        output_file_name = File.expand_path(output_file_name, workdir)
                    end

                    output = File.open(output_file_name, 'a')
		end

                if oro_logfile
                    oro_logfile = oro_logfile.
                        gsub('%m', real_name).
                        gsub('%p', pid.to_s)
                    if workdir
                        oro_logfile = File.expand_path(oro_logfile, workdir)
                    end
                    ENV['ORO_LOGFILE'] = oro_logfile
                else
                    ENV['ORO_LOGFILE'] = "/dev/null"
                end

		if output
		    STDERR.reopen(output)
		    STDOUT.reopen(output)
		end

                if output_file_name && options[:valgrind]
                    cmdline.unshift "--log-file=#{output_file_name}.valgrind"
                end

                if cmdline_wrapper
                    cmdline = cmdline_wrapper_options + cmdline
                    cmdline.unshift cmdline_wrapper
                end
                
                # Command line arguments have to be of type --<option>=<value>
                # or if <value> is nil a valueless option, i.e. --<option>
                if cmdline_args
                    cmdline_args.each do |option, value|
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
                end
		read.close
		write.fcntl(Fcntl::F_SETFD, 1)
		::Process.setpgrp
                begin
                    if workdir
                        Dir.chdir(workdir)
                    end
                    exec(*cmdline)
                rescue Exception => e
                    write.write("FAILED")
                end
	    end

	    write.close
	    if read.read == "FAILED"
		raise "cannot start #{name}"
	    end

            if options[:gdb]
                Orocos.warn "process #{name} has been started under gdbserver, port=#{gdb_port}. The components will not be functional until you attach a GDB to the started server"
            end

            if options[:wait]
                timeout = if options[:wait].kind_of?(Numeric)
                              options[:wait]
                          end
                wait_running(timeout)
            end
        end

	def self.wait_running(process, timeout = nil)
	    if timeout == 0
		return nil if !process.alive?
                
                # Get any task name from that specific deployment, and check we
                # can access it. If there is none
                all_reachable = process.task_names.all? do |task_name|
                    if TaskContext.reachable?(task_name)
                        Orocos.debug "#{task_name} is reachable"
                        true
                    else
                        Orocos.debug "could not access #{task_name}, #{name} is not running yet ..."
                        false
                    end
                end
                if all_reachable
                    Orocos.info "all tasks of #{process.name} are reachable, assuming it is up and running"
                end
                all_reachable
	    else
                start_time = Time.now
                got_alive = process.alive?
                while true
		    if wait_running(process, 0)
			break
                    elsif not timeout
                        break
                    elsif timeout < Time.now - start_time
                        break
                    end

                    if got_alive && !process.alive?
                        raise Orocos::NotFound, "#{process.name} was started but crashed"
                    end
                    sleep 0.1
                end

                if process.alive?
                    return true
                else
                    raise Orocos::NotFound, "cannot get a running #{process.name} module"
                end
	    end
	end

        # Wait for the module to be started. If timeout is 0, the function
        # returns immediately, with a false return value if the module is not
        # started yet and a true return value if it is started.
        #
        # Otherwise, it waits for the process to start for the specified amount
        # of seconds. It will throw Orocos::NotFound if the process was not
        # started within that time.
        #
        # If timeout is nil, the method will wait indefinitely
	def wait_running(timeout = nil)
            Process.wait_running(self, timeout)
	end

        SIGNAL_NUMBERS = {
            'SIGABRT' => 1,
            'SIGINT' => 2,
            'SIGKILL' => 9,
            'SIGSEGV' => 11
        }

        # Tries to stop and cleanup the provided task. Returns true if it was
        # successful, and false otherwise
        def self.try_task_cleanup(task)
            begin
                task.stop(false)
                if task.model && task.model.needs_configuration?
                    task.cleanup(false)
                end
            rescue StateTransitionFailed
            end

            task.each_port do |port|
                port.disconnect_all
            end

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
        def kill(wait = true, signal = nil)
            return if !pid # already dead

            # Stop all tasks and disconnect the ports
            if !signal
                clean_shutdown = true
                begin
                    each_task do |task|
                        if !self.class.try_task_cleanup(task)
                            clean_shutdown = false
                            break
                        end
                    end
                rescue Orocos::NotFound, Orocos::NoModel
                    # We're probably still starting the process. Just go on and
                    # signal it
                    clean_shutdown = false
                end
                if !clean_shutdown
                    Orocos.warn "clean shutdown of process #{name} failed"
                end
            end

            expected_exit = nil
            if clean_shutdown
                expected_exit = signal = SIGNAL_NUMBERS['SIGINT']
	    else
                signal = SIGNAL_NUMBERS['SIGINT']
            end

            if signal 
                if !expected_exit
                    Orocos.warn "sending #{signal} to #{name}"
                end

                if signal.respond_to?(:to_str) && signal !~ /^SIG/
                    signal = "SIG#{signal}"
                end

                expected_exit ||=
                    if signal.kind_of?(Integer) then signal
                    else SIGNAL_NUMBERS[signal] || signal
                    end

                @expected_exit = expected_exit
                begin
                    ::Process.kill(signal, pid)
                rescue Errno::ESRCH
                    # Already exited
                    return
                end
            end

            if wait
                join
                if @exit_status && @exit_status.signaled?
                    if !expected_exit
                        Orocos.warn "#{name} unexpectedly exited with signal #{@exit_status.termsig}"
                    elsif @exit_status.termsig != expected_exit
                        Orocos.warn "#{name} was expected to quit with signal #{expected_exit} but terminated with signal #{@exit_status.termsig}"
                    end
                end
            end
        end

        # Require that to rename the task called +old+ in this deployment to
        # +new+ during execution
        def map_name(old, new)
            name_mappings[old] = new
        end

        # use a mapping if exists 
        def get_mapped_name(name)
            name_mappings[name] || name
        end

        # Returns the name of the tasks that are running in this process
        #
        # See also #each_task
        def task_names
            if !model
                raise Orocos::NotOrogenComponent, "#{name} does not seem to have been generated by orogen"
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
            task_names.each do |name|
                yield(task(name))
            end
        end

        # Returns the TaskContext instance for a task that runs in this process,
        # or raises Orocos::NotFound.
        def task(task_name)
            full_name = "#{name}_#{task_name}"
            if result = tasks.find { |t| t.name == task_name || t.name == full_name }
                return result
            end

            result = if task_names.include?(task_name)
                         TaskContext.get task_name, self
                     elsif task_names.include?(full_name)
                         TaskContext.get full_name, self
                     else
                         raise Orocos::NotFound, "no task #{task_name} defined on #{name}"
                     end

            @tasks << result
            result
        end
    end

    # Enumerates the Orocos::Process objects that are currently available in
    # this Ruby instance
    def self.each_process
        if !block_given?
            return enum_for(:each_process)
        end

        ObjectSpace.each_object(Orocos::Process) do |p|
            yield(p) if p.alive?
        end
    end

    # call-seq:
    #   guard { }
    #
    # All processes started in the provided block will be automatically killed
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

        if processes.empty?
            processes ||= ObjectSpace.enum_for(:each_object, Orocos::Process)
        end
        if !tasks.empty?
            processes.each do |p|
                tasks -= p.enum_for(:each_task).to_a
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

