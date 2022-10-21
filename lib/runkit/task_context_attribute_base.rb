# frozen_string_literal: true

module Runkit
    # Common implementation for the {Property} and {Attribute} of a RTT TaskContext
    class TaskContextAttributeBase < AttributeBase
        # Returns the operation that has to be called if this is an
        # dynamic propery. Nil otherwise
        attr_reader :dynamic_operation

        def dynamic?
            !!@dynamic_operation
        end

        def initialize(task, name, runkit_type_name)
            super
            if task.operation?(opname = "__orogen_set#{name.capitalize}")
                @dynamic_operation = task.operation(opname)
            end
        end

        def do_write_dynamic(value)
            raise PropertyChangeRejected, "the change of property #{name} was rejected by the remote task" unless @dynamic_operation.callop(value)
        end
    end
end
