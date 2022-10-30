# frozen_string_literal: true

module Runkit
    # This class represents output ports on remote task contexts.
    #
    # They are obtained from TaskContext#port or TaskContext#each_port
    class OutputPort < Port
        include OutputPortBase

        def pretty_print(pp) # :nodoc:
            pp.text "out "
            super
        end

        # Used by OutputPortReadAccess to determine which output reader class
        # should be used
        def self.reader_class
            OutputReader
        end

        # (see PortBase#input?)
        def input?
            false
        end

        # Connect this output port to an input port. +options+ defines the
        # connection policy for the connection. If a task is given instead of
        # an input port the method will try to find the right input port
        # by type and will raise an error if there are
        # none or more than one matching input ports
        #
        # The following options are available:
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
        def connect_to(input_port, distance: D_UNKNOWN, **options)
            return super unless input_port.respond_to?(:to_runkit_port)

            input_port = input_port.to_runkit_port
            if !input_port.kind_of?(InputPort) # rubocop:disable Style/GuardClause
                raise ArgumentError, "an output port can only connect to an input port (got #{input_port})"
            elsif input_port.type.name != type.name
                raise ArgumentError, "trying to connect #{self}, an output port of type #{type.name}, to #{input_port}, an input port of type #{input_port.type.name}"
            end

            policy = Port.prepare_policy(**options)
            if distance == D_SAME_HOST
                policy = handle_mq_transport(input_port.full_name, policy)
            end
            input_port.blocking_read = true if policy[:pull]

            begin
                refine_exceptions(input_port) do
                    do_connect_to(input_port, policy)
                end
            rescue Runkit::ConnectionFailed
                if policy[:transport] == TRANSPORT_MQ && Runkit::MQueue.auto_fallback_to_corba?
                    policy[:transport] = TRANSPORT_CORBA
                    Runkit.warn "failed to create a connection from #{full_name} to #{input_port.full_name} using the MQ transport, falling back to CORBA"
                    retry
                end
                raise
            end

            self
        rescue Runkit::ConnectionFailed => e
            raise e, "failed to connect #{full_name} => #{input_port.full_name} with policy #{policy.inspect}"
        end

        # Require this port to disconnect from the provided input port
        def disconnect_from(input)
            return super unless input.respond_to?(:to_runkit_port)

            input = input.to_runkit_port
            refine_exceptions(input) do
                do_disconnect_from(input)
            end
        end
    end
end
