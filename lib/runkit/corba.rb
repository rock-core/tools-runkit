# frozen_string_literal: true

module Runkit
    Port.transport_names[TRANSPORT_CORBA] = "CORBA"

    # Management of the CORBA layer for communication with the RTT components
    module CORBA
        extend Logger::Forward
        extend Logger::Hierarchy

        class << self
            # The maximum message size, in bytes, allowed by the omniORB. It can
            # only be set before Runkit.initialize is called
            #
            # runkit.rb sets the default to 4GB (the maximum)
            attr_reader :max_message_size

            def max_message_size=(value)
                if initialized?
                    raise "the maximum message size can only be changed "\
                          "before the CORBA layer is initialized"
                end

                ENV["ORBgiopMaxMsgSize"] = value.to_int.to_s
            end

            # Returns the current timeout for method calls, in milliseconds
            # Runkit.rb sets it to 20000 ms by default
            #
            # See #call_timeout= for a complete description
            attr_reader :call_timeout

            # Sets the timeout, in milliseconds, for a CORBA method call to be
            # completed. It means that no method call can exceed the specified
            # value.
            def call_timeout=(value)
                do_call_timeout(value)
                @call_timeout = value
            end

            # Returns the timeout, in milliseconds, before a connection creation
            # fails.
            # Runkit.rb sets it to 2000 ms by default
            #
            # See #connect_timeout=
            attr_reader :connect_timeout

            # Sets the timeout, in milliseconds, before a connection creation
            # fails.
            def connect_timeout=(value)
                do_connect_timeout(value)
                @connect_timeout = value
            end
        end

        # The max message size is a DOS-protection feature. Honestly, given our
        # usage of CORBA, an attacker would have much worse ways to DOS a Rock
        # system.
        #
        # Since it does get in the way, just set it to the maximum admissible
        # value
        self.max_message_size = 1 << 32 - 1 unless ENV["ORBgiopMaxMsgSize"]

        # Initialize the CORBA layer
        #
        # It does not need to be called explicitely, as it is called by
        # Runkit.initialize
        def self.initialize
            self.call_timeout    ||= 20_000
            self.connect_timeout ||= 2000
            do_initialize
        end

        def self.clear
            # Do nothing
            #
            # We can't really de-initialize the ORB, as it would require disposing
            # of all ruby task contexts first.
        end

        # Improves exception messages for exceptions that are raised from the
        # C++ extension
        def self.refine_exceptions(obj0, obj1 = nil) # :nodoc:
            yield
        rescue ComError => e
            if obj1
                raise ComError,
                      "communication failed with either #{obj0} or #{obj1}",
                      e.backtrace
            end

            raise ComError, "Communication failed with corba #{obj0}", e.backtrace
        end
    end
end
