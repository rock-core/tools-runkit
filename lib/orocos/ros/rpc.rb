module Orocos
    module ROS
        class << self
            # The caller ID for this process. Defaults to orocosrb_<pid>
            attr_accessor :caller_id
            # Returns the URI to the ROS master
            def self.ros_master_uri
                ENV['ROS_MASTER_URI']
            end
            # The global ROS master as a XMLRPC object
            #
            # It gets initialized on first call
            #
            # @raise [Orocos::ComError] if the ROS master is not available
            def self.ros_master
                @ros_master ||= XMLRPC::Client::Proxy.new(ros_master_uri, '')
            end
        end
        @caller_id = "/orocosrb_#{::Process.pid}"

        def self.initialize(name = ROS.caller_id[1..-1])
            if initialized?
                raise RuntimeError, "cannot initialize the ROS layer multiple times"
            end

            do_initialize(name)
            at_exit do
                Orocos::ROS.shutdown
            end
        end

        # Common handling for the ROS master/slave API
        class ROS_XMLRPC
            class CallFailed < RuntimeError; end

            # [XMLRPC::Client] The remote server
            attr_reader :server
            # [String] the caller ID for this process
            attr_reader :caller_id

            def initialize(uri, caller_id)
                @server = XMLRPC::Client.new2(uri)
                @caller_id = caller_id
            end

            def call(method_name, *args)
                code, status_msg, result = server.call(method_name, *args)
                if code == -1
                    raise ArgumentError, status_msg
                elsif code == 0
                    raise CallFailed, status_msg
                else
                    result
                end
            rescue Errno::ECONNREFUSED, Errno::EPIPE, Errno::ECONNRESET => e
                raise ComError, e.message, e.backtrace
            end
        end

        # Access to a remote ROS master
        class ROSMaster < ROS_XMLRPC
            def system_state
                call('getSystemState', caller_id)
            end

            def lookup_node(name)
                call('lookupNode', caller_id, name)
            end
        end

        # Access to a remote ROS slave
        class ROSSlave < ROS_XMLRPC
            # [Array<Array<(String,String)>>] the list of subscriptions as
            # [topic_name, topic_type_name] pairs
            def subscriptions
                call('getSubscriptions', caller_id)
            end

            # [Array<Array<(String,String)>>] the list of publications as
            # [topic_name, topic_type_name] pairs
            def publications
                call('getPublications', caller_id)
            end

            # [String] the URI of the master that manages this slave
            def pid
                call('getPid', caller_id)
            end

            # [String] the URI of the master that manages this slave
            def master_uri
                call('getMasterUri', caller_id)
            end
        end
    end
end


