module Orocos
    module ROS
        class << self
            # The caller ID for this process. Defaults to orocosrb_#{pid}
            attr_accessor :caller_id
            # Returns the sytem state as reported by the ROS Master
            def self.system_state
                ros_master.getSystemState(caller_id)
            end
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
        @caller_id = "orocosrb_#{::Process.pid}"


        # A name service implementation that allows to enumerate all ROS nodes
        class NameService < Orocos::NameServiceBase
            attr_reader :uri
            attr_reader :caller_id

            def initialize(uri = ENV['ROS_MASTER_URI'], caller_id = ROS.caller_id)
                @uri = uri
                @caller_id = caller_id
                super()
            end

            def ros_master
                @ros_master ||= ROSMaster.new(uri, caller_id)
            end

            def get(name, options = Hash.new)
                node_uri = ros_master.lookup_node(name)
                server = ROSSlave.new(node_uri, caller_id)
                return Node.new(server, name)
            end
            def names
                state = ros_master.system_state

                result = Set.new
                state.each do |objects|
                    objects.each do |_, node_names|
                        result |= node_names.to_set
                    end
                end
                result
            end
            def validate
                ros_master
            end
        end

    end
end

