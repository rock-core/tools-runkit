module Orocos
    module ROS
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
                node_uri =
                    begin ros_master.lookup_node(name)
                    rescue ArgumentError
                        raise Orocos::NotFound, "no such ROS node #{name}"
                    end
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
                result.to_a
            end
            def validate
                names
            end
        end
    end
end

