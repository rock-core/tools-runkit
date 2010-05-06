require 'socket'
require 'fcntl'
module Orocos
    # A remote process management server. The ProcessServer allows to start/stop
    # and monitor the status of processes on a client/server way.
    #
    # Use ProcessClient to access a server
    class ProcessServer
        DEFAULT_OPTIONS = { :wait => false, :output => '%m-%p.log' }
        DEFAULT_PORT = 20202

        # Start a standalone process server using the given options and port.
        # The options are passed to Orocos.run when a new deployment is started
        def self.run(options = DEFAULT_OPTIONS, port = DEFAULT_PORT)
            Orocos.disable_sigchld_handler = true
            Orocos.initialize
            new({ :wait => false }.merge(options), port).exec
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

        # Helper method that deals with one client request
        def handle_command(socket) # :nodoc:
            cmd_code = socket.read(1)
            raise EOFError if !cmd_code

            if cmd_code == "I"
                Orocos.debug "#{socket} requested system information"
                available_projects = Hash.new
                Orocos.available_projects.each do |name, orogen_path|
                    available_projects[name] = File.read(orogen_path)
                end
                available_deployments = Hash.new
                Orocos.available_deployments.each do |name, pkg|
                    available_deployments[name] = pkg.project_name
                end
                Marshal.dump([available_projects, available_deployments], socket)
            elsif cmd_code == "S"
                name = Marshal.load(socket)
                Orocos.debug "#{socket} requested startup of #{name}"
                begin
                    p = Orocos.run(name, options).first
                    Orocos.debug "#{name} is started (#{p.pid})"
                    processes[name] = p
                    socket.write("Y")
                rescue Exception => e
                    Orocos.debug "failed to start #{name}: #{e.message}"
                    Orocos.debug "  " + e.backtrace.join("\n  ")
                    socket.write("N")
                end
            elsif cmd_code == "E"
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

    # Easy access to a ProcessServer instance.
    #
    # Process servers allow to start/stop and monitor processes on remote
    # machines. Instances of this class provides access to remote process
    # servers.
    class ProcessClient
        # Emitted when an operation fails
        class Failed < RuntimeError; end

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
        # Mapping from a deployment name to the corresponding RemoteProcess
        # instance, for processes that have been started by this client.
        attr_reader :processes

        # Returns the StaticDeployment instance that represents the remote
        # deployment +deployment_name+
        def deployment_model(deployment_name)
            tasklib_name = available_deployments[deployment_name]
            tasklib = Orocos::Generation.load_task_library(tasklib_name)
            tasklib.deployers.find { |d| d.name == deployment_name }
        end

        # Connects to the process server at +host+:+port+
        def initialize(host = 'localhost', port = ProcessServer::DEFAULT_PORT)
            @socket = TCPSocket.new(host, port)
            socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
            socket.fcntl(Fcntl::FD_CLOEXEC, 1)
            socket.write("I")

            info = Marshal.load(socket)
            @available_projects    = info[0]
            @available_deployments = info[1]
            @processes = Hash.new
            @death_queue = Array.new
        end

        # Loads the oroGen project definition called 'name' using the data the
        # process server sent us.
        def load(name)
            Orocos::Generation.load_task_library(name, available_projects[name])
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
        def start(deployment_name)
            project_name = available_deployments[deployment_name]
            if !project_name
                raise ArgumentError, "unknown deployment #{deployment_name}"
            end
            self.load(project_name)

            socket.write("S")
            Marshal.dump(deployment_name, socket)

            if !wait_for_ack
                raise Failed, "failed to start #{deployment_name}"
            end

            processes[deployment_name] = RemoteProcess.new(deployment_name, self)
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
                        raise "unexpected message #{data.inspect} from process server"
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
            socket.write("E")
            Marshal.dump(deployment_name, socket)

            if !wait_for_ack
                raise Failed, "failed to quit #{deployment_name} (#{reply})"
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

        def initialize(name, process_client)
            @name = name
            @process_client = process_client
            @alive = true
            @model = process_client.deployment_model(name)
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

        # Returns the names of the tasks that are running on this deployment
        def task_names
            orogen = process_client.deployment_model(name)
            orogen.task_activities.map { |act| act.name }
        end
    end
end

