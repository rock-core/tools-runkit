# frozen_string_literal: true

require "orocos/test"
require "orocos/async"
require "orocos/ros/async"

describe Orocos::Async::ROS::NameService do
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
            ns.get("bla") { |task, err| recorder.callback_with_error(task, err) }

            Orocos::Async.steps
        end

        def create_test_node
            Orocos.load_typekit "base"
            task = new_ruby_task_context "ros_test"
            port = task.create_input_port("out", "/base/Time")
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
            Orocos::Async.steps
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

describe Orocos::ROS::OutputTopic do
    include Orocos::Spec

    attr_reader :name_service
    attr_reader :local_port

    before do
        @name_service = Orocos::ROS::NameService.new

        Orocos.load_typekit "base"
        task = new_ruby_task_context "ros_test"
        port = task.create_output_port("out", "/base/Time")
        port.publish_on_ros("/ros_test_out")
        @local_port = port
    end
    describe "access through the async API" do
        attr_reader :async_name_service, :node, :port
        before do
            node = name_service.get Orocos::ROS.caller_id
            port = node.output_port "/ros_test_out"
            @sync_reader = port.reader
            @node = node.to_async
            @port = port.to_async
        end

        it "should emit reachable" do
        end

        it "should emit the data event when new data is received" do
            recorder = flexmock
            expected_sample = port.new_sample
            expected_sample.microseconds = 1000
            recorder.should_receive(:received).once.with(expected_sample)
            port.on_data do |sample|
                recorder.received sample
            end
            Orocos::Async.steps
            local_port.write expected_sample
            # The first read_new is always nil. This is weird and is definitely
            # TODO
            sleep 0.2
            Orocos::Async.steps
        end
    end
end
