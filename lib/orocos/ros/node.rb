module Orocos
    module ROS
        # A TaskContext-compatible interface of a ROS node
        #
        # The following caveats apply:
        #
        # * ROS nodes do not have an internal lifecycle state machine. In
        #   practice, it means that #configure has no effect, #start will start
        #   the node's process and #stop will kill it (if we have access to it).
        #   If the ROS process is not managed by orocos.rb, they will throw
        # * ROS nodes do not allow modifying subscriptions at runtime, so the
        #   port connection / disconnection methods can only be used while the
        #   node is not running
        class Node
            # [NameService] access to the state of the ROS graph
            attr_reader :name_service
            # [ROSSlave] access to the node XMLRPC API
            attr_reader :server
            # [String] the node name
            attr_reader :name
            # [Hash<String,Topic>] a cache of the topics that are known to be
            # associated with this node. It should never be used directly, as it
            # may contain stale entries
            attr_reader :topics

            def initialize(name_service, server, name)
                @name_service = name_service
                @server = server
                @name = name
                @input_topics = Hash.new
                @output_topics = Hash.new
            end

            def state
                :RUNNING
            end

            def reachable?
                name_service.has_node?(name)
                true
            rescue ComError
                false
            end

            def doc?; false end
            attr_reader :doc

            def each_property; end


            def has_port?(name)
                !!(find_output_port(name) || find_input_port(name))
            end

            def port(name)
                p = (find_output_port(name) || find_input_port(name))
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} attached to node #{name}"
                end
                p
            end

            def input_port(name)
                p = find_input_port(name)
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} as a subscription of node #{self.name}"
                end
                p
            end

            def output_port(name)
                p = find_output_port(name)
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} as a publication of node #{self.name}"
                end
                p
            end
            
            # Finds the name of a topic this node is publishing
            #
            # @return [ROS::Topic,nil] the topic if found, nil otherwise
            def find_output_port(name, wait_if_unavailable = true)
                each_output_port do |p|
                    if p.name == name
                        return p
                    end
                end
                if wait_if_unavailable
                    name_service.wait_for_update
                    find_output_port(name, false)
                end
            end
            
            # Finds the name of a topic this node is subscribed to
            #
            # @return [ROS::Topic,nil] the topic if found, nil otherwise
            def find_input_port(name, wait_if_unavailable = true)
                each_input_port do |p|
                    if p.name == name
                        return p
                    end
                end
                if wait_if_unavailable
                    name_service.wait_for_update
                    find_input_port(name, false)
                end
            end

            def each_port
                return enum_for(:each_port) if !block_given?
                each_output_port { |p| yield(p) }
                each_input_port { |p| yield(p) }
            end

            # Enumerates each "output topics" of this node
            def each_output_port
                return enum_for(:each_output_port) if !block_given?
                
                name_service.output_topics_for(name).each do |topic_name, topic_type|
                    topic_type = name_service.topic_message_type(topic_name)
                    if ROS.compatible_message_type?(topic_type)
                        topic = (@output_topics[topic_name] ||= OutputTopic.new(self, topic_name, topic_type))
                        yield(topic)
                    end
                end
            end

            # Enumerates each "input topics" of this node
            def each_input_port
                return enum_for(:each_input_port) if !block_given?
                name_service.input_topics_for(name).each do |topic_name|
                    topic_type = name_service.topic_message_type(topic_name)
                    if ROS.compatible_message_type?(topic_type)
                        topic = (@input_topics[topic_name] ||= InputTopic.new(self, topic_name, topic_type))
                        yield(topic)
                    end
                end
            end

            def pretty_print(pp)
                pp.text "ROS Node #{name}"
                pp.breakable

                inputs  = each_input_port.to_a
                outputs = each_output_port.to_a
                ports = enum_for(:each_port).to_a
                if ports.empty?
                    pp.text "No ports"
                    pp.breakable
                else
                    pp.text "Ports:"
                    pp.breakable
                    pp.nest(2) do
                        pp.text "  "
                        each_port do |port|
                            port.pretty_print(pp)
                            pp.breakable
                        end
                    end
                    pp.breakable
                end
            end
        end
    end
end


