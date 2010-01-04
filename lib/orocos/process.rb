require 'utilrb/pkgconfig'
require 'orogen'
require 'fcntl'

module Orocos
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
    def self.run(*args, &block)
        Process.spawn(*args, &block)
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
        attr_reader :orogen
        # The set of task contexts for this process. This is valid only after
        # the process is actually started
        attr_reader :tasks

	def self.from_pid(pid)
	    ObjectSpace.enum_for(:each_object, Orocos::Process).find { |mod| mod.pid == pid }
	end

        # Creates a new Process instance which will be able to
        # start and supervise the execution of the given Orocos
        # component
        def initialize(name)
            @name  = name
            @tasks = []
            begin
                @pkg = Utilrb::PkgConfig.new("orogen-#{name}")
            rescue Utilrb::PkgConfig::NotFound => e
                raise NotFound, "#{name} does not exist or isn't found by pkg-config\ncheck your PKG_CONFIG_PATH environment var. Current value is #{ENV['PKG_CONFIG_PATH']}"
            end

            # Load the orogen's description
            orogen_project = Orocos::Generation::TaskLibrary.load(@pkg, @pkg.deffile)
            @orogen = orogen_project.deployers.find do |d|
                d.name == name
            end

            # Load the needed toolkits
            Shellwords.split(pkg.toolkits).each do |name|
                Orocos::CORBA.load_toolkit(name)
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
	    rescue Errno::ECHILD
	    end

            dead!
        end
        
        # True if the process is running
        def alive?; !!@pid end
        # True if the process is running
        def running?; alive? end

        # Called externally to announce a component dead.
	def dead! # :nodoc:
	    @pid = nil 

            # Force unregistering the task contexts from CORBA naming
            # service
            task_names.each do |name|
                Orocos::CORBA.unregister(name)
            end
	end
        
        # Deprecated
        #
        # Use Orocos.run directly instead
        def self.spawn(*names)
            if !Orocos::CORBA.initialized?
                raise "CORBA layer is not initialized, did you forget to call 'Orocos.initialize' ?"
            end

            if names.last.kind_of?(Hash)
                options = names.pop
            end

            names = names.to_set
            begin
                options = validate_options options, :wait => 2, :output => nil, :valgrind => false

                valgrind = options[:valgrind]
                if valgrind.respond_to?(:to_ary)
                    valgrind = valgrind.dup
                    names |= valgrind.to_set
                elsif valgrind
                    valgrind = names.dup
                else
                    valgrind = []
                end

                # First thing, do create all the named processes
                processes = names.map { |name| [name, Process.new(name)] }
                # Then spawn them, but without waiting for them
                processes.each do |name, p|
                    output = if options[:output]
                                 options[:output].gsub '%m', name
                             end

                    p.spawn(:output => output, :valgrind => valgrind.include?(name))
                end

                # Finally, if the user required it, wait for the processes to run
                if options[:wait]
                    timeout = if options[:wait].kind_of?(Numeric)
                                  options[:wait]
                              end
                    processes.each { |_, p| p.wait_running(timeout) }
                end
            rescue Exception
                # Kill the processes that are already running
                if processes
                    kill(processes.map { |name, p| p if p.running? }.compact)
                end
                raise
            end

            processes = processes.map { |_, p| p }
            if block_given?
                Orocos.guard do
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
	    Orocos.debug { "Spawning module #{name}" }

            options = Kernel.validate_options options, :output => nil, :valgrind => nil
            output   = options[:output]
            valgrind = !!options[:valgrind]

            ENV['ORBInitRef'] = "NameService=corbaname::#{CORBA.name_service}"

            module_bin = pkg.binfile
            if !module_bin # assume an older orogen version
                module_bin = "#{pkg.exec_prefix}/bin/#{name}"
            end
            cmdline = [module_bin]

	    if output.respond_to?(:to_str)
		output_format = output.to_str
		output = Tempfile.open('orocos-rb', File.dirname(output_format))
	    end
		    
	    read, write = IO.pipe
	    @pid = fork do 
		if output_format
		    output_file_name = output_format.
			gsub('%m', name).
			gsub('%p', ::Process.pid.to_s)
		    FileUtils.mv output.path, output_file_name
		end
		
		if output
		    STDERR.reopen(output)
		    STDOUT.reopen(output)
		end

                if valgrind
                    if output_file_name
                        cmdline.unshift "--log-file=#{output_file_name}.valgrind"
                    end
                    cmdline.unshift "valgrind"
                end

		read.close
		write.fcntl(Fcntl::F_SETFD, 1)
		::Process.setpgrp
                begin
                    exec(*cmdline)
                rescue Exception => e
                    write.write("FAILED")
                end
	    end

	    write.close
	    if read.read == "FAILED"
		raise "cannot start #{name}"
	    end
        end

        # Wait for the module to be started. If timeout is 0, the function
        # returns immediatly, with a false return value if the module is not
        # started yet and a true return value if it is started.
        #
        # Otherwise, it waits for the process to start for the specified amount
        # of seconds. It will throw Orocos::NotFound if the process was not
        # started within that time.
        #
        # If timeout is nil, the method will wait indefinitely
	def wait_running(timeout = nil)
	    if timeout == 0
		return nil if !pid
                
                # Get any task name from that specific deployment, and check we
                # can access it. If there is none
                task_names.all? do |task_name|
                    begin
                        task(task_name)
                        Orocos.debug "#{task_name} is reachable, assuming #{name} is up and running"
                        true
                    rescue Orocos::NotFound
                        Orocos.debug "could not access #{task_name}, #{name} is not running yet ..."
                        false
                    end
                end
	    else
                start_time = Time.now
                got_pid = false
                while true
                    if wait_running(0)
                        return true
                    elsif timeout && timeout < (Time.now - start_time)
                        raise Orocos::NotFound, "cannot get a running #{name} module"
                    end

                    got_pid = true if pid
                    if got_pid && !pid
                        raise Orocos::NotFound, "#{name} was started but crashed"
                    end
                    sleep 0.1
                end
	    end
	end

        # Kills the process by using UNIX signals
        def kill(wait = true, signal = 'INT')
            ::Process.kill("SIG#{signal}", pid)
            join if wait
        end

        # Returns the name of the tasks that are running in this process
        #
        # See also #each_task
        def task_names
            if !orogen
                raise Orocos::NotOrogenComponent, "#{name} does not seem to have been generated by orogen"
            end
            orogen.task_activities.map { |act| act.name }
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
            if result = tasks.find { |t| t.name == task_name || t.name == full_name}
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
        ObjectSpace.each_object(Orocos::Process) do |p|
            yield(p) if p.alive?
        end
    end

    # call-seq:
    #   guard do ... end
    #
    # All processes started in the provided block will be automatically killed
    def self.guard
        yield
    ensure
        tasks = ObjectSpace.enum_for(:each_object, Orocos::TaskContext)
        tasks.each do |t|
            begin
                t.stop if t.running?
            rescue
            end
        end

        processes = ObjectSpace.enum_for(:each_object, Orocos::Process)
        processes.each { |mod| mod.kill if mod.running? }
        processes.each { |mod| mod.join if mod.running? }
    end
end

trap('SIGCHLD') do
    begin
	while dead = Process.wait(-1, Process::WNOHANG)
	    if mod = Orocos::Process.from_pid(dead)
                mod.dead!
            end
	end
    rescue Errno::ECHILD
    end
end


