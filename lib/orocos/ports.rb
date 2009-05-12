require 'utilrb/kernel/options'

module Orocos
    class Port
	class << self
	    # The only way to create a Port object (and its derivatives) is
	    # TaskContext#port
	    private :new
	end

        # The task this port is part of
        attr_reader :task
        # The port name
        attr_reader :name
        # The port's type name as used by the RTT
        attr_reader :type_name
        # The port's type as a Typelib::Type object
        attr_reader :type

        def initialize
            if !(@type = Orocos.registry.get(@type_name))
                raise "cannot find type #{@type_name} in the registry"
            end
        end

        def ==(other)
            other.class == self.class &&
                other.task == self.task &&
                other.name == self.name
        end

        def pretty_print(pp) # :nodoc:
            pp.text " #{name} (#{type.name})"
        end

        # Removes this port from all connections it is part of
        def disconnect_all
            refine_exceptions do
                do_disconnect_all
            end
        end

        def validate_policy(policy)
            policy = validate_options policy,
                :type => :data,
                :init => false,
                :pull => false,
                :size => nil,
                :lock => :lock_free

            if policy[:type] == :buffer && !policy[:size]
                raise ArgumentError, "you must provide a 'size' argument for buffer connections"
            elsif policy[:type] == :data && policy[:size]
                raise ArgumentError, "there are no 'size' argument to data connections"
            end
            policy[:size] ||= 0
            policy
        end

    private
        def refine_exceptions(other = nil)
            CORBA.refine_exceptions(self, other) do
                yield
            end

        rescue NotFound
            if !other || task.has_task?(name)
                raise CORBA::NotFound, "port '#{name}' disappeared from task '#{task.name}'"
            else
                raise CORBA::NotFound, "port '#{other.name}' disappeared from task '#{other.task.name}'"
            end
        end
    end

    class InputPort
        def writer(policy = Hash.new)
            do_writer(@type_name, validate_policy(policy))
        end

        def pretty_print(pp)
            pp.text "in "
            super
        end

        def connect_to(output_port, options = Hash.new)
            unless output_port.kind_of?(OutputPort)
                raise ArgumentError, "an input port can only connect to an output port"
            end
            output_port.connect_to self, options
            self
        end
    end

    class OutputPort
        def disconnect_from(input)
            refine_exceptions(input) do
                do_disconnect_from(input)
            end
            self
        end

        def pretty_print(pp)
            pp.text "out "
            super
        end

        def reader(policy = Hash.new)
            do_reader(@type_name, validate_policy(policy))
        end

        def connect_to(input_port, options = Hash.new)
            if !input_port.kind_of?(InputPort)
                raise ArgumentError, "an output port can only connect to an input port"
            elsif input_port.type_name != type_name
                raise ArgumentError, "trying to connect am output port of type #{type_name} to an input port of type #{input_port.type_name}"
            end

            do_connect_to(input_port, validate_policy(options))
            self
        end
    end

    class OutputReader
	class << self
	    # The only way to create an OutputReader object is OutputPort#reader
	    private :new
	end

        # The OutputPort object this reader is linked to
        attr_reader :port

        def read
	    if process = port.task.process
		if !process.alive?
		    disconnect
		    raise CORBA::ComError, "remote end is dead"
		end
	    end

            value = port.type.new
            if do_read(port.type_name, value)
                value.to_ruby
            end
        end
    end

    class InputWriter
	class << self
	    # The only way to create an InputWriter object is InputPort#writer
	    private :new
	end

        # The InputPort object this writer is linked to
        attr_reader :port

        def write(data)
	    if process = port.task.process
		if !process.alive?
		    disconnect
		    raise CORBA::ComError, "remote end is dead"
		end
	    end

            data = Typelib.from_ruby(data, port.type)
            do_write(port.type_name, data)
        end
    end
end

