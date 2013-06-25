module Orocos
    # This is a drop-in replacement for ProcessClient. It creates Ruby tasks in
    # the local process, based on the deployment models
    class RubyProcessServer
        def available_projects; Orocos.available_projects end
        def available_deployments; Orocos.available_deployments end
        def available_typekits; Orocos.available_typekits end

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

        attr_reader :deployments
        attr_reader :orogen_models
        attr_reader :terminated_deployments

        def initialize
            @deployments = Hash.new
            @orogen_models = Hash.new
            @terminated_deployments = Hash.new
        end

        def load_orogen_project(name)
            Orocos.master_project.load_orogen_project(name)
        end

        def load_orogen_deployment(name)
            if deployment = orogen_models[name]
                return deployment
            else
                project_name = available_deployments[name]
                if !project_name
                    raise ArgumentError, "there is no deployment called #{name} on #{host}:#{port}"
                end

                tasklib = load_orogen_project(project_name)
                deployment = tasklib.deployers.find { |d| d.name == name }
                if !deployment
                    raise InternalError, "cannot find the deployment called #{name} in #{tasklib}. Candidates were #{tasklib.deployers.map(&:name).join(", ")}"
                end
                return deployment
            end
        end

        def preload_typekit(name)
            Orocos.load_typekit name
        end

        def disconnect
        end

        def register_deployment_model(model, name = model.name)
            orogen_models[name] = model
        end

        def start(name, deployment_name, name_mappings, options)
            model = load_orogen_deployment(deployment_name)

            prefix_mappings, options =
                Orocos::ProcessBase.resolve_prefix_option(options, model)
            name_mappings = prefix_mappings.merge(name_mappings)

            ruby_deployment = RubyDeployment.new(self, name, model)
            ruby_deployment.name_mappings = name_mappings
            ruby_deployment.spawn
            deployments[name] = ruby_deployment
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
        # Returns a hash that maps deployment names to the Status
        # object that represents their exit status.
        def wait_termination(timeout = nil)
            result, @terminated_deployments =
               terminated_deployments, Hash.new
            result
        end

        # Requests to stop the given deployment
        #
        # The call does not block until the process has quit. You will have to
        # call #wait_termination to wait for the process end.
        def stop(deployment_name)
            if deployment = deployments[deployment_name]
                deployment.kill
            end
        end

        def dead_deployment(deployment_name, status = Status.new(:exit_code => 0))
            if deployment = deployments.delete(deployment_name)
                terminated_deployments[deployment] = status
            end
        end
    end

    class RubyDeployment < ProcessBase
        attr_reader :ruby_process_server
        attr_reader :tasks

        def host_id; 'localhost' end
        def on_localhost?; true end
        def pid; Process.pid end

        def initialize(ruby_process_server, name, model)
            @ruby_process_server = ruby_process_server
            @tasks = Hash.new
            super(name, model)
        end

        def spawn(options = Hash.new)
            model.task_activities.each do |deployed_task|
                tasks[deployed_task.name] = RubyTaskContext.
                    from_orogen_model(get_mapped_name(deployed_task.name), deployed_task.task_model)
            end
            @alive = true
        end

        def wait_running(blocking = false)
            true
        end

        def kill(wait = true, status = RubyProcessServer::Status.new(:exit_code => 0))
            tasks.each_value do |task|
                task.dispose
            end
            dead!(status)
        end

        def dead!(status = RubyProcessServer::Status.new(:exit_code => 0))
            @alive = false
            ruby_process_server.dead_deployment(name, status)
        end

        def join
            raise NotImplementedError, "RemoteProcess#join is not implemented"
        end

        # True if the process is running. This is an alias for running?
        def alive?; @alive end
        # True if the process is running. This is an alias for alive?
        def running?; @alive end
    end
end

