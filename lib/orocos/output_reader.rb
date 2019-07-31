module Orocos
    # Local input port that is specifically designed to read to another task's output port
    class OutputReader < RubyTasks::LocalInputPort
        # The port this object is reading from
        attr_accessor :port

        # The policy of the connection
        attr_accessor :policy

        # Reads a sample on the associated output port. Returns a value as soon
        # as a sample has ever been written to the port since the data reader
        # has been created
        #
        # @raise [CORBA::ComError] if the remote process is known to be dead.
        # This is only possible if the remote deployment has been started by
        # this Ruby instance
        def read(sample = nil)
            if !policy[:pull]
                Orocos.allow_blocking_calls do
                    # Non-pull readers are non-blocking
                    super
                end
            else
                super
            end
        end

        # Reads a sample on the associated output port, and returns nil if no
        # new data is available
        #
        # @raise [CORBA::ComError] if the remote process is known to be dead.
        # This is only possible if the remote deployment has been started by
        # this Ruby instance
        # @see read
        def read_new(sample = nil)
            if !policy[:pull]
                Orocos.allow_blocking_calls do
                    # Non-pull readers are non-blocking
                    super
                end
            else
                super
            end
        end

        # Disconnects this port from the port it is reading
        def disconnect
            disconnect_all
        end
    end
end

