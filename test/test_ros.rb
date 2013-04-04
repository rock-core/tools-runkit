$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::ROS::NameService do
    include Orocos
    include Orocos::Spec

    def setup
        if !Orocos::ROS.initialized?
            Orocos::ROS.initialize
        end
        super
    end

    it "should allow to list registered nodes" do
        # Verify that the local Ruby process can be listed through the name
        # service
        ns = Orocos::ROS::NameService.new
        assert ns.names.include?(Orocos::ROS.caller_id), "expected to find #{Orocos::ROS.caller_id} in the list of known ROS nodes, but got #{ns.names.to_a.sort}"
    end

    it "should allow to get a node handle" do
        # Verify that the local Ruby process can be listed through the name
        # service
        ns = Orocos::ROS::NameService.new
        node = ns.get(Orocos::ROS.caller_id)
        assert_equal Orocos::ROS.caller_id, node.name
    end
end

describe Orocos::ROS::Node do
    include Orocos
    include Orocos::Spec

    attr_reader :name_service

    def setup
        if !Orocos::ROS.initialized?
            Orocos::ROS.initialize
        end
        @name_service = Orocos::ROS::NameService.new
        super
    end

    it "should list its subscribed topics as input ports" do
        Orocos.load_typekit 'ros_test'
        task = new_ruby_task_context 'ros_test'
        port = task.create_input_port('out', '/ros_test/CustomConvertedType')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

        node = name_service.get(Orocos::ROS.caller_id)
        assert(p = node.find_input_port('ros_test_in'))
        assert_equal 'ros_test_in', p.name
        assert_equal '/ros_test/CustomConvertedType', p.orocos_type_name
        assert_equal '/ros_test/CustomConvertedType', p.type_name
        assert_equal '/std_msgs/Time', p.ros_message_name
        assert_equal Orocos.registry.get('/ros_test/CustomConvertedType'), p.type
    end

    it "should be able to write data to input topics" do
        Orocos.load_typekit 'ros_test'
        task = new_ruby_task_context 'ros_test'
        port = task.create_input_port('out', '/ros_test/CustomConvertedType')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")

        node = name_service.get(Orocos::ROS.caller_id)
        topic = node.find_input_port('ros_test_out')
        writer = topic.writer
        reader = port.reader
        sample = Types::RosTest::Time.new(:ns => 342235)
        writer.write sample
        # Account for latency in the communication channel
        100.times do
            if data = reader.read_new
                assert_equal sample, data
            end
            sleep 0.05
        end
    end

    it "should list its published topics as output ports" do
        Orocos.load_typekit 'ros_test'
        task = new_ruby_task_context 'ros_test'
        port = task.create_output_port('out', '/ros_test/CustomConvertedType')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_out")

        node = name_service.get(Orocos::ROS.caller_id)
        assert(p = node.find_output_port('ros_test_out'))
        assert_equal 'ros_test_out', p.name
        assert_equal '/ros_test/CustomConvertedType', p.orocos_type_name
        assert_equal '/ros_test/CustomConvertedType', p.type_name
        assert_equal '/std_msgs/Time', p.ros_message_name
        assert_equal Orocos.registry.get('/ros_test/CustomConvertedType'), p.type
    end

    it "should be able to read data from output topics" do
        Orocos.load_typekit 'ros_test'
        task = new_ruby_task_context 'ros_test'
        port = task.create_output_port('out', '/ros_test/Time')
        port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_out")

        node = name_service.get(Orocos::ROS.caller_id)
        topic = node.find_output_port('ros_test_out')
        reader = topic.reader
        writer = port.writer
        sample = Types::RosTest::Time.new(:ns => 342235)
        writer.write sample
        # Account for latency in the communication channel
        100.times do
            if data = reader.read_new
                assert_equal sample, data
            end
            sleep 0.05
        end
    end
end

