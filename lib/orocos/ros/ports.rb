module Orocos
    class Port
        def default_ros_topic_name
            "#{task.name}/#{self.name}"
        end
    end

    class OutputPort
        # Publishes this port on a ROS topic
        def publish_on_ros(topic_name = default_ros_topic_name, policy = Hash.new)
            if topic_name.kind_of?(Hash)
                topic_name, policy = default_ros_topic_name, topic_name
            end
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Unpublishes this port from a ROS topic
        def unpublish_from_ros(topic_name = "#{task.name}/#{self.name}")
            remove_stream(topic_name)
        end
    end

    class InputPort
        # Subscribes this port on a ROS topic
        def subscribe_to_ros(topic_name = default_ros_topic_name, policy = Hash.new)
            if topic_name.kind_of?(Hash)
                topic_name, policy = default_ros_topic_name, topic_name
            end
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Subscribes this port from a ROS topic
        def unsubscribe_from_ros(topic_name = "#{task.name}/#{self.name}")
            remove_stream(topic_name)
        end
    end
end

