require 'socket'
require 'fcntl'
module Orocos
    # A remote process management server. The ProcessServer allows to start/stop
    # and monitor the status of processes on a client/server way.
    #
    # Use ProcessClient to access a server
    class ProcessServer
        # Returns a unique directory name as a subdirectory of
        # +base_dir+, based on +path_spec+. The generated name
        # is of the form
        #   <base_dir>/a/b/c/YYYYMMDD-HHMM-basename
        # if <tt>path_spec = "a/b/c/basename"</tt>. A .<number> suffix
        # is appended if the path already exists.
        #
        # Shamelessly taken from Roby
	def self.unique_dirname(base_dir, path_spec, date_tag = nil)
	    if path_spec =~ /\/$/
		basename = ""
		dirname = path_spec
	    else
		basename = File.basename(path_spec)
		dirname  = File.dirname(path_spec)
	    end

	    date_tag ||= Time.now.strftime('%Y%m%d-%H%M')
	    if basename && !basename.empty?
		basename = date_tag + "-" + basename
	    else
		basename = date_tag
	    end

	    # Check if +basename+ already exists, and if it is the case add a
	    # .x suffix to it
	    full_path = File.expand_path(File.join(dirname, basename), base_dir)
	    base_dir  = File.dirname(full_path)

	    unless File.exists?(base_dir)
		FileUtils.mkdir_p(base_dir)
	    end

	    final_path, i = full_path, 0
	    while File.exists?(final_path)
		i += 1
		final_path = full_path + ".#{i}"
	    end

	    final_path
	end

        DEFAULT_OPTIONS = { :wait => false, :output => '%m-%p.txt' }
        DEFAULT_PORT = 20202

        # Start a standalone process server using the given options and port.
        # The options are passed to Orocos.run when a new deployment is started
        def self.run(options = DEFAULT_OPTIONS, port = DEFAULT_PORT)
            Orocos.disable_sigchld_handler = true
            Orocos.initialize
            new({ :wait => false }.merge(options), port).exec

        rescue Interrupt
        end

        # The startup options to be passed to Orocos.run
        attr_reader :options
        # The TCP port we should listen to
        attr_reader :port
        # A mapping from the deployment names to the corresponding Process
        # object.
        attr_reader :processes

        def initialize(options = DEFAULT_OPTIONS, port = DEFAULT_PORT)
            @options = options
            @port = port
            @processes = Hash.new
            @all_ios = Array.new
        end

        def each_client(&block)
            clients = @all_ios[2..-1]
            if clients
                clients.each(&block)
            end
        end

        # Main server loop. This will block and only return when CTRL+C is hit.
        #
        # All started processes are stopped when the server quits
        def exec
            Orocos.info "starting on port #{port}"
            server = TCPServer.new(nil, port)
            server.fcntl(Fcntl::FD_CLOEXEC, 1)
            com_r, com_w = IO.pipe
            @all_ios.clear
            @all_ios << server << com_r

            trap 'SIGCHLD' do
                begin
                    while dead = ::Process.wait(-1, ::Process::WNOHANG)
                        Marshal.dump([dead, $?], com_w)
                    end
                rescue Errno::ECHILD
                end
            end

            Orocos.info "process server listening on port #{port}"

            while true
                readable_sockets, _ = select(@all_ios, nil, nil)
                if readable_sockets.include?(server)
                    readable_sockets.delete(server)
                    socket = server.accept
                    socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
                    socket.fcntl(Fcntl::FD_CLOEXEC, 1)
                    Orocos.debug "new connection: #{socket}"
                    @all_ios << socket
                end

                if readable_sockets.include?(com_r)
                    readable_sockets.delete(com_r)
                    pid, exit_status =
                        begin Marshal.load(com_r)
                        rescue TypeError
                        end

                    process = processes.find { |_, p| p.pid == pid }
                    if process
                        process_name, process = *process
                        process.dead!(exit_status)
                        processes.delete(process_name)
                        Orocos.debug "announcing death: #{process_name}"
                        each_client do |socket|
                            begin
                                Orocos.debug "  announcing to #{socket}"
                                socket.write("D")
                                Marshal.dump([process_name, exit_status], socket)
                            rescue IOError
                                Orocos.debug "  #{socket}: IOError"
                            end
                        end
                    end
                end

                readable_sockets.each do |socket|
                    if !handle_command(socket)
                        Orocos.debug "#{socket} closed"
                        socket.close
                        @all_ios.delete(socket)
                    end
                end
            end

        rescue Exception => e
            if e.class == Interrupt # normal procedure
                Orocos.fatal "process server exited normally"
                return
            end

            Orocos.fatal "process server exited because of unhandled exception"
            Orocos.fatal "#{e.message} #{e.class}"
            e.backtrace.each do |line|
                Orocos.fatal "  #{line}"
            end

        ensure
            quit_and_join
        end

        # Helper method that stops all running processes
        def quit_and_join # :nodoc:
            Orocos.warn "stopping process server"
            processes.each_value do |p|
                Orocos.warn "killing #{p.name}"
                p.kill
            end

            each_client do |socket|
                socket.close
            end
            exit(0)
        end

        COMMAND_GET_INFO   = "I"
        COMMAND_MOVE_LOG   = "L"
        COMMAND_CREATE_LOG = "C"
        COMMAND_START      = "S"
        COMMAND_END        = "E"
        COMMAND_LOAD_PROJECT = "P"
        COMMAND_PRELOAD_TYPEKIT = "T"

        # Helper method that deals with one client request
        def handle_command(socket) # :nodoc:
            cmd_code = socket.read(1)
            raise EOFError if !cmd_code

            if cmd_code == COMMAND_LOAD_PROJECT
                project_name, _ = Marshal.load(socket)
                Orocos.debug "#{socket} requested project loading for project #{project_name}"
                begin
                    project = Orocos.master_project.load_orogen_project(project_name)
                    socket.write("Y")
                rescue Exception => e
                    Orocos.debug "loading project #{project_name} failed with #{e.message}"
                    socket.write("N")
                end

            elsif cmd_code == COMMAND_PRELOAD_TYPEKIT
                typekit_name, _ = Marshal.load(socket)
                Orocos.debug "#{socket} requested typekit loading for typekit #{typekit_name}"
                begin
                    Orocos::CORBA.load_typekit(typekit_name)
                    socket.write("Y")
                rescue Exception => e
                    Orocos.debug "loading typekit #{typekit_name} failed with #{e.message}"
                    socket.write("N")
                end

            elsif cmd_code == COMMAND_GET_INFO
                Orocos.debug "#{socket} requested system information"
                available_projects = Hash.new
                available_typekits = Hash.new
                Orocos.available_projects.each do |name, (pkg, deffile)|
                    available_projects[name] = File.read(deffile)
                    if pkg && pkg.type_registry && !pkg.type_registry.empty?
                        available_typekits[name] = File.read(pkg.type_registry)
                    end
                end
                available_deployments = Hash.new
                Orocos.available_deployments.each do |name, pkg|
                    available_deployments[name] = pkg.project_name
                end
                Marshal.dump([available_projects, available_deployments, available_typekits, ::Process.pid], socket)
            elsif cmd_code == COMMAND_MOVE_LOG
                Orocos.debug "#{socket} requested moving a log directory"
                begin
                    log_dir, results_dir = Marshal.load(socket)
                    log_dir     = File.expand_path(log_dir)
                    date_tag    = File.read(File.join(log_dir, 'time_tag')).strip
                    results_dir = File.expand_path(results_dir)
                    Orocos.debug "  #{log_dir} => #{results_dir}"
                    if File.directory?(log_dir)
                        dirname = Orocos::ProcessServer.unique_dirname(results_dir + '/', '', date_tag)
                        FileUtils.mv log_dir, dirname
                    end
                rescue Exception => e
                    Orocos.warn "failed to move log directory from #{log_dir} to #{results_dir}: #{e.message}"
                    if dirname
                        Orocos.warn "   target directory was #{dirname}"
                    end
                end

            elsif cmd_code == COMMAND_CREATE_LOG
                begin
                    Orocos.debug "#{socket} requested creating a log directory"
                    log_dir, time_tag = Marshal.load(socket)
                    log_dir     = File.expand_path(log_dir)
                    Orocos.debug "  #{log_dir}, time: #{time_tag}"
                    FileUtils.mkdir_p(log_dir)
                    File.open(File.join(log_dir, 'time_tag'), 'w') do |io|
                        io.write(time_tag)
                    end
                rescue Exception => e
                    Orocos.warn "failed to create log directory #{log_dir}: #{e.message}"
                    Orocos.warn "   #{e.backtrace[0]}"
                end

            elsif cmd_code == COMMAND_START
                name, options = Marshal.load(socket)
                options ||= Hash.new
                Orocos.debug "#{socket} requested startup of #{name} with #{options}"
                begin
                    p = Orocos.run(name, self.options.merge(options)).first
                    Orocos.debug "#{name} is started (#{p.pid})"
                    processes[name] = p
                    socket.write("Y")
                rescue Exception => e
                    Orocos.debug "failed to start #{name}: #{e.message}"
                    Orocos.debug "  " + e.backtrace.join("\n  ")
                    socket.write("N")
                end
            elsif cmd_code == COMMAND_END
                name = Marshal.load(socket)
                Orocos.debug "#{socket} requested end of #{name}"
                p = processes[name]
                if p
                    begin
                        p.kill(false)
                        socket.write("Y")
                    rescue Exception => e
                        socket.write("N")
                    end
                else
                    socket.write("N")
                end
            end

            true
        rescue EOFError
            false
        end
    end

    class RemoteMasterProject < Orocos::Generation::Component
        attr_reader :server

        def initialize(server)
            @server = server
            super()
        end

        def orogen_project_description(name)
            return nil, server.available_projects[name]
        end
    end

    # Easy access to a ProcessServer instance.
    #
    # Process servers allow to start/stop and monitor processes on remote
    # machines. Instances of this class provides access to remote process
    # servers.
    class ProcessClient
        # Emitted when an operation fails
        class Failed < RuntimeError; end
        class StartupFailed < RuntimeError; end

        # The socket instance used to communicate with the server
        attr_reader :socket

        # Mapping from orogen project names to the corresponding content of the
        # orogen files. These projects are the ones available to the remote
        # process server
        attr_reader :available_projects
        # Mapping from deployment names to the corresponding orogen project
        # name. It lists the deployments that are available on the remote
        # process server.
        attr_reader :available_deployments
        # Mapping from deployment names to the corresponding XML type registry
        # for the typekits available on the process server
        attr_reader :available_typekits
        # Mapping from a deployment name to the corresponding RemoteProcess
        # instance, for processes that have been started by this client.
        attr_reader :processes
        # The master oroGen project in which we load everything else. It is an
        # instance of RemoteMasterProject, to use the data we got from the
        # process server
        attr_reader :master_project

        # The hostname we are connected to
        attr_reader :host
        # The port on which we are connected on +hostname+
        attr_reader :port
        # The PID of the server process
        attr_reader :server_pid
        # A string that allows to uniquely identify this process server
        attr_reader :host_id

        def to_s
            "#<Oroocs::ProcessServer #{host}:#{port}>"
        end
        def inspect; to_s end

        # Connects to the process server at +host+:+port+
        def initialize(host = 'localhost', port = ProcessServer::DEFAULT_PORT)
            @host = host
            @port = port
            @socket =
                begin TCPSocket.new(host, port)
                rescue Errno::ECONNREFUSED => e
                    raise e.class, "cannot contact process server at '#{host}:#{port}': #{e.message}"
                end

            socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
            socket.fcntl(Fcntl::FD_CLOEXEC, 1)
            socket.write(ProcessServer::COMMAND_GET_INFO)

	    if !select([socket], [], [], 2)
	       raise "timeout while reading process server at '#{host}:#{port}'"
	    end
            info = begin Marshal.load(socket)
                   rescue EOFError
                       raise StartupFailed, "process server failed at '#{host}:#{port}'"
                   end

            @available_projects    = info[0]
            @available_deployments = info[1]
            @available_typekits    = info[2]
            @server_pid            = info[3]
            @master_project = RemoteMasterProject.new(self)
            @processes = Hash.new
            @death_queue = Array.new
            @host_id = "#{host}:#{port}:#{server_pid}"
        end

        # Loads the oroGen project definition called 'name' using the data the
        # process server sent us.
        def load_orogen_project(name)
            name = name.to_str
            if !available_projects[name]
                raise ArgumentError, "there is no orogen project called #{name} on #{host}:#{port}"
            end

            # Ask the process server to load the information about that project.
            # This reduces the process startup overhead quite heavily
            socket.write(ProcessServer::COMMAND_LOAD_PROJECT)
            Marshal.dump([name], socket)
            if !wait_for_ack
                raise ArgumentError, "process server could not load information about the project #{name}"
            end

            orogen = master_project.load_orogen_project(name)
            if master_project.has_typekit?(name)
                # Check that the typekit on the local machine exists and is
                # compatible
                local_project, _ = Orocos.available_projects[name]
                local_typekit =
                    if (registry_path = local_project.type_registry) && !registry_path.empty?
                        Typelib::Registry.import(registry_path, 'tlb')
                    end

                if local_typekit
                    registry = available_typekits[name]
                    begin
                        Typelib::Registry.from_xml(registry).merge(local_typekit)
                    rescue Exception => e
                        raise e.class, "failed to load the typekit of #{name} from #{host}:#{port}: #{e.message}"
                    end
                end
            end

            # Register it locally ...
            # TODO: check that any local definition matches
            Orocos.master_project.register_loaded_project(name, orogen)
        end

        # Returns the StaticDeployment instance that represents the remote
        # deployment +deployment_name+
        def load_orogen_deployment(deployment_name)
            project_name = available_deployments[deployment_name]
            if !project_name
                raise ArgumentError, "there is not deployment calle #{deployment_name} on #{host}:#{port}"
            end

            tasklib = load_orogen_project(project_name)
            deployment = tasklib.deployers.find { |d| d.name == deployment_name }
            if !deployment
                raise InternalError, "cannot find the deployment called #{deployment_name} in #{tasklib}. Candidates were #{tasklib.deployers.map(&:name).join(", ")}"
            end
            deployment
        end

        def preload_typekit(name)
            socket.write(ProcessServer::COMMAND_PRELOAD_TYPEKIT)
            Marshal.dump([name], socket)
            if !wait_for_ack
                raise ArgumentError, "process server could not load information about the project #{name}"
            end
        end

        def disconnect
            socket.close
        end

        def wait_for_ack
            reply = socket.read(1)
            if reply == "D"
                queue_death_announcement
                wait_for_ack
            elsif reply == "Y"
                return true
            else
                return false
            end
        end

        # Starts the given deployment on the remote server, without waiting for
        # it to be ready.
        #
        # Returns a RemoteProcess instance that represents the process on the
        # remote side.
        #
        # Raises Failed if the server reports a startup failure
        def start(deployment_name, options = Hash.new)
            project_name = available_deployments[deployment_name]
            if !project_name
                raise ArgumentError, "unknown deployment #{deployment_name}"
            end
            self.load_orogen_project(project_name)

            socket.write(ProcessServer::COMMAND_START)
            Marshal.dump([deployment_name, options], socket)
            if !wait_for_ack
                raise Failed, "failed to start #{deployment_name}"
            end

            processes[deployment_name] = RemoteProcess.new(deployment_name, self)
        end

        # Requests that the process server moves the log directory at +log_dir+
        # to +results_dir+
        def save_log_dir(log_dir, results_dir)
            socket.write(ProcessServer::COMMAND_MOVE_LOG)
            Marshal.dump([log_dir, results_dir], socket)
        end

        # Creates a new log dir, and save the given time tag in it (used later
        # on by save_log_dir)
        def create_log_dir(log_dir, time_tag)
            socket.write(ProcessServer::COMMAND_CREATE_LOG)
            Marshal.dump([log_dir, time_tag], socket)
        end

        def queue_death_announcement
            @death_queue.push Marshal.load(socket)
        end

        # Waits for processes to terminate. +timeout+ is the number of
        # milliseconds we should wait. If set to nil, the call will block until
        # a process terminates
        #
        # Returns a hash that maps deployment names to the Process::Status
        # object that represents their exit status.
        def wait_termination(timeout = nil)
            if @death_queue.empty?
                reader = select([socket], nil, nil, timeout)
                return if !reader
                while reader
                    data = socket.read(1)
                    if !data
                        return
                    elsif data != "D"
                        raise "unexpected message #{data} from process server"
                    end
                    queue_death_announcement
                    reader = select([socket], nil, nil, 0)
                end
            end

            result = Hash.new
            @death_queue.each do |name, status|
                Orocos.debug "#{name} died"
                if p = processes.delete(name)
                    p.dead!
                    result[p] = status
                else
                    Orocos.warn "process server reported the exit of '#{name}', but no process with that name is registered"
                end
            end
            @death_queue.clear

            result
        end

        # Requests to stop the given deployment
        #
        # The call does not block until the process has quit. You will have to
        # call #wait_termination to wait for the process end.
        def stop(deployment_name)
            socket.write(ProcessServer::COMMAND_END)
            Marshal.dump(deployment_name, socket)

            if !wait_for_ack
                raise Failed, "failed to quit #{deployment_name}"
            end
        end
    end

    # Representation of a remote process started with ProcessClient#start
    class RemoteProcess
        # The deployment name
        attr_reader :name
        # The ProcessClient instance that gives us access to the remote process
        # server
        attr_reader :process_client
        # The Orocos::Generation::StaticDeployment instance that describes this
        # process
        attr_reader :model
        # A string describing the host. It can be used to check if two processes
        # are running on the same host
        def host_id
            process_client.host_id
        end
        # True if this process is located on the same machine than the ruby
        # interpreter
        def on_localhost?
            process_client.host == 'localhost'
        end

        def initialize(name, process_client)
            @name = name
            @process_client = process_client
            @alive = true
            @model = process_client.load_orogen_deployment(name)
        end

        def log_all_ports(options = Hash.new)
            Orocos.log_all_ports(self, options)
        end

        def setup_logger(options = Hash.new)
            Orocos.setup_default_logger(self, options)
        end

        # Called to announce that this process has quit
        def dead!
            @alive = false
        end

        def task_names
            model.task_activities.map(&:name)
        end


        # Stops the process
        def kill(wait = true)
            raise ArgumentError, "cannot call RemoteProcess#kill(true)" if wait
            process_client.stop(name)
        end

        # Wait for the 
        def join
            raise NotImplementedError, "RemoteProcess#join is not implemented"
        end

        # True if the process is running. This is an alias for running?
        def alive?; @alive end
        # True if the process is running. This is an alias for alive?
        def running?; @alive end

        # Waits for the deployment to be ready. +timeout+ is the number of
        # milliseconds we should wait. If it is nil, will wait indefinitely
	def wait_running(timeout = nil)
            Orocos::Process.wait_running(self, timeout)
	end
    end
end

