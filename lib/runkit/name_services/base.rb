# frozen_string_literal: true

module Runkit
    module NameServices
        # Base class for all Runkit name services. An runkit name service is used
        # to find local and remote Runkit Tasks based on their name and namespace.
        class Base
            attr_accessor :name

            # Checks if a {TaskContext} with the given name is reachable.
            #
            # @param [String] name the name if the TaskContext
            # @return [Boolean]
            def task_reachable?(name)
                ior(name)
                true
            rescue NotFound
                false
            end

            # Gets an handle to a local/remote Runkit Task having the given name.
            #
            # @param [String] name the name of the {TaskContext}
            # @param [OroGen::Spec::TaskContext] model the task context model
            #
            # @return [TaskContext]
            # @raise [NotFound] if no {TaskContext} can be found
            def get(name, **options)
                TaskContext.new(ior(name), name: name, **options)
            end

            # Gets the IOR for the given Runkit Task having the given name.
            #
            # @param [String] name the name of the TaskContext
            # @return [String]
            # @raise [NotFound] if the TaskContext cannot be found
            def ior(name)
                raise NotImplementedError
            end

            # Returns all Runkit Task names known by the name service
            # inclusive the namespace of the NameService instance.
            #
            # @return [Array<String>]
            def names
                raise NotImplementedError
            end

            # Checks if the name service is reachable if not it
            # raises a ComError.
            #
            # @return [nil]
            # @raise [ComError]
            def validate; end

            # Checks if the name service is reachable.
            #
            # @return [Boolean]
            def reachable?
                validate
                true
            rescue
                false
            end

            # Calls the given code block for all reachable {TaskContext} known by
            # the name service.
            #
            # @yieldparam [TaskContext]
            def each_task
                return enum_for(__method__) unless block_given?

                names.each do |name|
                    task = get(name)

                    begin
                        task.ping
                        yield(task)
                    rescue NotFound
                    end
                end
            end
        end
    end
end
