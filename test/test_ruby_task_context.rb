$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::RubyTaskContext do
    include Orocos
    include Orocos::Spec

    it "should be registered on the name server" do
        task = new_ruby_task_context("task")
        assert Orocos.name_service.get("task")
    end

    it "should refer to a LocalTaskContext object that refers to it back" do
        task = new_ruby_task_context("task")
        assert_same task, task.instance_variable_get(:@local_task).remote_task
    end

    it "can create output ports" do
        task = new_ruby_task_context("producer")
        port = task.create_output_port("p", "int")
        assert_kind_of Orocos::OutputPort, port
        assert_equal task, port.task
        assert_equal "p", port.name

        assert task.has_port?("p")
        assert_kind_of Orocos::OutputPort, task.port("p")
        assert_equal "int", task.port("p").orocos_type_name
    end

    it "can create input ports" do
        task = new_ruby_task_context("producer")
        port = task.create_input_port("p", "int")

        assert_kind_of Orocos::InputPort, port
        assert task.has_port?("p")
        assert_kind_of Orocos::InputPort, task.port("p")
        assert_equal "int", task.port("p").orocos_type_name
    end

    it "can write and read on ports" do
        producer = new_ruby_task_context("producer")
        out_p = producer.create_output_port("p", "int")
        consumer = new_ruby_task_context("consumer")
        in_p = consumer.create_input_port("p", "int")

        out_p.connect_to in_p
        out_p.write 10
        assert_equal 10, in_p.read
    end

    it "can create a property" do
        task = new_ruby_task_context("task")
        property = task.create_property('prop', 'int')
        assert_kind_of Orocos::Property, property
        assert_same property, task.property('prop')
        assert task.has_property?('prop')
    end

    it "can read and write properties" do
        task = new_ruby_task_context("task")
        property = task.create_property('prop', 'int')
        property.write(10)
        assert_equal 10, property.read
        property.write(20)
        assert_equal 20, property.read
    end

    it "allows to handle the normal state changes" do
        task = new_ruby_task_context('task')
        assert_equal :STOPPED, task.rtt_state
        task.start
        assert_equal :RUNNING, task.rtt_state
        task.stop
        assert_equal :STOPPED, task.rtt_state
    end
end

