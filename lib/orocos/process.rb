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
                raise e, "#{name} does not exist or isn't found by pkg-config\ncheck your PKG_CONFIG_PATH environment var. Current value is #{ENV['PKG_CONFIG_PATH']}"
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

        # Wait for the module to be started. If nohang is true, the function
        # returns immediatly, with a false return value if the module is not
        # started yet and a true return value if it is started. Otherwise, it
        # waits until the process is available
	def wait_running(nohang = false)
	    if nohang
		raise "module #{name} died" if !pid

                task_name = Orocos.components.find { |n| n =~ /^#{name}\.\w+$/ }
                if task_name
                    begin Orocos::TaskContext.get task_name
                    rescue Orocos::NotFound
                    end
                end
	    else
                while true
                    if wait_running(true)
                        return true
                    end
                    sleep 0.1
                end
	    end
	end

        def kill(wait = true)
            ::Process.kill('SIGINT', pid)
            join if wait
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


