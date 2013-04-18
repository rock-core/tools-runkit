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
        end

        class OutputTopic < Topic
            def reader(policy = Hash.new)
                # Create ourselves a transient port on Orocos.ruby_task and
                # connect it to the topic
                reader = Orocos.ruby_task.create_input_port(
                    Topic.transient_local_port_name(topic_name),
                    orocos_type_name,
                    :permanent => false)
                reader.create_stream(Orocos::TRANSPORT_ROS, topic_name)
                reader
            end
        end

        class InputTopic < Topic
            def writer(policy = Hash.new)
                # Create ourselves a transient port on Orocos.ruby_task and
                # connect it to the topic
                writer = Orocos.ruby_task.create_output_port(
                    Topic.transient_local_port_name(topic_name),
                    orocos_type_name,
                    :permanent => false)
                writer.create_stream(Orocos::TRANSPORT_ROS, topic_name)
                writer
            end
        end
    end
end

