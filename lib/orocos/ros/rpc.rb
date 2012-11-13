module Orocos
    module ROS
        def self.initialize(name)
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
        end
    end
end


