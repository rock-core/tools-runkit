# frozen_string_literal: true

module Runkit
    module RubyTasks
        # Input port created on a {TaskContext} task instantiated in this Ruby
        # process
        #
        # It is created by {TaskContext#create_input_port}
        class LocalOutputPort < OutputPort
            # Remove this port from the underlying task context
            def remove
                task.remove_port(self)
            end

            # Write a sample on this output port
            #
            # If the data type is a struct, the sample can be provided either as a
            # Typelib instance object or as a hash.
            #
            # In the first case, one can do:
            #
            #   value = port.new_sample # Get a new sample from the port
            #   value.field = 10
            #   value.other_field = "a_string"
            #   input_writer.write(value)
            #
            # In the second case,
            #   input_writer.write(:field => 10, :other_field => "a_string")
            def write(data)
                data = Typelib.from_ruby(data, type)
                do_write(runkit_type_name, data)
            end

            # Whether the port seem to be connected to something
            def connected?
                Runkit.allow_blocking_calls do
                    super
                end
            end
        end
    end
end
