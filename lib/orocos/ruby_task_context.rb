module Orocos
    # Input port created on a RubyTaskContext task instantiated in this Ruby
    # process
    #
    # It is created by RubyTaskContext#create_input_port
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
            if value = read_helper(sample, true)
                value[0]
            end
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
            if value = read_helper(sample, false)
                value[0] if value[1] == NEW_DATA
            end
        end

        # Clears the channel, i.e. "forget" that this port ever got written to
        def clear
            do_clear
        end

        private

        # Helper method for #read and #read_new
        def read_helper(sample, copy_old_data) # :nodoc:
            if sample
                if sample.class != type
                    raise ArgumentError, "wrong sample type #{sample.class}, expected #{type}"
                end
                value = sample
            else
                value = type.new
            end

            result = do_read(orocos_type_name, value, copy_old_data)
            if result == 1 || (result == 0 && copy_old_data)
                if sample
                    sample.invalidate_changes_from_converted_types
                end
                return [Typelib.to_ruby(value), result]
            end
        end

    end

    # Local input port that is specifically designed to read to another task's output port
    class OutputReader < LocalInputPort
        # The port this object is reading from
        attr_accessor :port

        # Helper method for #read and #read_new
        #
        # This is overloaded in OutputReader to raise CORBA::ComError if the
        # process supporting the remote task is known to be dead
        def read_helper(sample, copy_old_data)
	    if process = port.task.process
		if !process.alive?
		    disconnect_all
		    raise CORBA::ComError, "remote end is dead"
		end
	    end
            super
        end

        # Reads a sample on the associated output port. Returns a value as soon
        # as a sample has ever been written to the port since the data reader
        # has been created
        #
        # @raise [CORBA::ComError] if the remote process is known to be dead.
        # This is only possible if the remote deployment has been started by
        # this Ruby instance
        def read(sample = nil)
            # Only overloaded for documentation reasons
            super
        end

        # Reads a sample on the associated output port, and returns nil if no
        # new data is available
        #
        # @raise [CORBA::ComError] if the remote process is known to be dead.
        # This is only possible if the remote deployment has been started by
        # this Ruby instance
        # @see read
        def read_new(sample = nil)
            # Only overloaded for documentation reasons
            super
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

    # Local output port that is specifically designed to write to another task's input port
    class InputWriter < LocalOutputPort
        # The port this object is reading from
        attr_accessor :port

        # Write data on the associated input port
        #
        # @overload
        #
        # @raise [CORBA::ComError] if the remote process is known to be dead.
        # This is only possible if the remote deployment has been started by
        # this Ruby instance
        def write(data)
	    if process = port.task.process
		if !process.alive?
		    disconnect_all
		    raise CORBA::ComError, "remote end is dead"
		end
	    end
            super
        end
    end

    # A TaskContext that lives inside this Ruby process
    #
    # For now, it has very limited functionality: mainly managing ports
    class RubyTaskContext < TaskContext
        class LocalTaskContext
            attr_reader :remote_task
            attr_reader :name

            def initialize(name)
                @name = name
            end
        end

        def self.new(name, options = Hash.new)
            local_task = LocalTaskContext.new(name)
            remote_task = super(local_task.ior, options)
            local_task.instance_variable_set :@remote_task, remote_task
            remote_task.instance_variable_set :@local_task, local_task
            remote_task
        end


        def initialize(ior, options = Hash.new)
            @local_ports = Hash.new
            options, other_options = Kernel.filter_options options, :name => name
            super(ior, other_options.merge(options))
        end

        # Create a new input port on this task context
        #
        # @param [String] name the port name. It must be unique among all port
        #   types
        # @param [String] orocos_type_name the name of the port's type, as
        #   recognized by Orocos. In most cases, it is the same than the
        #   typelib type name
        # @option options [Boolean] :permanent if true (the default), the port
        #   will be stored permanently on the task. Otherwise, it will be
        #   removed as soon as the port object gets garbage collected by Ruby
        # @option options [Class] :class the class that should be used to
        #   represent the port on the Ruby side. Do not change unless you know
        #   what you are doing
        def create_input_port(name, orocos_type_name, options = Hash.new)
            options, other_options = Kernel.filter_options options, :class => LocalInputPort
            create_port(false, options[:class], name, orocos_type_name, other_options)
        end

        # Create a new output port on this task context
        #
        # @param [String] name the port name. It must be unique among all port
        #   types
        # @param [String] orocos_type_name the name of the port's type, as
        #   recognized by Orocos. In most cases, it is the same than the
        #   typelib type name
        # @option options [Boolean] :permanent if true (the default), the port
        #   will be stored permanently on the task. Otherwise, it will be
        #   removed as soon as the port object gets garbage collected by Ruby
        # @option options [Class] :class the class that should be used to
        #   represent the port on the Ruby side. Do not change unless you know
        #   what you are doing
        def create_output_port(name, orocos_type_name, options = Hash.new)
            options, other_options = Kernel.filter_options options, :class => LocalOutputPort
            create_port(true, options[:class], name, orocos_type_name, other_options)
        end

        # Remove the given port from this task's interface
        def remove_port(port)
            @local_ports.delete(port.name)
            port.disconnect_all # don't wait for the port to be garbage collected by Ruby

            port_name =
                if port.respond_to?(:name) then port.name
                else port.to_str
                end
            do_remove_port(port_name)
        end

        # Deregisters this task context.
        #
        # This is done automatically when the object is garbage collected.
        # However, it is sometimes better to do this explicitely, for instance
        # to avoid the name clash warning.
        def dispose
            @local_task.dispose
        end

        private

        def create_port(is_output, klass, name, orocos_type_name, options)
            options = Kernel.validate_options options, :permanent => true
            local_port = @local_task.do_create_port(is_output, klass, name, orocos_type_name)
            if options[:permanent]
                @local_ports[local_port.name] = local_port
                @ports[local_port.name] = local_port
            end
            local_port
        end
    end
end
