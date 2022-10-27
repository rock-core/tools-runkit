# frozen_string_literal: true

module Runkit
    module RubyTasks
        # Ruby task context that stubs operations
        #
        # Ruby task contexts cannot define operations. Operations are however needed
        # when using ruby tasks for testing. This class is used in place of
        # {RubyTasks::TaskContext} to be able to stub the operations and test
        # the code that interacts with the task
        #
        # Operations are defined either as writing properties (for dynamic
        # properties) or as empty methods with the same name than the operation.
        # Overload the method to define specific behaviors.
        class StubTaskContext < TaskContext
            # (see TaskContext#setup_from_orogen_model}
            #
            # Overloaded to define the operation stubs
            def setup_from_orogen_model(orogen_model)
                setter_operations = {}
                orogen_model.each_property.each do |prop|
                    if op = prop.setter_operation
                        setter_operations[op.name] = prop
                    end
                end

                stubbed_operations = Module.new
                orogen_model.each_operation do |op|
                    next if operation?(op.name, with_stubs: false)

                    if (property = setter_operations[op.name])
                        stubbed_operations.class_eval do
                            define_method(op.name) do |value|
                                self.property(property.name).write(value, direct: true)
                                true
                            end
                        end
                    else
                        stubbed_operations.class_eval do
                            define_method(op.name) do |*args|
                            end
                        end
                    end
                end
                extend stubbed_operations
                super
            end

            def operation?(name, with_stubs: true)
                super(name) || (with_stubs && model.find_operation(name))
            end

            # Fake SendHandle used for operation stubs
            class SendHandle
                # Value returned by the stub method
                attr_reader :result
                # Error raised by the stub method
                attr_reader :error

                def initialize(result, error)
                    @result = Array(result)
                    @error = error
                end

                def collect
                    if error
                        Runkit::SEND_FAILURE
                    elsif result.empty?
                        Runkit::SEND_SUCCESS
                    else
                        [Runkit::SEND_SUCCESS, *result]
                    end
                end

                def collect_if_done
                    collect
                end
            end

            # Fake Operation class to access operation stubs
            class Operation
                attr_reader :name
                attr_reader :task_context

                def initialize(name, task_context)
                    @name = name
                    @task_context = task_context
                end

                def callop(*args)
                    task_context.send(name, *args)
                end

                def sendop(*args)
                    begin result = callop(*args)
                    rescue StandardError => e
                        return
                    end
                    SendHandle.new(result, e)
                end
            end

            # (see TaskContext#operation)
            #
            # @return [Operation]
            def operation(name)
                super
            rescue NotFound
                raise unless model.find_operation(name)

                Operation.new(name, self)
            end
        end
    end
end
