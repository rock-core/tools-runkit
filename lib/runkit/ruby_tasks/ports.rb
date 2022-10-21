# frozen_string_literal: true

module Runkit
    module RubyTasks
        # Input port created on a {TaskContext} task instantiated in this Ruby
        # process
        #
        # It is created by {TaskContext#create_input_port}
        class LocalInputPort < InputPort
            # Remove this port from the underlying task context
            def remove
                task.remove_port(self)
            end

            # Reads a sample on this input port
            #
            # For simple types, the returned value is the Ruby representation of the
            # C value.  For instance, C++ strings are represented as String objects,
            # integers as Integer, ...
            #
            # For structures and vectors, the returned value is a representation of
            # that type that Ruby can understand. Field access is transparent:
            #
            #   struct = reader.read
            #   struct.a_field # returns either a simple value or another structure
            #   struct.an_array.each do |element|
            #   end
            def read(sample = nil)
                if value = raw_read(sample)
                    Typelib.to_ruby(value)
                end
            end

            # Reads a sample on this input port
            #
            # Unlike #read, it will always return a typelib type even for simple types.
            #
            # Raises CORBA::ComError if the communication is broken.
            def raw_read(sample = nil)
                _result, value = raw_read_with_result(sample, true)
                value
            end

            # @deprecated use {raw_read} instead
            def read_raw(sample)
                raw_read(sample)
            end

            # @deprecated use {raw_read_new} instead
            def read_new_raw(sample)
                raw_read_new(sample)
            end

            # Whether the port seem to be connected to something
            def connected?
                Runkit.allow_blocking_calls do
                    super
                end
            end

            # Reads a new sample on the associated output port.
            #
            # Unlike #read, it will return a non-nil value only if it it different
            # from the last time #read or #read_new has been called
            #
            # For simple types, the returned value is the Ruby representation of the
            # C value.  For instance, C++ strings are represented as String objects,
            # integers as Integer, ...
            #
            # For structures and vectors, the returned value is a representation of
            # that type that Ruby can understand. Field access is transparent:
            #
            #   struct = reader.read
            #   struct.a_field # returns either a simple value or another structure
            #   struct.an_array.each do |element|
            #   end
            #
            # Raises CORBA::ComError if the communication is broken.
            def read_new(sample = nil)
                if value = raw_read_new(sample)
                    Typelib.to_ruby(value)
                end
            end

            # Reads a new sample on the associated output port.
            #
            # Unlike #raw_read, it will return a non-nil value only if it it different
            # from the last time #read or #read_new has been called
            #
            # Unlike #read_new, it will always return a typelib type even for simple types.
            #
            # Raises CORBA::ComError if the communication is broken.
            def raw_read_new(sample = nil)
                _result, value = raw_read_with_result(sample, false)
                value
            end

            # Attempt to read a sample and return it, along with the read state
            #
            # The returned sample is converted to its Ruby equivalent if a
            # conversion has been registered
            #
            # @overload read_with_result(sample = nil, false)
            #   @return [(Runkit::NEW_DATA, Object)] the read sample if there was a
            #     never-read sample
            #   @return [Runkit::OLD_DATA] if there is a sample on the port, but it
            #     was already read
            #   @return [false] if there were no samples on the port
            #
            # @overload read_with_result(sample = nil, true)
            #   @return [(Runkit::NEW_DATA, Object)] the read sample if there was a
            #     never-read sample
            #   @return [(Runkit::OLD_DATA, Object)] the read sample if there was a
            #     sample that was already read
            #   @return [false] if there were no samples on the port
            def read_with_result(sample = nil, copy_old_data = true)
                result, value = raw_read_with_result(sample, copy_old_data)
                if value
                    [result, Typelib.to_ruby(value)]
                else
                    result
                end
            end

            # Attempt to read a sample and return it, along with the read state
            #
            # The sample is returned as a Typelib::Type object
            #
            # @overload read_with_result(sample = nil, false)
            #   @return [(Runkit::NEW_DATA, Typelib::Type)] the read sample if there was a
            #     never-read sample
            #   @return [Runkit::OLD_DATA] if there is a sample on the port, but it
            #     was already read
            #   @return [false] if there were no samples on the port
            #
            # @overload read_with_result(sample = nil, true)
            #   @return [(Runkit::NEW_DATA, Typelib::Type)] the read sample if there was a
            #     never-read sample
            #   @return [(Runkit::OLD_DATA, Typelib::Type)] the read sample if there was a
            #     sample that was already read
            #   @return [false] if there were no samples on the port
            def raw_read_with_result(sample = nil, copy_old_data = true)
                if sample
                    unless sample.kind_of?(type)
                        raise ArgumentError, "wrong sample type #{sample.class}, expected #{type}" if sample.class != type
                    end
                    value = sample
                else
                    value = type.new
                end

                result = value.allocating_operation do
                    do_read(runkit_type_name, value, copy_old_data, blocking_read?)
                end
                if result == NEW_DATA || (result == OLD_DATA && copy_old_data)
                    sample&.invalidate_changes_from_converted_types
                    [result, value]
                else
                    result
                end
            end

            # Clears the channel, i.e. "forget" that this port ever got written to
            def clear
                do_clear
            end
        end

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
