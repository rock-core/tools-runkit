# frozen_string_literal: true

module Runkit
    # Common implementation for the {Property} and {Attribute} of a RTT TaskContext
    class TaskContextAttributeBase < AttributeBase
        def dynamic?
            @dynamic_operation
        end

        def initialize(task, name, model)
            super

            @dynamic_operation =
                if task.operation?(opname = "__orogen_set#{name.capitalize}")
                    task.operation(opname)
                end
        end

        def do_write_dynamic(value)
            return if @dynamic_operation.callop(value)

            raise PropertyChangeRejected,
                  "the change of property #{name} was rejected by the remote task"
        end
    end
end
