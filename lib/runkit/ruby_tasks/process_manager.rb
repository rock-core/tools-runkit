# frozen_string_literal: true

require "runkit/ruby_tasks/process"

module Runkit
    module RubyTasks
        # This is a drop-in replacement for ProcessClient. It creates Ruby tasks in
        # the local process, based on the deployment models
        class ProcessManager
            class Status
                def initialize(exit_code: nil, signal: nil)
                    @exit_code = exit_code
                    @signal = signal
                end

                def stopped?
                    false
                end

                def exited?
                    !@exit_code.nil?
                end

                def exitstatus
                    @exit_code
                end

                def signaled?
                    !@signal.nil?
                end

                def termsig
                    @signal
                end

                def stopsig; end

                def success?
                    exitstatus == 0
                end
            end

            attr_reader :deployments
            attr_reader :loader
            attr_reader :terminated_deployments

            # The task context class that should be used on the client side
            #
            # Defaults to {TaskContext}, another option is {StubTaskContext}
            #
            # @return [Class]
            attr_reader :task_context_class

            def initialize(loader = Runkit.default_loader, task_context_class: TaskContext)
                @loader = loader
                @deployments = {}
                @terminated_deployments = {}
                @task_context_class = task_context_class
            end

            def disconnect; end

            def register_deployment_model(model)
                loader.register_deployment_model(model)
            end

            def start(name, deployment_name, name_mappings, options)
                model = if deployment_name.respond_to?(:to_str)
                            loader.deployment_model_from_name(deployment_name)
                        else deployment_name
                        end
                raise ArgumentError, "#{name} is already started in #{self}" if deployments[name]

                prefix_mappings = Runkit::ProcessBase.resolve_prefix(model, options.delete(:prefix))
                name_mappings = prefix_mappings.merge(name_mappings)

                task_context_class = options.fetch(:task_context_class, self.task_context_class)
                ruby_deployment = Process.new(self, name, model,
                                              task_context_class: task_context_class)
                ruby_deployment.name_mappings = name_mappings
                ruby_deployment.spawn
                deployments[name] = ruby_deployment
            end

            # Requests that the process server moves the log directory at +log_dir+
            # to +results_dir+
            def save_log_dir(log_dir, results_dir); end

            # Creates a new log dir, and save the given time tag in it (used later
            # on by save_log_dir)
            def create_log_dir(log_dir, time_tag, metadata = {}); end

            # Waits for processes to terminate. +timeout+ is the number of
            # milliseconds we should wait. If set to nil, the call will block until
            # a process terminates
            #
            # Returns a hash that maps deployment names to the Status
            # object that represents their exit status.
            def wait_termination(timeout = nil)
                result = terminated_deployments
                @terminated_deployments = {}
                result
            end

            def wait_running(*process_names)
                process_ior_mappings = {}
                process_names.each do |name|
                    process_ior_mappings[name] = if deployments[name]&.resolve_all_tasks
                                                     { iors: deployments[name].wait_running }
                                                 else
                                                     { error: "#{name} is not a valid process in the deployment" }
                                                 end
                end
                process_ior_mappings
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

            def dead_deployment(deployment_name, status = Status.new(exit_code: 0))
                if deployment = deployments.delete(deployment_name)
                    terminated_deployments[deployment] = status
                end
            end
        end
    end
end
