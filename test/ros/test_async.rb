$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", '..', "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Async::ROS::NameService do
    include Orocos::Spec

    # The name service instance that is being tested
    attr_reader :ns

    before do
        Orocos::Async.clear
        @ns = Orocos::Async::ROS::NameService.new
    end

    describe "#get" do
        it "should raise NotFound if remote task is not reachable" do
            assert_raises Orocos::NotFound do 
                ns.get "bla"
            end
        end

        it "should not raise NotFound if remote task is not reachable and a block is given" do
            recorder = flexmock
            recorder.should_receive(:callback_without_error).with(nil).never
            recorder.should_receive(:callback_with_error).with(nil, Orocos::NotFound).once
            ns.get("bla") { |task| recorder.callback_without_error(task) }
            ns.get("bla") { |task,err| recorder.callback_with_error(task, err) }

            sleep 0.1
            Orocos::Async.step
        end

        def create_test_node
            Orocos.load_typekit 'base'
            task = new_ruby_task_context 'ros_test'
            port = task.create_input_port('out', '/base/Time')
            port.create_stream(Orocos::TRANSPORT_ROS, "/ros_test_in")
            task
        end

        it "should be able to resolve a task into a Async::ROS::Node synchronously" do 
            expected = create_test_node
            t = ns.get Orocos::ROS.caller_id
            assert_is_ros_node_proxy Orocos::ROS.caller_id, t
        end

        it "should be able to resolve a task into an Async::ROS::Node asynchronously" do
            expected = create_test_node
            t = nil
            ns.get(Orocos::ROS.caller_id) { |task| t = task }
            sleep 0.1
            Orocos::Async.step
            assert_is_ros_node_proxy Orocos::ROS.caller_id, t
        end

        def assert_is_ros_node_proxy(name, proxy)
            assert_kind_of Orocos::Async::ROS::Node, proxy
            assert proxy.valid_delegator?, "#{proxy} did not get resolved into a sync object"
            delegated_node = proxy.instance_variable_get(:@delegator_obj)
            assert_kind_of Orocos::ROS::Node, delegated_node
            assert_equal name, delegated_node.name
            assert_same ns.instance_variable_get(:@delegator_obj), delegated_node.name_service
        end
    end
end

