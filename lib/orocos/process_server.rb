require 'socket'
require 'fcntl'
module Orocos
    class ProcessServer
        DEFAULT_OPTIONS = { :wait => false, :output => '%m-%p.log' }
        DEFAULT_PORT = 20202

        attr_reader :options
        attr_reader :port
        attr_reader :processes

        def initialize(options = DEFAULT_OPTIONS, port = DEFAULT_PORT)
            @options = options
            @port = port
            @processes = Hash.new
        end

        def exec
            server = TCPServer.new(nil, port)
            com_r, com_w = IO.pipe
            all_ios = [server, com_r]

            trap 'SIGCHLD' do
                begin
                    while dead = ::Process.wait(-1, ::Process::WNOHANG)
                        Marshal.dump(dead, com_w)
                    end
                rescue Errno::ECHILD
                end
            end

            STDERR.puts "READY"
            while true
                readable_sockets, _ = select(all_ios, nil, nil)
                if readable_sockets.include?(server)
                    readable_sockets.delete(server)
                    socket = server.accept
                    socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
                    socket.fcntl(Fcntl::FD_CLOEXEC, 1)
                    STDERR.puts "new connection: #{socket}"
                    all_ios << socket
                end

                if readable_sockets.include?(com_r)
                    pid = Marshal.load(com_r)
                    Marshal.dump(["D", pid], socket)
                end

                readable_sockets.each do |socket|
                    if !handle_command(socket)
                        STDERR.puts "#{socket} closed"
                        socket.close
                        all_ios.delete(socket)
                    end
                end
            end
        ensure
            quit_and_join
        end

        def quit_and_join
            processes.each_value do |p|
                STDERR.puts "killing #{p.name}"
                p.kill
            end
        end

        def handle_command(socket)
            cmd_code = socket.read(1)
            raise EOFError if !cmd_code

            if cmd_code == "I"
                STDERR.puts "#{socket} requested system information"
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
                STDERR.puts "#{socket} requested startup of #{name}"
                begin
                    p = Orocos.run(name, options).first
                    STDERR.puts "#{name} is started"
                    processes[name] = p
                    socket.write("Y")
                rescue Exception => e
                    STDERR.puts "failed to start #{name}: #{e.message}"
                    STDERR.puts "  " + e.backtrace.join("\n  ")
                    socket.write("N")
                end
            elsif cmd_code == "E"
                name = Marshal.load(socket)
                STDERR.puts "#{socket} requested end of #{name}"
                p = processes.delete(name)
                if p
                    p.kill(false)
                end
                socket.write("Y")
            end

            true
        rescue EOFError
            false
        end
    end

    class ProcessClient
        attr_reader :socket

        attr_reader :available_projects
        attr_reader :available_deployments

        def initialize(host, port)
            @socket = TCPSocket.new(host, port)
            socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
            socket.fcntl(Fcntl::FD_CLOEXEC, 1)
            socket.write("I")

            info = Marshal.load(socket)
            @available_projects    = info[0]
            @available_deployments = info[1]
        end

        # Loads the oroGen project definition called 'name' using the data the
        # process server sent us.
        def load(name)
            Orocos::Generation.load_task_library(name, available_projects[name])
        end

        def start(deployment_name)
            project_name = available_deployments[deployment_name]
            if !project_name
                raise ArgumentError, "unknown deployment #{deployment_name}"
            end
            self.load(project_name)

            socket.write("S")
            Marshal.dump(deployment_name, socket)
            reply = socket.read(1)
            if reply != "Y"
                raise ArgumentError, "failed to start #{deployment_name}"
            end
        end
    end
end

