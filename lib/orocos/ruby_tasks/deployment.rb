module Orocos
    module RubyTasks
    class Process < ProcessBase
        attr_reader :ruby_process_server
        attr_reader :deployed_tasks

        def host_id; 'localhost' end
        def on_localhost?; true end
        def pid; Process.pid end

        def initialize(ruby_process_server, name, model)
            @ruby_process_server = ruby_process_server
            @deployed_tasks = Hash.new
            super(name, model)
        end

        def pid
            ::Process.pid
        end

        def spawn(options = Hash.new)
            model.task_activities.each do |deployed_task|
                deployed_tasks[deployed_task.name] = TaskContext.
                    from_orogen_model(get_mapped_name(deployed_task.name), deployed_task.task_model)
            end
            @alive = true
        end

        def wait_running(blocking = false)
            true
        end

        def task(task_name)
            if t = deployed_tasks[task_name]
                t
            else raise ArgumentError, "#{self} has no task called #{task_name}"
            end
        end

        def kill(wait = true, status = ProcessManager::Status.new(:exit_code => 0))
            deployed_tasks.each_value do |task|
                task.dispose
            end
            dead!(status)
        end

        def dead!(status = ProcessManager::Status.new(:exit_code => 0))
            @alive = false
            if ruby_process_server
                ruby_process_server.dead_deployment(name, status)
            end
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
end

