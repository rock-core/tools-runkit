module Orocos
    # Local output port that is specifically designed to write to another task's input port
    class InputWriter < RubyTasks::LocalOutputPort
        # The port this object is reading from
        attr_accessor :port

        # The policy of the connection
        attr_accessor :policy

        # Disconnects this port from the port it is reading
        def disconnect
            disconnect_all
        end

        # Write data on the associated input port
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
end

