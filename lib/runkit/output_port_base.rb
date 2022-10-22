# frozen_string_literal: true

module Runkit
    # Generic functionality for all output objects
    #
    # For {#reader} to work, the mixed-in class must provide a reader_class
    # singleton method, and must be able to connect to an input port
    #
    # It also implements the fallback calls for the connection / disconnection
    # protocol. Any 'output port' class must call this generic implementation
    # when it does not know how to connect to / disconnect from the argument it
    # has been given. The 'input port' classes that can handle specialized
    # connection schemes must then implement #resolve_connection_from and
    # #resolve_disconnection_from to implement them. These methods are called by
    # the default implementation of #connect_to and #disconnect_from.
    module OutputPortBase
        # Returns an OutputReader object that is connected to that port
        #
        # The policy dictates how data should flow between the port and the
        # reader object. See #prepare_policy
        def reader(distance: PortBase::D_UNKNOWN, **policy)
            ensure_type_available
            reader = Runkit.ruby_task_access do
                Runkit.ruby_task.create_input_port(
                    self.class.transient_local_port_name(full_name),
                    runkit_type_name,
                    permanent: false,
                    class: self.class.reader_class
                )
            end
            reader.port = self
            reader.policy = policy
            connect_to(reader, distance: distance, **policy)
            reader
        end

        # Generic implementation of #connect_to
        #
        # It calls #resolve_connection_from, as a fallback for
        # out.connect_to(in) calls where 'out' does not know how to handle 'in'
        def connect_to(sink, policy = {})
            sink.resolve_connection_from(self, policy)
        end

        # Generic implementation of #disconnect_from
        #
        # It calls #resolve_connection_from, as a fallback for
        # out.connect_to(in) calls where 'out' does not know how to handle 'in'
        def disconnect_from(sink)
            sink.resolve_disconnection_from(self)
        end
    end
end
