# frozen_string_literal: true

require "runkit/rrunkit"
require "typelib"

module Runkit
    Port.transport_names[TRANSPORT_CORBA] = "CORBA"

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
                raise "the maximum message size can only be changed before the CORBA layer is initialized" if initialized?

                ENV["ORBgiopMaxMsgSize"] = value.to_int.to_s
            end
        end

        # The max message size is a DOS-protection feature. Honestly, given our
        # usage of CORBA, an attacker would have much worse ways to DOS a Rock
        # system.
        #
        # Since it does get in the way, just set it to the maximum admissible
        # value
        self.max_message_size = 1 << 32 - 1 unless ENV["ORBgiopMaxMsgSize"]

        class << self
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

        # @deprecated use {Runkit.load_typekit} instead
        def self.load_typekit(name)
            Runkit.load_typekit(name)
        end

        # Initialize the CORBA layer
        #
        # It does not need to be called explicitely, as it is called by
        # Runkit.initialize
        def self.initialize
            # setup environment which is used by the runkit.rb
            ENV["ORBInitRef"] = "NameService=corbaname::#{CORBA.name_service.ip}" unless CORBA.name_service.ip.empty?

            self.call_timeout    ||= 20_000
            self.connect_timeout ||= 2000
            do_init

            # check if name service is reachable
            CORBA.name_service.validate
        end

        def self.get(method, name)
            raise NotInitialized, "the CORBA layer is not initialized, call Runkit.initialize first" unless Runkit::CORBA.initialized?

            result = ::Runkit::CORBA.refine_exceptions("naming service") do
                ::Runkit::TaskContext.send(method, name)
            end
            result
        end

        # Deinitializes the CORBA layer
        #
        # It shuts down the CORBA access and deregisters the Ruby process from
        # the server
        def self.deinit
            do_deinit
        end

        def self.clear
            @name_service = nil
        end

        # Improves exception messages for exceptions that are raised from the
        # C++ extension
        def self.refine_exceptions(obj0, obj1 = nil) # :nodoc:
            yield
        rescue ComError => e
            if !obj1
                raise ComError, "Communication failed with corba #{obj0}", e.backtrace
            else
                raise ComError, "communication failed with either #{obj0} or #{obj1}", e.backtrace
            end
        end
    end
end
