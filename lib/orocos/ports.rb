require 'utilrb/kernel/options'

module Orocos
    # Base class for port classes.
    #
    # See OutputPort and InputPort
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
        # The port full name. It is task_name.port_name
        def full_name; "#{task.name}.#{name}" end
        # The port's type name as used by the RTT
        attr_reader :orocos_type_name
        # The port's type name as used in Ruby
        attr_reader :type_name
        # The port's type as a Typelib::Type object
        attr_reader :type
        # The port's model as either a Orocos::Generation::InputPort or
        # Orocos::Generation::OutputPort
        def model
            @model ||= task.model.find_port(name)
        end

        def initialize
            @type = Orocos.typelib_type_for(@orocos_type_name)
            @type_name = @type.name

            if model
                @max_sizes = model.max_sizes.dup
            else
                @max_sizes = Hash.new
            end
            @max_sizes.merge!(Orocos.max_sizes_for(type))
        end

        # True if +self+ and +other+ represent the same port
        def ==(other)
            other.class == self.class &&
                other.task == self.task &&
                other.name == self.name
        end

        def pretty_print(pp) # :nodoc:
            if type_name != orocos_type_name
                pp.text " #{name} (#{type_name}/#{orocos_type_name})"
            else
                pp.text " #{name} (#{type_name})"
            end
        end

        # Removes this port from all connections it is part of
        def disconnect_all
            refine_exceptions do
                do_disconnect_all
            end
        end

        # Returns a new object of this port's type
        def new_sample
            @type.new
        end

        CONNECTION_POLICY_OPTIONS = {
            :type => :data,
            :init => false,
            :pull => false,
            :data_size => 0,
            :size => 0,
            :lock => :lock_free,
            :transport => 0
        }

        # A connection policy is represented by a hash whose elements are each
        # of the policy parameters. Valid policies are:
        # 
        # * buffer policy. Values are stored in a FIFO of the specified size.
        #   Connecting with a buffer policy is done with:
        # 
        #      output_port.connect_to(input_port, :type => :buffer, :size => 10)
        # 
        # * data policy. The input port will always read the last value pushed by the
        #   output port. It is the default policy, but can be explicitly specified with:
        # 
        #      output_port.connect_to(input_port, :type => :data)
        # 
        # An additional +:pull+ option specifies if samples should be pushed by the
        # output end (i.e. if all samples that are written on the output port are sent to
        # the input port), or if the values are transmitted only when the input port is
        # read. For instance:
        # 
        #   output_port.connect_to(input_port, :type => :data, :pull => true)
        #
        # Finally, the type of locking can be specified. The +lock_free+ locking
        # policy guarantees that a high-priority thread will not be "taken over"
        # by a low-priority one, but requires a lot of copying -- so avoid it in
        # non-hard-realtime contexts with big data samples. The +locked+ locking
        # policy uses mutexes, so is not ideal in hard realtime contexts. Each
        # policy is specified with:
        #
        #   output_port.connect_to(input_port, :lock => :lock_free)
        #   output_port.connect_to(input_port, :lock => :locked)
        #
        # This method raises ArgumentError if the policy is not valid.
        def self.validate_policy(policy)
            policy = validate_options policy, CONNECTION_POLICY_OPTIONS

            if policy[:type] == :buffer && !policy[:size]
                raise ArgumentError, "you must provide a 'size' argument for buffer connections"
            elsif policy[:type] == :data && (policy[:size] && policy[:size] != 0)
                raise ArgumentError, "there are no 'size' argument to data connections"
            end
            policy[:size] ||= 0
            policy
        end

        def validate_policy(policy)
            Port.validate_policy(policy)
        end

    private
        def refine_exceptions(other = nil) # :nodoc:
            CORBA.refine_exceptions(self, other) do
                yield
            end

        rescue NotFound
            if !other || task.has_port?(name)
                raise NotFound, "port '#{name}' disappeared from task '#{task.name}'"
            else
                raise NotFound, "port '#{other.name}' disappeared from task '#{other.task.name}'"
            end
        end

        # Helper method for #connect_to, to handle the MQ transport (in
        # particular, the validation of the parameters)
        #
        # A block must be given, that should return true if the MQ transport
        # should be used for this particular connection and false otherwise
        # (i.e. true if the two ports are located on the same machine, false
        # otherwise)
        def handle_mq_transport(input_name, policy) # :nodoc:
            if policy[:transport] == TRANSPORT_MQ && !Orocos::MQueue.available?
                raise ArgumentError, "cannot select the MQueue transport as it is not built into the RTT"
            end

            if Orocos::MQueue.auto? && policy[:transport] == 0
                if yield
                    switched = true
                    Orocos.info do
                        "#{full_name} => #{input_name}: using MQ transport"
                    end
                    policy[:transport] = TRANSPORT_MQ
                else
                    Orocos.debug do
                        "#{full_name} => #{input_name}: cannot use MQ as the two ports are located on different machines"
                    end
                end
            end

            if Orocos::MQueue.auto_sizes? && policy[:transport] == TRANSPORT_MQ && policy[:data_size] == 0
                size = max_marshalling_size
                if size
                    Orocos.info do
                        "#{full_name} => #{input_name}: MQ data_size == #{size}"
                    end
                    policy[:data_size] = size
                else
                    policy[:transport] = 0
                    if Orocos::MQueue.warn?
                        Orocos.warn "the MQ transport could be selected, but the marshalling size of samples from the output port #{full_name}, of type #{type_name}, is unknown"
                    end
                end
            end

            if Orocos::MQueue.validate_sizes? && policy[:transport] == TRANSPORT_MQ
                size = if policy[:size] == 0 then 10 # 10 is the default size in the RTT's MQ transport for data samples
                       else policy[:size]
                       end

                valid = Orocos::MQueue.valid_sizes?(size, policy[:data_size]) do
                    "#{full_name} => #{input_name} of type #{type_name}: "
                end

                if !valid
                    policy[:transport] = 0
                end
            end

            policy
        end

        ##
        # :method: max_sizes
        #
        # :call-seq:
        #   max_sizes('name.to[].field' => value, 'name.other' => value) => self
        #   max_sizes => current size specification
        #
        # Sets the maximum allowed size for the variable-size containers in
        # +type+. If the type is a compound, the mapping is given as
        # path.to.field => size. If it is a container, the size of the
        # container itself is given as first argument, and the sizes for the
        # contained values as a second map argument.
        #
        # For instance, with the types
        #
        #   struct A
        #   {
        #       std::vector<int> values;
        #   };
        #   struct B
        #   {
        #       std::vector<A> field;
        #   };
        #
        # Then sizes on a port of type B would be given with
        #
        #   port.max_sizes('field' => 10, 'field[].values' => 20)
        #
        # while the sizes on a port of type std::vector<A> would be given
        # with
        #
        #   port.max_sizes(10, 'values' => 20)
        #
        dsl_attribute :max_sizes do |*values|
            # Validate that all values are integers and all names map to
            # known types
            value = Orocos::Spec::OutputPort.validate_max_sizes_spec(type, values)
            max_sizes.merge(value)
        end

        # Returns the maximum marshalled size of a sample from this port, as
        # marshalled by typelib
        #
        # If the type contains variable-size containers, the result is dependent
        # on the values given to #max_sizes. If not enough is known, this method
        # will return nil.
        def max_marshalling_size
            Orocos::Spec::OutputPort.compute_max_marshalling_size(type, max_sizes)
        end

    end

    # This class represents output ports on remote task contexts.
    #
    # They are obtained from TaskContext#port or TaskContext#each_port
    class InputPort
        # Returns a InputWriter object that allows you to write data to the
        # remote input port.
        def writer(policy = Hash.new)
            policy = validate_policy(policy)
            policy = handle_mq_transport("#{full_name}.writer", policy) do
                task.process && task.process.on_localhost?
            end
            do_writer(orocos_type_name, policy)
        rescue Orocos::ConnectionFailed => e
            raise e, "failed to create a port writer on #{full_name} of type #{type_name} with policy #{policy.inspect}"
        end

        # Writes one sample with a default policy.
        #
        # While convenient, this is quite ressource consuming, as each time one
        # will need to create a new connection between the ruby interpreter and
        # the remote component.
        #
        # Use #writer if you need to write on the same port repeatedly.
        def write(sample)
            writer.write(sample)
        end

        def pretty_print(pp) # :nodoc:
            pp.text "in "
            super
        end

        # Connect this input port to an output port. +options+ defines the
        # connection policy for the connection.
        #
        # See OutputPort#connect_to for a in-depth explanation on +options+.
        def connect_to(output_port, options = Hash.new)
            unless output_port.kind_of?(OutputPort)
                raise ArgumentError, "an input port can only connect to an output port"
            end
            output_port.connect_to self, options
            self
        end
    end

    # This class represents output ports on remote task contexts.
    #
    # They are obtained from TaskContext#port or TaskContext#each_port
    class OutputPort
        # Require this port to disconnect from the provided input port
        def disconnect_from(input)
            refine_exceptions(input) do
                do_disconnect_from(input)
            end
        end

        def pretty_print(pp) # :nodoc:
            pp.text "out "
            super
        end

        # Reads one sample with a default policy.
        #
        # While convenient, this is quite ressource consuming, as each time one
        # will need to create a new connection between the ruby interpreter and
        # the remote component.
        #
        # Use #reader if you need to read the same port repeatedly.
        def read
            reader = self.reader
            reader.read
        ensure
            reader.disconnect
        end

        # Reads one sample with a default policy.
        #
        # While convenient, this is quite ressource consuming, as each time one
        # will need to create a new connection between the ruby interpreter and
        # the remote component.
        #
        # This is defined for consistency with OutputReader
        #
        # Use #reader if you need to read the same port repeatedly.
        def read_new
            read
        end

        # Returns an OutputReader object that is connected to that port
        #
        # The policy dictates how data should flow between the port and the
        # reader object. See #validate_policy
        def reader(policy = Hash.new)
            policy = validate_policy(policy)
            policy = handle_mq_transport("#{full_name}.reader", policy) do
                task.process && task.process.on_localhost?
            end
            do_reader(OutputReader, orocos_type_name, policy)
        rescue Orocos::ConnectionFailed => e
            raise e, "failed to create a port reader on #{full_name} of type #{type_name} with policy #{policy.inspect}"
        end

        # Connect this output port to an input port. +options+ defines the
        # connection policy for the connection. The following options are
        # available:
        #
        # Data connections. In that connection, the reader will see only the
        # last sample he received. Such a connection is set up with
        #   
        #   input_port.connect_to output_port, :type => :data
        #
        # Buffered connections. In that case, the reader will be able to read
        # all the samples received since the last read. A buffer in between the
        # output and input port will keep the samples that have not been read
        # already.  Such a connection is set up with:
        #
        #   output_port.connect_to input_port, :type => :buffer, :size => 10
        #
        # Where the +size+ option gives the size of the intermediate buffer.
        # Note that new samples will be lost if they are received when the
        # buffer is full.
        def connect_to(input_port, options = Hash.new)
            if !input_port.kind_of?(InputPort)
                raise ArgumentError, "an output port can only connect to an input port"
            elsif input_port.type_name != type_name
                raise ArgumentError, "trying to connect an output port of type #{type_name} to an input port of type #{input_port.type_name}"
            end

            policy = validate_policy(options)
            policy = handle_mq_transport(input_port.full_name, policy) do
                task.process != input_port.task.process && task.process.host_id == input_port.task.process.host_id
            end
            do_connect_to(input_port, policy)
            self
        rescue Orocos::ConnectionFailed => e
            raise e, "failed to connect #{full_name} => #{input_port.full_name} with policy #{policy.inspect}"
        end
    end

    # Instances of this class allow to read a component's output port. They are
    # obtained from OutputPort#reader
    class OutputReader
	class << self
	    # The only way to create an OutputReader object is OutputPort#reader
	    private :new
	end

        def full_name
            "#{port.full_name}.reader"
        end

        OLD_DATA = 0
        NEW_DATA = 1

        # The OutputPort object this reader is linked to
        attr_reader :port

        def read_helper(sample, copy_old_data) # :nodoc:
	    if process = port.task.process
		if !process.alive?
		    disconnect
		    raise CORBA::ComError, "remote end is dead"
		end
	    end

            if sample
                if sample.class != port.type
                    raise ArgumentError, "wrong sample type #{sample.class}, expected #{port.type}"
                end
                value = sample
            else
                value = port.type.new
            end

            if result = do_read(port.orocos_type_name, value, copy_old_data)
                return [Typelib.to_ruby(value), result]
            end
        end

        # Reads a sample on the associated output port.
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
        def read(sample = nil)
            if value = read_helper(sample, true)
                value[0]
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
            if value = read_helper(sample, false)
                value[0] if value[1] == NEW_DATA
            end
        end
        
        # Returns a new sample that can be used with read_new 
        def new_sample; port.new_sample end
    end

    # Instances of InputWriter allows to write data to a component's input port.
    # 
    # They are returned by InputPort#writer
    class InputWriter
	class << self
	    # The only way to create an InputWriter object is InputPort#writer
	    private :new
	end

        def full_name
            "#{port.full_name}.writer"
        end

        # The InputPort object this writer is linked to
        attr_reader :port

        # Returns a new sample that can be used to write on this port
        def new_sample; port.new_sample end

        # Write a sample on the associated input port.
        #
        # If the data type is a struct, the sample can be provided either as a
        # Typelib instance object or as a hash.
        #
        # In the first case, one can do:
        #
        #   value = input_port.new_sample # Get a new sample from the port
        #   value = input_writer.new_sample # Get a new sample from the writer
        #   value.field = 10
        #   value.other_field = "a_string"
        #   input_writer.write(value)
        #
        # In the second case, 
        #   input_writer.write(:field => 10, :other_field => "a_string")
        #   
        # Raises CORBA::ComError if the communication is broken.
        def write(data)
	    if process = port.task.process
		if !process.alive?
		    disconnect
		    raise CORBA::ComError, "remote end is dead"
		end
	    end

            data = Typelib.from_ruby(data, port.type)
            do_write(port.orocos_type_name, data)
        end
    end
end

