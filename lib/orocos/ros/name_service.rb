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
                state[2].each do |service_name, providers|
                    providers.each do |node_name|
                        node_graph[node_name] ||= [Set.new, Set.new]
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

            # The time of the last update to ros_graph. This is the time at
            # which the XMLRPC request has been made
            # @return [Time]
            attr_reader :update_time
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
                @update_time = Time.at(0)
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
                        new_update_time = Time.now
                        state  = @ros_master.system_state
                        topics = @ros_master.topics
                        [new_update_time, NodeGraph.from_system_state(state, topics)]
                    end
                end
            end

            def update_system_state(update_time, graph, exception)
                @mutex.synchronize do
                    if !exception
                        @update_time = update_time
                        @ros_graph = graph
                    end
                    @ros_master_exception ||= exception
                    @updated_graph_signal.broadcast
                end
            end

            def done_system_state(result, exception)
                time, graph = *result
                update_system_state(time, graph, exception)
                sleep(poll_period)
                poll_system_state
            end

            def get(name, options = Hash.new)
                options = Kernel.validate_options options, :retry => true
                has_node = access_ros_graph do
                    ros_graph.has_node?(name)
                end

                if !has_node
                    if options[:retry]
                        # Wait for a single update of the graph and try
                        # again
                        wait_for_update
                        get(name, :retry => false)
                    else
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
                wait_for_update do
                    ros_graph.nodes.dup
                end
            end

            def retry_after_update_if_nil
                result = yield
                if !result
                    wait_for_update
                    puts "RETRYING"
                    yield
                else result
                end
            end

            # Returns the Topic object that matches the given topic name. If
            # that topic has more than one publisher (yuk), it picks the first
            # one.
            #
            # @return [Topic]
            def find_topic_by_name(topic_name)
                retry_after_update_if_nil do
                    node_name, direction =
                        access_ros_graph do
                            ros_graph.node_graph.find do |node_name, (inputs, outputs)|
                                puts "#{node_name} => #{inputs.to_a}, #{outputs.to_a}"
                                if inputs.include?(topic_name)
                                    break([node_name, :input_port])
                                elsif outputs.include?(topic_name)
                                    break([node_name, :output_port])
                                end
                            end
                        end

                    if node_name
                        puts "node: #{node_name}, direction: #{direction}, topic: #{topic_name}"
                        return get(node_name).send(direction, topic_name)
                    end
                    nil
                end
            end

            # Processes the latest ROS master exception caught
            #
            # It raises the exception and reinitializes the
            # @ros_master_exception attribute so that the next error can be
            # caught as well
            #
            # It must be called with @mutex locked
            def process_ros_master_exception
                exception, @ros_master_exception = @ros_master_exception, nil
                if exception
                    raise exception
                end
            end

            # Wait for the ROS graph to be updated at least once
            #
            # @arg [Time,nil] if given, the new graph should be newer than
            #   this time. Otherwise, we simply wait for any update
            # @yield in a context where it is safe to access the ROS graph
            #   object. The block is optional
            # @return the value returned by the given block, if a block was
            #   given
            # @raise any error that has occured during ROS graph update
            def wait_for_update(barrier = Time.now)
                result = @mutex.synchronize do
                    barrier = update_time
                    while update_time <= barrier
                        process_ros_master_exception
                        @updated_graph_signal.wait(@mutex)
                    end

                    if block_given?
                        yield
                    end
                    process_ros_master_exception
                end
                result
            end

            # Gives thread-safe access to the ROS graph
            #
            # @raise any error that has occured during ROS graph update
            # @return [void]
            def access_ros_graph
                @mutex.synchronize do
                    process_ros_master_exception
                    yield if block_given?
                end
            end

            # Validates that this name service can be used
            #
            # @raise any error that has occured during ROS graph update
            def validate
                wait_for_update
            end

            # Provide thread-safe access to the ROS graph API
            def method_missing(m, *args, &block)
                access_ros_graph do
                    if ros_graph.respond_to?(m)
                        return ros_graph.send(m, *args, &block)
                    end
                super
                end
            end
        end
    end
end

