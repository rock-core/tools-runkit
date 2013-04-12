module Orocos
    module ROS
        # A representation of the overall ROS node graph. This is used as it is
        # a lot cheaper to query the ROS master directly using getSystemState
        # than calling getPublishers / getSubscribers on each individual slaves
        class NodeGraph
            def self.from_system_state(state, topics)
                graph = new
                graph.initialize_from_system_state(state, topics)
                graph
            end

            # Set<Array(String,String)> The set of known topics, as pairs of
            # [topic_names, topic_msg_name]
            attr_reader :topic_types
            # Hash<String,Array(Set<String>,Set<String>)> mapping from a node
            # name to the set of input topics and output topics. The set of
            # known node names is nodes.keys
            attr_reader :node_graph

            def initialize
                @topic_types = Hash.new
                @node_graph = Hash.new
            end

            def initialize_from_system_state(state, topics)
                @topic_types = Hash[*topics.flatten]
                state[0].each do |topic_name, publishers|
                    publishers.each do |node_name|
                        node_graph[node_name] ||= [Set.new, Set.new]
                        node_graph[node_name][1] << topic_name
                    end
                end
                state[1].each do |topic_name, subscribers|
                    subscribers.each do |node_name|
                        node_graph[node_name] ||= [Set.new, Set.new]
                        node_graph[node_name][0] << topic_name
                    end
                end
            end

            # Returns the set of topic names that are published by the given
            # node
            def output_topics_for(node_name)
                node_graph[node_name][1] || Set.new
            end

            # Returns the set of topic names that are subscribed by the given
            # node
            def input_topics_for(node_name)
                node_graph[node_name][0] || Set.new
            end

            # Returns the set of known topic names
            def topics
                topic_types.keys
            end

            # Returns the message type name for this topic
            #
            # @return nil if the topic name is not known to us
            def topic_message_type(topic_name)
                topic_types[topic_name]
            end

            # Returns true if the given name is a known name for a topic
            def has_topic?(name)
                topic_types.has_key?(name)
            end

            # Returns the set of known node names
            def nodes
                node_graph.keys
            end

            # Returns true if the given name is a known name for a node
            def has_node?(name)
                node_graph.has_key?(name)
            end
        end

        # A name service implementation that allows to enumerate all ROS nodes
        class NameService < Orocos::NameServiceBase
            attr_reader :uri
            attr_reader :caller_id

            attr_reader :ros_graph
            attr_reader :poll_period

            # The Utilrb::ThreadPool object that handles the asynchronous update
            # of the ROS node graph
            # @return [Utilrb::ThreadPool]
            attr_reader :thread_pool

            def initialize(uri = ENV['ROS_MASTER_URI'], caller_id = ROS.caller_id)
                @uri = uri
                @caller_id = caller_id
                @ros_graph = NodeGraph.new
                @mutex = Mutex.new
                @ros_master_sync = Mutex.new
                @updated_graph_signal = ConditionVariable.new
                @poll_period = 0.1
                super()

                @ros_master = ROSMaster.new(uri, caller_id)
                @thread_pool = Utilrb::ThreadPool.new(0, 2)
                poll_system_state
            end

            def poll_system_state
                thread_pool.process_with_options(
                    Hash[:sync_key => @ros_master,
                         :callback => method(:done_system_state)]) do

                    @ros_master_sync.synchronize do
                        state  = @ros_master.system_state
                        topics = @ros_master.topics
                        NodeGraph.from_system_state(state, topics)
                    end
                end
            end

            def done_system_state(graph, exception)
                @mutex.synchronize do
                    @ros_graph = graph
                    @ros_master_exception = exception
                    @updated_graph_signal.broadcast
                    sleep(poll_period)
                    poll_system_state
                end
            end

            def access_ros_graph
                @mutex.synchronize do
                    if @ros_master_exception
                        raise @ros_master_exception
                    end
                    yield
                end
            end

            def get(name, options = Hash.new)
                access_ros_graph do
                    if !ros_graph.has_node?(name)
                        raise Orocos::NotFound, "no such ROS node #{name}"
                    end
                end

                slave_uri =
                    begin
                        @ros_master_sync.synchronize do
                           @ros_master.lookup_node(name)
                        end
                    rescue ArgumentError
                        raise Orocos::NotFound, "no such ROS node #{name}"
                    end
                server = ROSSlave.new(slave_uri, caller_id)
                return Node.new(self, server, name)
            end

            def names
                @mutex.synchronize { ros_graph.nodes.dup }
            end

            def validate
                @mutex.synchronize do
                    if @ros_master_exception
                        raise @ros_master_exception
                    end
                    @updated_graph_signal.wait(@mutex)
                end
                access_ros_graph { }
            end
        end
    end
end

