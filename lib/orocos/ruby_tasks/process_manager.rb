module Orocos
    module RubyTasks
    # This is a drop-in replacement for ProcessClient. It creates Ruby tasks in
    # the local process, based on the deployment models
    class ProcessManager
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
        attr_reader :loader
        attr_reader :terminated_deployments

        def initialize(loader = Orocos.default_loader)
            @deployments = Hash.new
            @loader = OroGen::Loaders::Aggregate.new
            self.loader.add loader
            @terminated_deployments = Hash.new
        end

        def disconnect
        end

        def register_deployment_model(model)
            loader.loaded_deployment_models[model.name] = model
        end

        def start(name, deployment_name, name_mappings, options)
            model = if deployment_name.respond_to?(:to_str)
                        loader.deployment_model_from_name(deployment_name)
                    else deployment_name
                    end
            if deployments[name]
                raise ArgumentError, "#{name} is already started in #{self}"
            end

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
    end
end

