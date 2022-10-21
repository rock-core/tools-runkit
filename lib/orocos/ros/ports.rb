# frozen_string_literal: true

module Orocos
    class Port
        def default_ros_topic_name
            "#{task.name}/#{name}"
        end
    end

    class OutputPort
        # Publishes this port on a ROS topic
        def publish_on_ros(topic_name = default_ros_topic_name, policy = {})
            if topic_name.kind_of?(Hash)
                policy = topic_name
                topic_name = default_ros_topic_name
            end
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Unpublishes this port from a ROS topic
        def unpublish_from_ros(topic_name = "#{task.name}/#{name}")
            remove_stream(topic_name)
        end
    end

    class InputPort
        # Subscribes this port on a ROS topic
        def subscribe_to_ros(topic_name = default_ros_topic_name, policy = {})
            if topic_name.kind_of?(Hash)
                policy = topic_name
                topic_name = default_ros_topic_name
            end
            create_stream(Orocos::TRANSPORT_ROS, topic_name, policy)
        end

        # Subscribes this port from a ROS topic
        def unsubscribe_from_ros(topic_name = "#{task.name}/#{name}")
            remove_stream(topic_name)
        end
    end
end
