# frozen_string_literal: true

require "orocos/test"

describe Orocos::ROS::Node do
    include Orocos
    include Orocos::Spec

    attr_reader :name_service

    before do
        @name_service = Orocos::ROS::NameService.new
    end

    describe "#initialize" do
        before do
            task = new_ruby_task_context "ros_test"
            port = task.create_input_port("out", "/base/Time")
            port.subscribe_to_ros
        end
        it "should be running when accessed from the name service" do
            node = name_service.get(Orocos::ROS.caller_id)
            assert node.running?
        end

        it "should not be running when created from scratch" do
            node = Orocos::ROS::Node.new(name_service, nil, "/mynode")
            assert !node.running?
        end

        it "should be given an empty model" do
            node = name_service.get(Orocos::ROS.caller_id)
            assert node.model
        end

        it "should be given an absolute name" do
            node = name_service.get(Orocos::ROS.caller_id)
            assert_equal Orocos::ROS.caller_id, node.name
        end
    end

    it "should list its subscribed topics as input ports" do
        Orocos.load_typekit "base"
        task = new_ruby_task_context "ros_test"
        port = task.create_input_port("out", "/base/Time")
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

        node = name_service.get(Orocos::ROS.caller_id)
        assert(p = node.find_input_port("ros_test_in"))
        assert_equal "ros_test_in", p.name
        assert_equal "/base/Time", p.orocos_type_name
        assert_equal "/base/Time", p.type.name
        assert_equal "std_msgs/Time", p.ros_message_type
        assert_equal Orocos.registry.get("/base/Time"), p.type
    end

    it "should list its published topics as output ports" do
        Orocos.load_typekit "base"
        task = new_ruby_task_context "ros_test"
        port = task.create_output_port("out", "/base/Time")
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_out")

        node = name_service.get(Orocos::ROS.caller_id)
        assert(p = node.find_output_port("ros_test_out"))
        assert_equal "ros_test_out", p.name
        assert_equal "/base/Time", p.orocos_type_name
        assert_equal "/base/Time", p.type.name
        assert_equal "std_msgs/Time", p.ros_message_type
        assert_equal Orocos.registry.get("/base/Time"), p.type
    end
end
