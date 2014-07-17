module Orocos
    module ROS
        # This class corresponds to the ProcessClient and is a drop-in replacement for
        # ProcessClient. 
        # It allows to start ROS launch files using the process server
        #
        # In this context launch files correspond to oroGen deployments
        # The naming 'deployments' is kept when required by the top level interface
        # otherwise 'launcher' is being used to clarify that this should be a 
        # ROS Launcher object
        class ProcessManager
            extend Logger::Root("Orocos::ROS", Logger::INFO)

            # The loader object that should be used to get ROS models
            #
            # @return [OroGen::ROS::Loader]
            attr_reader :loader

            # Mapping from a launcher name to the corresponding Launcher
            # instance, for launcher processes that have been started by this client.
            attr_reader :launcher_processes
            alias :processes :launcher_processes

            # @return [Set<LauncherProcess>] the set of launcher processes for which
            #   {#kill} has been called but the exit status has not yet been read by
            #   {#wait_termination}
            attr_reader :dying_launcher_processes

            # @return [Orocos::ROS::NameService] the ROS nameservice used by this process manager
            def name_service
                @name_service ||= Orocos::ROS.name_service
            end

            attr_writer :name_service

            # Initialize process server
            def initialize(loader = Orocos::ROS.default_loader)
                @launcher_processes = Hash.new
                @dying_launcher_processes = Array.new
                @loader = loader
            end 

            def disconnect
            end

            # Start a launcher process under the given process_name
            # @return [Orocos::ROS::LauncherProcess] The launcher process which started by the process manager
            def start(process_name, launcher, name_mappings = Hash.new, options = Hash.new)
                launcher_model = if launcher.respond_to?(:to_str)
                                     loader.deployment_model_from_name(launcher)
                                 else launcher
                                 end

                ProcessManager.debug "launcher: '#{launcher_model.name}' with processname '#{process_name}'"
                launcher_processes.each do |process_name, l| 
                    if l.name == launcher_model.name
                        raise ArgumentError, "launcher #{launcher_model.name} is already started with processname #{process_name} in #{self}"
                    end
                end

                ros_launcher = LauncherProcess.new(self, process_name, launcher_model)
                ros_launcher.spawn
                launcher_processes[process_name] = ros_launcher
                ros_launcher
            end

            # Requests that the process server moves the log directory at +log_dir+
            # to +results_dir+
            def save_log_dir(log_dir, results_dir)
            end

            # Creates a new log dir, and save the given time tag in it (used later
            # on by save_log_dir)
            def create_log_dir(log_dir, time_tag)
            end

            # Waits for processes to terminate. +timeout+ is the number of
            # milliseconds we should wait. If set to nil, the call will block until
            # a process terminates
            #
            # Returns a hash that maps launcher names to the Status
            # object that represents their exit status.
            def wait_termination(timeout = nil)
                if timeout != 0
                    raise ArgumentError, "#{self.class} does not support non-zero timeouts in #wait_termination"
                end

                terminated_launchers = Hash.new
                dying_launcher_processes.delete_if do |launcher_process|
                    _, status = ::Process.waitpid2(launcher_process.pid, ::Process::WUNTRACED | ::Process::WNOHANG)
                    if status
                        ROS.info "announing dead launcher_process: #{launcher_process}"
                        terminated_launchers[launcher_process] = status
                        launcher_processes.delete(launcher_process.name)
                        launcher_process.dead!(status)
                        true
                    else
                        false
                    end
                end
                terminated_launchers
            end

            # Kills the given launcher process and registers it in
            # {#dying_launcher_processes} for later reporting by {#wait_termination}
            #
            # @param [LauncherProcess] launcher the launcher process to be killed
            # @return [void]
            def kill(launcher_process)
                ROS.info "ProcessManager is killing launcher process #{launcher_process.name} with pid '#{launcher_process.pid}'"
                ::Process.kill('SIGTERM', launcher_process.pid)
                dying_launcher_processes << launcher_process
                nil
            end
        end

        # Management of a roslaunch process and its underlying launch file
        class LauncherProcess < ProcessBase
            extend Logger::Root("Orocos::ROS::LauncherProcess", Logger::INFO)

            # Parse run options to 
            # @return [String, Hash] Names and options
            def self.parse_run_options(*names)
                options = names.last.kind_of?(Hash) ? names.pop : Hash.new
                [ names, options ]
            end

            attr_reader :ros_process_server
            alias :nodes :tasks

            attr_reader :launcher

            # The process ID of this process on the machine of the process server
            attr_reader :pid

            def host_id; 'localhost' end
            def on_localhost?; true end
            def alive; !!@pid end

            def initialize(ros_process_server, name, model)
                @ros_process_server = ros_process_server
                @nodes = Hash.new
                @launcher = model
                @pid = nil
                super(name, model)
            end

            # Spawn the launch file
            # @return [int] pid of the launch process
            def spawn(options = Hash.new)
                options, unknown_options = Kernel.filter_options options,
                    :wait => false,
                    :redirect => "ros-#{@launcher.name}.txt"

                wait = options[:wait]
                options.delete(:wait)
                options.merge!(unknown_options)

                task_names.each do |name|
                    if ros_process_server.name_service.task_reachable?(name)
                        raise ArgumentError, "there is already a task called '#{name}', are you starting the same component twice ?"
                    end
                end

                LauncherProcess.debug "Launcher '#{@launcher.name}' spawning"
                @pid = Orocos::ROS.roslaunch(@launcher.project.name, @launcher.name, options)
                LauncherProcess.info "Launcher '#{@launcher.name}' started, pid '#{@pid}'. Nodes #{@launcher.nodes.map(&:name).join(", ")}  available."

                @pid
            end

            # Retrieve the task (node) using the internal name service instance
            # @return [Orocos::ROS::Node] A task (node) instance
            # @raise [Orocos::NotFound] If task (node) cannot be found in the name service
            def task(name)
                super(name, ros_process_server.name_service)
            end

            # True if the process is running. This is an alias for running?
            def alive?; !!@pid end
            # True if the process is running. This is an alias for alive?
            def running?; alive? end

            # Wait for all nodes of the launcher to become available
            # @raise [Orocos::NotFound] if the nodes are not available after a given timeout
            # @return [Boolean] True if process is running, false otherwise
            def wait_running(timeout = nil)

                is_running = Orocos::Process.wait_running(self,timeout) do |launcher_process|
                    all_nodes_available = true
                    all_topics_available = true
                    topics = []
                    begin
                        nodes = launcher_process.launcher.nodes
                        if nodes.empty?
                            LauncherProcess.warn "launcher_process: #{launcher_process} does not have any nodes"
                        end

                        nodes.each do |n|
                            # Wait till node is visible in ROS
                            if !ROS.rosnode_running?(n.name)
                                all_nodes_available = false
                                break
                            end

                            # Check if the node can be seen in the nameservice as
                            # well
                            task = ros_process_server.name_service.get(n.name)

                            # Try to check whether the topics in the spec are already available
                            # Note that we have to try to instanciate write and reader and using
                            # to_orocos_port in order to make sure the ROS node is really accessible
                            if spec = ROS.node_spec_by_node_name(n.name)
                                spec.each_input_port do |port|
                                    if task.port(port.topic_name)
                                        topics << port.topic_name
                                        next
                                    end

                                    all_topics_available = false
                                    break
                                end

                                spec.each_output_port do |port|
                                    if task.port(port.topic_name)
                                        topics << port.topic_name
                                        next
                                    end
                                    all_topics_available = false
                                    break
                                end
                            else
                                raise ArgumentError, "No ROS Node specification available for #{n.name}"
                            end
                        end
                    rescue Orocos::NotFound => e
                        all_nodes_available = false
                        all_topics_available = false
                    end

                    if ! (all_nodes_available && all_topics_available)
                        LauncherProcess.debug "reachable nodes: #{nodes.map(&:name).join(", ")}"
                        LauncherProcess.debug "reachable topics: #{topics.join(", ")}"
                    end

                    all_nodes_available && all_topics_available
                end

                is_running
            end

            # Wait for termination of the launcher process
            # @return [Process::Status] Final process status
            def wait_termination(timeout = nil)
                if timeout
                    raise NotImplementedError, "ROS::ProcessManager#wait_termination cannot be called with a timeout"
                end

                _, status = begin ::Process.waitpid2(@pid, ::Process::WUNTRACED | Process::WNOHANG)
                              rescue Errno::ECHILD
                              end
                status
            end

            # Kill the launcher
            def kill(wait = true)
                LauncherProcess.debug "Sending SIGTERM to launcher '#{@launcher.name}', pid #{@pid}. Nodes #{@launcher.nodes.map(&:name).join(", ")} will be teared down."
                ::Process.kill('SIGTERM', @pid)
                ros_process_server.kill(self)
                if wait
                    status = @launcher.wait_termination
                end
            end

            # Called to announce that this process has quit
            def dead!(exit_status)
                LauncherProcess.debug "Announcing launcher '#{@launcher.name}', pid #{@pid} dead!"
                @pid = nil
            end
        end
    end # module ROS
end #module Orocos
