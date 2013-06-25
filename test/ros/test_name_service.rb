$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::ROS::NameService do
    include Orocos
    include Orocos::Spec

    attr_reader :name_service

    before do
        @name_service = Orocos::ROS::NameService.new

        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        port = task.create_input_port('out', '/base/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

    end

    it "should allow to list registered nodes" do
        # Verify that the local Ruby process can be listed through the name
        # service
        assert name_service.names.include?(Orocos::ROS.caller_id), "expected to find #{Orocos::ROS.caller_id} in the list of known ROS nodes, but got #{name_service.names.to_a.sort}"
    end

    it "should allow to get a node handle" do
        # Verify that the local Ruby process can be listed through the name
        # service
        node = name_service.get(Orocos::ROS.caller_id)
        assert_equal Orocos::ROS.caller_id, node.name
    end

    it "should accept to return a topic by name" do
        sleep 0.1
        topic = name_service.find_topic_by_name('/ros_test_in')
        assert(topic)
        assert_equal 'ros_test_in', topic.name
        assert_equal Orocos::ROS.caller_id, topic.task.name
    end
end


