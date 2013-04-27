module Orocos
    module ROS
        # A Port-compatible implementation of a ROS topic. To map topics to
        # ports, a Node will announce all the topics it is subscribed / it
        # publishes as its own ports
        class Topic
            # The node this topic is associated with
            attr_reader :task
            # The "port name", which is not necessarily the topic name
            attr_reader :name
            # The topic name
            attr_reader :topic_name
            # The topic type, as a typelib type
            attr_reader :type
            # The topic type name
            attr_reader :type_name
            # The topic's type as an orocos type name
            attr_reader :orocos_type_name
            # The ROS message type name
            attr_reader :ros_message_type
            # Documentation string
            attr_reader :doc

            def doc?; false end

            def full_name
                "#{task.name}/#{name}"
            end

            def new_sample; type.new end

            @@local_transient_port_id = 0
            def self.transient_local_port_name(topic_name)
                "rostopics#{topic_name.gsub('/', '.')}.#{@@local_transient_port_id += 1}"
            end

            def initialize(task, topic_name, ros_message_type, model = nil,
                           name = topic_name.gsub(/^~?\//, ''),
                           orocos_type_name = nil)
                @task = task
                @name = name
                @ros_message_type = ros_message_type
                @model = model
                @topic_name = topic_name
                @orocos_type_name = orocos_type_name

                if !@orocos_type_name
                    candidates = ROS.find_all_types_for(ros_message_type)
                    if candidates.empty?
                        raise ArgumentError, "ROS message type #{ros_message_type} has no corresponding type on the oroGen side"
                    end
                    @orocos_type_name ||= candidates.first
                end

                @type =
                    begin
                        Orocos.typelib_type_for(@orocos_type_name)
                    rescue Typelib::NotFound
                        Orocos.load_typekit_for(@orocos_type_name)
                        Orocos.typelib_type_for(@orocos_type_name)
                    end
                @type_name = @type.name
            end

            def pretty_print(pp) # :nodoc:
                pp.text " #{name} (#{type_name}), ros: #{topic_name}(#{ros_message_type})"
            end

            def connect_to(port, policy = Hash.new)
                port.subscribe_to_ros(topic_name, policy)
            end

            def disconnect_from(port)
                port.remove_stream(topic_name)
            end
        end

        class OutputTopic < Topic
            def reader(policy = Hash.new)
                # Create ourselves a transient port on Orocos.ruby_task and
                # connect it to the topic
                reader = Orocos.ruby_task.create_input_port(
                    Topic.transient_local_port_name(topic_name),
                    orocos_type_name,
                    :permanent => false,
                    :class => OutputReader)
                reader.port = self
                reader.policy = policy
                reader.subscribe_to_ros(topic_name, policy)
                reader
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
            def writer(policy = Hash.new)
                # Create ourselves a transient port on Orocos.ruby_task and
                # connect it to the topic
                writer = Orocos.ruby_task.create_output_port(
                    Topic.transient_local_port_name(topic_name),
                    orocos_type_name,
                    :permanent => false,
                    :class => InputWriter)
                writer.port = self
                writer.policy = policy
                writer.publish_on_ros(topic_name, policy)
                writer
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

    class OutputPort
        # Publishes this port on a ROS topic
        def publish_on_ros(topic_name, policy = Hash.new)
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Unpublishes this port from a ROS topic
        def unpublish_from_ros(topic_name)
            remove_stream(topic_name)
        end
    end

    class InputPort
        # Subscribes this port on a ROS topic
        def subscribe_to_ros(topic_name, policy = Hash.new)
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Subscribes this port from a ROS topic
        def unsubscribe_from_ros(topic_name)
            remove_stream(topic_name)
        end
    end
end

