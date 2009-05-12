require 'utilrb/pkgconfig'
require 'fcntl'

module Orocos
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

	def self.from_pid(pid)
	    ObjectSpace.enum_for(:each_object, Orocos::Process).find { |mod| mod.pid == pid }
	end

        # Creates a new Process instance which will be able to
        # start and supervise the execution of the given Orocos
        # component
        def initialize(name)
            @name = name
            begin
                @pkg = Utilrb::PkgConfig.new("orogen-#{name}")
            rescue Utilrb::PkgConfig::NotFound => e
                raise NotFound, "#{name} does not exist or isn't found by pkg-config\ncheck your PKG_CONFIG_PATH environment var. Current value is #{ENV['PKG_CONFIG_PATH']}"
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
        
        # True if the orocos component process is running
        def alive?; !!@pid end

        # Announce that, even though we did not detect it, the
        # process is actually dead.
	def dead! # :nodoc:
	    @pid = nil 

            # Force unregistering the task contexts from CORBA naming
            # service
            Orocos.task_names.
                grep(/^#{Regexp.quote(name)}_/).
                each { |task_name| Orocos::CORBA.unregister(task_name) }
	end
        
        # Spawns this process
        def spawn(output = nil)
	    raise "#{name} is already running" if alive?
	    Orocos.debug { "Spawning module #{name}" }

            module_bin = "#{@pkg.exec_prefix}/bin/#{name}"
            cmdline = [module_bin]

	    if output.respond_to?(:to_str)
		output_format = output.to_str
		output = Tempfile.open('orocos-rb', File.dirname(output_format))
	    end
		    
	    read, write = IO.pipe
	    @pid = fork do 
		if output_format
		    real_name = output_format.
			gsub('%m', name).
			gsub('%p', Process.pid.to_s)
		    FileUtils.mv output.path, real_name
		end
		
		if output
		    STDERR.reopen(output)
		    STDOUT.reopen(output)
		end

		read.close
		write.fcntl(Fcntl::F_SETFD, 1)
		::Process.setpgrp
		exec(*cmdline)
		write.write("FAILED")
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
                task_name = Orocos.task_names.find { |n| n =~ /^#{name}_\w+$/ }
                if task_name
                    begin
                        Orocos::TaskContext.get task_name
                        return true
                    rescue Orocos::NotFound
                        return false
                    end
                end
	    else
                start_time = Time.now
                while true
                    if wait_running(0)
                        return true
                    elsif timeout && timeout < (Time.now - start_time)
                        raise Orocos::NotFound, "cannot get a running #{name} module"
                    end

                    sleep 0.1
                end
	    end
	end

        def kill(wait = true, signal = 'INT')
            ::Process.kill("SIG#{signal}", pid)
            join if wait
        end

        def task_names
            Orocos.task_names.grep(/^#{Regexp.quote(name)}_/).
                map { |task_name| task_name.gsub(/^#{Regexp.quote(name)}_/, '') }
        end

        def task(task_name)
            task = TaskContext.get "#{name}_#{task_name}"
	    task.instance_variable_set(:@process, self)
	    task
        end
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


