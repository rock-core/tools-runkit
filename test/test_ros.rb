$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

TEST_DIR = File.expand_path(File.dirname(__FILE__))
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

describe Orocos::ROS do
    include Orocos
    include Orocos::Spec

    it "should return true for a known mapping" do
        Orocos.load_typekit 'base'
        assert Orocos::ROS.compatible_message_type?('std_msgs/Time')
    end
end

describe Orocos::ROS::Node do
    include Orocos
    include Orocos::Spec

    attr_reader :name_service

    before do
        @name_service = Orocos::ROS::NameService.new
    end

    it "should list its subscribed topics as input ports" do
        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        port = task.create_input_port('out', '/base/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

        node = name_service.get(Orocos::ROS.caller_id)
        assert(p = node.find_input_port('ros_test_in'))
        assert_equal 'ros_test_in', p.name
        assert_equal '/base/Time', p.orocos_type_name
        assert_equal '/base/Time', p.type_name
        assert_equal 'std_msgs/Time', p.ros_message_type
        assert_equal Orocos.registry.get('/base/Time'), p.type
    end

    it "should be able to write data to input topics" do
        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        port = task.create_input_port('out', '/base/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

        node = name_service.get(Orocos::ROS.caller_id)
        topic = node.find_input_port('ros_test_in')
        writer = topic.writer
        sample = port.new_sample
        sample.microseconds = 342235
        writer.write sample
        # Account for latency in the communication channel
        100.times do
            if data = port.read_new
                assert_equal sample, data
                return
            end
            sleep 0.05
        end
    end

    it "should list its published topics as output ports" do
        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        port = task.create_output_port('out', '/base/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_out")

        node = name_service.get(Orocos::ROS.caller_id)
        puts node.each_output_port.map(&:name).join(", ").inspect
        assert(p = node.find_output_port('ros_test_out'))
        assert_equal 'ros_test_out', p.name
        assert_equal '/base/Time', p.orocos_type_name
        assert_equal '/base/Time', p.type_name
        assert_equal 'std_msgs/Time', p.ros_message_type
        assert_equal Orocos.registry.get('/base/Time'), p.type
    end

    it "should be able to read data from output topics" do
        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        port = task.create_output_port('out', '/base/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_out")

        node = name_service.get(Orocos::ROS.caller_id)
        topic = node.find_output_port('ros_test_out')
        reader = topic.reader
        sample = port.new_sample
        sample.microseconds = 342235
        port.write sample
        # Account for latency in the communication channel
        100.times do
            if data = reader.read_new
                assert_equal sample, data
                return
            end
            sleep 0.05
        end
    end
end

