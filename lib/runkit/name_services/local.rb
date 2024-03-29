# frozen_string_literal: true

module Runkit
    module NameServices
        # In-process name service that allows to manually map names to tasks
        class Local < Base
            # A new NameService instance
            #
            # @param [Hash<String,Runkit::TaskContext>] tasks The tasks which are known by the name service.
            # @note The namespace is always "Local"
            def initialize(tasks = [])
                @registered_tasks = Concurrent::Hash.new
                tasks.each { |task| register(task) }
            end

            def names
                @registered_tasks.keys
            end

            def include?(name)
                @registered_tasks.key?(name)
            end

            # (see NameServiceBase#get)
            def ior(name)
                task = @registered_tasks[name]
                return task.ior if task.respond_to?(:ior)

                raise Runkit::NotFound, "task context #{name} cannot be found."
            end

            # (see NameServiceBase#get)
            def get(name, **)
                task = @registered_tasks[name]
                return task if task

                raise Runkit::NotFound, "task context #{name} cannot be found."
            end

            # Registers the given {Runkit::TaskContext} on the name service.
            # If a name is provided, it will be used as an alias. If no name is
            # provided, the name of the task is used. This is true even if the
            # task name is renamed later.
            #
            # @param [Runkit::TaskContext] task The task.
            # @param [String] name Optional name which is used to register the task.
            def register(task, name: task.name)
                @registered_tasks[name] = task
            end

            # Deregisters the given name or task from the name service.
            #
            # @param [String,TaskContext] name The name or task
            def deregister(name)
                @registered_tasks.delete(name)
            end

            # (see Base#cleanup)
            def cleanup
                @registered_tasks.clear
            end
        end
    end
end
