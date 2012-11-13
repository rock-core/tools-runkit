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

    def setup
        super
        @allocated_task_contexts = Array.new
    end

    def teardown
        @allocated_task_contexts.each(&:dispose)
        super
    end

    def new_ruby_task_context(name)
        task = Orocos::RubyTaskContext.new(name)
        @allocated_task_contexts << task
        task
    end

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
end

