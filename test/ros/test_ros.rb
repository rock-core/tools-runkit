# frozen_string_literal: true

require "orocos/test"

describe Orocos::ROS do
    attr_reader :name_service
    before do
        @name_service = Orocos::ROS::NameService.new
    end

    describe ".compatible_message_type" do
        it "should return true for a known mapping" do
            Orocos.load_typekit "base"
            assert Orocos::ROS.compatible_message_type?("std_msgs/Time")
        end
    end

    describe ".topic" do
        before do
            Orocos.load_typekit "base"
        end

        it "should resolve a known topic" do
            task = new_ruby_task_context "ros_test"
            port = task.create_input_port("out", "/base/Time")
            port.subscribe_to_ros("/ros_test_in")

            node = name_service.get(Orocos::ROS.caller_id)
            assert(p = node.find_input_port("ros_test_in"))

            topic = Orocos::ROS.topic "/ros_test_in"

            assert_equal p, topic
        end
        it "should raise NotFound for an unknown topic" do
            assert_raises(Orocos::NotFound) do
                Orocos::ROS.topic "/does/not/exist"
            end
        end
    end
end
