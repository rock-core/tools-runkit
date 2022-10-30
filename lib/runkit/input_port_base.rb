# frozen_string_literal: true

module Runkit
    # Generic implementation of some methods for all input-port-like objects
    #
    # For #reader to work, the mixed-in class must provide a writer_class
    # singleton method, and must be able to connect to an input port
    module InputPortBase
        # Returns a InputWriter object that allows you to write data to the
        # remote input port.
        def writer(distance: PortBase::D_UNKNOWN, **policy)
            writer = Runkit.ruby_task_access do
                Runkit.ruby_task.create_output_port(
                    self.class.transient_local_port_name(full_name),
                    runkit_type_name,
                    permanent: false,
                    class: self.class.writer_class
                )
            end
            writer.port = self
            writer.policy = policy
            writer.connect_to(self, distance: distance, **policy)
            writer
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

        # This method is part of the connection protocol
        #
        # Whenever an output is connected to an input, if the receiver
        # object cannot resolve the connection, it calls
        # #resolve_connection_from on its target
        #
        # @param source the source object in the connection that is being
        #   created
        # @raise [ArgumentError] if the connection cannot be created
        def resolve_connection_from(source, **_policy)
            raise ArgumentError, "I don't know how to connect #{source} to #{self}"
        end

        # This method is part of the connection protocol
        #
        # Whenever an output is disconnected from an input, if the receiver
        # object cannot resolve the connection, it calls
        # #resolve_disconnection_from on its target
        #
        # @param source the source object in the connection that is being
        #   destroyed
        # @raise [ArgumentError] if the connection cannot be undone (or if it
        #   could not exist in the first place)
        def resolve_disconnection_from(source)
            raise ArgumentError, "I don't know how to disconnect #{source} to #{self}"
        end
    end
end
