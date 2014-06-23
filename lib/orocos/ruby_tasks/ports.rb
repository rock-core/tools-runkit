module Orocos
    module RubyTasks
    # Input port created on a {TaskContext} task instantiated in this Ruby
    # process
    #
    # It is created by {TaskContext#create_input_port}
    class LocalInputPort < InputPort
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
                return Typelib.to_ruby(value)
            end
        end

        # Reads a sample on this input port
        #
        # Unlike #read, it will always return a typelib type even for simple types.
        #
        # Raises CORBA::ComError if the communication is broken.
        def raw_read(sample = nil)
            if value = read_helper(sample,true)
                value[0]
            end
        end

        # @deprecated use {raw_read} instead
        def read_raw(sample)
            raw_read(sample)
        end

        # @deprecated use {raw_read_new} instead
        def read_new_raw(sample)
            raw_read_new(sample)
        end


        OLD_DATA = 0
        NEW_DATA = 1

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
                return Typelib.to_ruby(value)
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
            if value = read_helper(sample, false)
                value[0] if value[1] == NEW_DATA
            end
        end

        # Clears the channel, i.e. "forget" that this port ever got written to
        def clear
            do_clear
        end

        private

        # Helper method for #read, #raw_read, #read_new and #raw_read_new
        # always returns a Typelib Type or nil even for simple types
        def read_helper(sample, copy_old_data) # :nodoc:
            if sample
                if sample.class != type
                    raise ArgumentError, "wrong sample type #{sample.class}, expected #{type}"
                end
                value = sample
            else
                value = type.new
            end

            result = value.allocating_operation do
                do_read(orocos_type_name, value, copy_old_data)
            end
            if result == NEW_DATA || (result == OLD_DATA && copy_old_data)
                if sample
                    sample.invalidate_changes_from_converted_types
                end
                return [value, result]
            end
        end

    end

    class LocalOutputPort < OutputPort
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
            do_write(orocos_type_name, data)
        end
    end
    end
end

