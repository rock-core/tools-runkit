$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Async::ObjectBase do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    describe "when subclassed" do 
        before do 
            Orocos::Async.clear
        end

        class TestObject < Orocos::Async::ObjectBase
            define_event :test

            def initialize(name)
                super(name,Orocos::Async.event_loop)
            end
        end

        it "should define on and emit functions on the class" do 
            assert TestObject.instance_methods.include?(:on_test)
            assert TestObject.instance_methods.include?(:emit_test)
            assert TestObject.instance_methods.include?(:on_error)
            assert TestObject.instance_methods.include?(:emit_error)
        end

        describe "method event" do 
            it "should raise if event is unknown" do
                obj = TestObject.new("name")
                assert_raises RuntimeError do 
                    obj.event(:bla)
                end
            end

            it "should not raise if is known" do
                obj = TestObject.new("name")
                obj.event(:error)
            end

            it "should call registered code block" do
                obj = TestObject.new("name")
                called = false
                obj.on_error do |val|
                    called = val
                end
                obj.event(:error,123)
                Orocos::Async.step
                assert_equal 123,called
            end

            it "should call the listener with the last value" do
                obj = TestObject.new("name")
                called = false
                obj.on_unreachable do
                    called = true
                end
                Orocos::Async.step
                assert_equal true,called
            end

            it "should not call the listener with the last value" do
                obj = TestObject.new("name")
                called = false
                obj.on_unreachable(false) do
                    called = true
                end
                Orocos::Async.step
                assert_equal false,called
            end
        end

        describe "method on_event" do 
            it "should raise if event is unknown" do
                obj = TestObject.new("name")
                assert_raises RuntimeError do 
                    obj.on_event :bla do
                    end
                end
            end
        end

        describe "method number_of_listeners" do 
            it "should raise if event is unknown" do
                obj = TestObject.new("name")
                assert_raises RuntimeError do 
                    obj.number_of_listeners :bla
                end
            end
            it "should return the number of listener" do
                obj = TestObject.new("name")
                assert_equal 0, obj.number_of_listeners(:reachable)
                obj.on_event(:reachable) {}
                assert_equal 1, obj.number_of_listeners(:reachable)
                obj.on_event(:reachable) {}
                assert_equal 2, obj.number_of_listeners(:reachable)
            end
        end

        describe "method validate_event" do 
            it "should raise if event is unknown" do
                obj = TestObject.new("name")
                assert_raises RuntimeError do 
                    obj.validate_event :bla
                end
            end
            it "should not raise if event is known" do
                obj = TestObject.new("name")
                obj.validate_event :error
            end
        end

        describe "method valid_event?" do 
            it "should return false for an unknown event" do
                obj = TestObject.new("name")
                assert !obj.valid_event?(:bla)
            end
            it "should return true for a known event" do
                obj = TestObject.new("name")
                assert obj.valid_event?(:error)
            end
        end

        describe "method listener?" do 
            it "should return false for a listener which is not active" do
                obj = TestObject.new("name")
                listener = Orocos::Async::EventListener.new(obj,:error)
                assert !obj.listener?(listener)
            end
            it "should return true for a active listner" do
                obj = TestObject.new("name")
                l = obj.on_error do 
                end
                assert obj.listener? l
            end
        end

        describe "method remove_listener" do 
            it "should remove a listner" do
                obj = TestObject.new("name")
                l = obj.on_error do 
                end
                assert obj.listener? l
                obj.remove_listener l
                assert !obj.listener?(l)
            end
        end

        describe "method proxy_event" do 
            it "should set up a listner which is proxying events" do
                obj = TestObject.new("name")
                assert_equal 0, obj.number_of_listeners(:reachable)

                obj2 = TestObject.new("name")
                obj2.proxy_event(obj,:reachable)
                #should be still 0 because no listener is registered to obj2
                assert_equal 0, obj.number_of_listeners(:reachable)

                called = nil
                l = obj2.on_reachable do |val|
                    called = val
                end
                assert_equal 1, obj.number_of_listeners(:reachable)
                assert_equal 1, obj2.number_of_listeners(:reachable)

                obj.event :reachable,222
                Orocos::Async.step
                assert_equal 222,called

                #this should also remove the listener from obj 
                l.stop
                assert_equal 0, obj.number_of_listeners(:reachable)
                assert_equal 0, obj2.number_of_listeners(:reachable)
            end
        end
    end
end

