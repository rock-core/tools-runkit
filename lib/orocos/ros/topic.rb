module Orocos
    module ROS
        # A Port-compatible implementation of a ROS topic. To map topics to
        # ports, a Node will announce all the topics it is subscribed / it
        # publishes as its own ports
        class Topic
            include PortBase

            # The topic name
            attr_reader :topic_name
            # The ROS message type name
            attr_reader :ros_message_type
            # Documentation string
            attr_reader :doc

            def doc?; false end

            @@local_transient_port_id = 0
            def self.transient_local_port_name(topic_name)
                "rostopics#{topic_name.gsub('/', '.')}.#{@@local_transient_port_id += 1}"
            end

            # @return [String] the default port name generated from a topic name
            def self.default_port_name(topic_name)
                topic_name.gsub(/^~?\//, '')
            end

            def initialize(task, topic_name, ros_message_type, model = nil,
                           name = Topic.default_port_name(topic_name),
                           orocos_type_name = nil)

                if !orocos_type_name
                    candidates = ROS.find_all_types_for(ros_message_type)
                    if candidates.empty?
                        raise ArgumentError, "ROS message type #{ros_message_type} has no corresponding type on the oroGen side"
                    end
                    orocos_type_name = candidates.first
                end

                @ros_message_type = ros_message_type
                @topic_name = topic_name

                super(task, name, orocos_type_name, model)
            end

            def pretty_print(pp) # :nodoc:
                pp.text " #{name} (#{orocos_type_name}), ros: #{topic_name}(#{ros_message_type})"
            end

            def ==(other)
                other.class == self.class &&
                    other.topic_name == self.topic_name &&
                    other.task == self.task
            end
        end

        class OutputTopic < Topic
            include OutputPortBase

            # Used by OutputPortReadAccess to determine which output reader class
            # should be used
            def self.reader_class; OutputReader end

            # Subscribes an input to this topic
            #
            # @param [#to_orocos_port] sink the sink port
            def connect_to(sink, policy = Hash.new)
                if sink.respond_to?(:to_topic)
                    sink = sink.to_topic
                    if self.task.running? || sink.task.running?
                        raise ArgumentError, "cannot use #connect_to on topics from running nodes"
                    end

                    sink.topic_name = self.topic_name
                elsif sink.respond_to?(:to_orocos_port)
                    sink.to_orocos_port.subscribe_to_ros(topic_name, policy)
                else
                    return super
                end
            end

            # Unsubscribes an input to this topic
            #
            # @param [#to_orocos_port] sink the sink port
            def disconnect_from(sink)
                if sink.respond_to?(:to_topic)
                    sink = sink.to_topic
                    if self.task.running? || sink.task.running?
                        raise ArgumentError, "cannot use #disconnect_from topics from running nodes"
                    end

                    sink.topic_name = "#{sink.task.name}/#{sink.name}"
                elsif sink.respond_to?(:to_orocos_port)
                    sink.to_orocos_port.unsubscribe_from_ros(topic_name)
                else
                    return super
                end
            end

            def to_async(options = Hash.new)
                if use = options.delete(:use)
                    Orocos::Async::CORBA::OutputPort.new(use,self)
                else to_async(:use => task.to_async(options))
                end
            end

            def to_proxy(options = Hash.new)
                task.to_proxy(options).port(name,:type => type)
            end
        end

        class InputTopic < Topic
            include InputPortBase

            # The scheme we use for topic connection is to normalize the output
            # topic names as /node/name and then remap the input topics.
            #
            # This allows to overide the topic name on the input topics
            attr_writer :topic_name

            # Used by InputPortWriteAccess to determine which class should be used
            # to create the writer
            def self.writer_class
                InputWriter
            end

            def to_async(options = Hash.new)
                if use = options.delete(:use)
                    Orocos::Async::CORBA::InputPort.new(use,self)
                else to_async(:use => task.to_async(options))
                end
            end

            def to_proxy(options = Hash.new)
                task.to_proxy(options).port(name,:type => type)
            end

            # This method is part of the connection protocol
            #
            # Whenever an output is connected to an input, if the receiver
            # object cannot resolve the connection, it calls
            # #resolve_connection_from on its target
            #
            # @param [#publish_on_ros] port the port that should be
            #   published on ROS
            # @raise [ArgumentError] if the given object cannot be published on
            #   this ROS topic
            def resolve_connection_from(port, options = Hash.new)
                # Note that we are sure that +port+ is an output. We now 'just'
                # have to check what kind of output, and act accordingly
                if port.respond_to?(:publish_on_ros)
                    port.publish_on_ros(topic_name, options)
                else
                    raise ArgumentError, "I don't know how to connect #{port} to #{self}"
                end
            end

            # This method is part of the connection protocol
            #
            # Whenever an output is connected to an input, if the receiver
            # object cannot resolve the connection, it calls
            # #resolve_disconnection_from on its target
            #
            # @param [#unpublish_from_ros] port the port that should be
            #   published on ROS
            # @raise [ArgumentError] if the given object cannot be unpublished from
            #   this ROS topic
            def resolve_disconnection_from(port, options = Hash.new)
                # Note that we are sure that +port+ is an output. We now 'just'
                # have to check what kind of output, and act accordingly
                if port.respond_to?(:unpublish_from_ros)
                    port.unpublish_from_ros(topic_name)
                else
                    raise ArgumentError, "I don't know how to disconnect #{port} from #{self}"
                end
            end
        end

        # Resolves an existing topic by name
        #
        # @raise [NotFound] if the topic does not exist
        def self.topic(name)
            Orocos.name_service.each do |ns|
                if ns.respond_to?(:find_topic_by_name)
                    if topic = ns.find_topic_by_name(name)
                        return topic
                    end
                end
            end
            raise NotFound, "topic #{name} does not seem to exist"
        end
    end
end

