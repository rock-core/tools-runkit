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

            def available_projects; Orocos::ROS.available_projects end
            def available_deployments; Orocos::ROS.available_launchers end
            def available_typekits; Orocos::ROS.available_typekits end

            alias :available_launchers :available_deployments

            class Status
                def initialize(options = Hash.new)
                    options = Kernel.validate_options options,
                        :exit_code => nil,
                        :signal => nil
                    @exit_code = options[:exit_code]
                    @signal = options[:signal]
                end

                def stopped?; false end
                def exited?; !@exit_code.nil? end
                def exitstatus; @exit_code end
                def signaled?; !@signal.nil? end
                def termsig; @signal end
                def stopsig; end
                def success?; exitstatus == 0 end
            end

            # Mapping from a launcher name to the corresponding Launcher
            # instance, for launcher processes that have been started by this client.
            attr_reader :launcher_processes
            alias :processes :launcher_processes

            attr_reader :terminated_launcher_processes

            def initialize
                @launcher_processes = Hash.new
                @terminated_launcher_processes = Hash.new

                # Make sure ROS has been loaded, otherwise no
                # ros specific projects will be found
                Orocos::ROS.load

                name_service = Orocos.name_service.find(Orocos::ROS::NameService)
                if !name_service || name_service.empty?
                    ProcessManager.info "Auto-adding ROS nameservice"
                    Orocos.name_service << Orocos::ROS::NameService.new
                end

            end 

            # Loading an orogen project which defines
            # a ros project
            def load_orogen_project(name)
                # At this stage the ROS projects should be known
                # to the Orocos.master_project and
                # will be loaded from cache
                Orocos.master_project.load_orogen_project(name)
            end

            # Loading a ros launcher definition, which corresponds to 
            # a deployment in orogen
            #
            # @return [Orocos::ROS::Spec::Launcher]
            def load_orogen_deployment(name)
                launcher = available_launchers[name]
                if !launcher
                    raise ArgumentError, "there is no launcher called #{name} on #{self}"
                end

                nodelib = launcher.project
                launcher = nodelib.ros_launchers.find { |l| l.name == name }

                if !launcher
                    raise InternalError, "cannot find the launcher called #{name} in #{nodelib}.
                    Candidates were #{nodelib.deployers.map(&:name).join(", ")}"
                end
                return launcher
            end

            def preload_typekit(name)
                Orocos.load_typekit name
            end

            def disconnect
            end

            def register_deployment_model(model, name = model.name)
                orogen_models[name] = model
            end

            def start(process_name, launcher_name, name_mappings = Hash.new, options = Hash.new)
                launcher_model = load_orogen_deployment(launcher_name)
                launcher_processes.each do |process_name, l| 
                    if l.name == launcher_name
                        raise ArgumentError, "launcher #{launcher_name} is already started with processname #{process_name} in #{self}"
                    end
                end

                #prefix_mapping, options = 
                #    Orocos::ProcessBase.resolve_prefix_option(options, launcher_model)
                #name_mappings = prefix_mappings.merge(name_mappings)

                ros_launcher = LauncherProcess.new(self, process_name, launcher_model)
                #ros_launcher.name_mappings = name_mappings
                ros_launcher.spawn
                launcher_processess[process_name] = ros_launcher
                ros_launcher.pid
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
                result, @terminated_launcher_processes =
                   terminated_launcher_processes, Hash.new
                result
            end

            # Requests to stop the given launcher process
            #
            # The call does not block until the process has quit. You will have to
            # call #wait_termination to wait for the process end.
            def stop(process_name)
                if launcher_process = launcher_processes[process_name]
                    launcher_process.kill
                end
            end

            def dead_deployment(process_name, status = Status.new(:exit_code => 0))
                if launcher_process = launcher_processes.delete(process_name)
                    terminated_launcher_processes[process_name] = status
                end
            end
        end

        # Corresponding to RemoteProcess / RubyDeployment
        class LauncherProcess < ProcessBase
            extend Logger::Root("Orocos::ROS::Launcher", Logger::INFO)

            attr_reader :ros_process_server
            alias :nodes :tasks

            attr_reader :launcher

            def host_id; 'localhost' end
            def on_localhost?; true end
            def pid; @launcher.pid end

            def initialize(ros_process_server, name, model)
                @ros_process_server = ros_process_server
                @nodes = Hash.new
                @launcher = model
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
                    if Orocos.name_service.task_reachable?(name)
                        raise ArgumentError, "there is already a task called #{name}, are you starting the same component twice ?"
                    end
                end

                LauncherProcess.info "Launcher '#{@launcher.name}' spawning"
                @pid = Orocos::ROS.roslaunch(@launcher.project.name, @launcher.name, options)
                wait_running(wait)
                LauncherProcess.info "Launcher '#{@launcher.name}' started. Nodes #{@launcher.nodes.map(&:name).join(", ")}  available."

                # Make tasks known
                model.task_activities.each do |deployed_task|
                    # will register on #@tasks
                    task(deployed_task.name)
                end

                @alive = true
                @pid
            end

            # True if the process is running. This is an alias for running?
            def alive?; @alive end
            # True if the process is running. This is an alias for alive?
            def running?; @alive end

            # Wait for all nodes of the launcher to become available
            # @throws [Orocos::NotFound] if the nodes are not available after a given timeout
            def wait_running(timeout = nil)
                now = Time.now
                while true
                    all_nodes_available = true

                    begin
                        launcher.nodes.each do |n|
                            # Wait till node is visible in ROS
                            if !Orocos::ROS.rosnode_running?(n.name)
                                all_nodes_available = false
                                break
                            end
                            # Check if the node can be seen in the Orocos nameservice as
                            # well
                            task = Orocos.name_service.get(n.name)
                        end
                    rescue Orocos::NotFound => e
                        all_nodes_available = false
                    end

                    if all_nodes_available
                        break
                    end

                    if timeout && (Time.now - now) > timeout
                        if !all_nodes_available
                            raise Orocos::NotFound, "#{self} is still not reachable after #{timeout} seconds"
                        end
                    end
                end
            end

            # Kill the launcher
            def kill
                LauncherProcess.info "Killing launcher '#{@launcher.name}', pid #{@pid}. Nodes #{@launcher.nodes.map(&:name).join(", ")} will be teared down."
                ::Process.kill('INT', @pid)
            end

            # Called to announce that this process has quit
            def dead!
                @alive = false
            end
        end
    end # module ROS
end #module Orocos
