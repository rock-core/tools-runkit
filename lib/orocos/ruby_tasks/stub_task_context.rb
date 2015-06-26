module Orocos
    module RubyTasks
        class StubTaskContext < TaskContext
            def setup_from_orogen_model(orogen_model)
                setter_operations = Hash.new
                orogen_model.each_property.each do |prop|
                    if op = prop.setter_operation
                        setter_operations[op.name] = prop
                    end
                end

                orogen_model.each_operation do |op|
                    next if has_operation?(op.name, with_stubs: false)

                    if property = setter_operations[op.name]
                        singleton_class.class_eval do
                            define_method(op.name) do |value|
                                self.property(property.name).write(value, Time.now, direct: true)
                                true
                            end
                        end
                    else
                        singleton_class.class_eval do
                            define_method(op.name) do |*args|
                            end
                        end
                    end
                end
                super
            end

            def has_operation?(name, with_stubs: true)
                super(name) || (with_stubs && !!model.find_operation(name))
            end

            class SendHandle
                # Value returned by the stub method
                attr_reader :result
                # Error raised by the stub method
                attr_reader :error

                def initialize(result, error)
                    @result, @error = Array(result), error
                end

                def collect
                    if error
                        return Orocos::SEND_FAILURE
                    elsif result.empty?
                        return Orocos::SEND_SUCCESS
                    else
                        return [Orocos::SEND_SUCCESS, *result]
                    end
                end

                def collect_if_done; collect end
            end

            class Operation
                attr_reader :name
                attr_reader :task_context

                def initialize(name, task_context)
                    @name, @task_context = name, task_context
                end

                def callop(*args)
                    task_context.send(name, *args)
                end

                def sendop(*args)
                    begin result = callop(*args)
                    rescue Exception => e
                    end
                    SendHandle.new(result, e)
                end
            end

            def operation(name)
                super
            rescue NotFound
                if model.find_operation(name)
                    Operation.new(name, self)
                else
                    raise
                end
            end
        end
    end
end
