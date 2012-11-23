
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Async::TaskContextProxy do
    include Orocos::Spec

    describe "initialize" do 
        before do 
            Orocos::Async.clear
        end

        it "should raise Orocos::NotFound if remote task is unreachable and :raise is set to true" do
            t1 = Orocos::Async::TaskContextProxy.new("bla",:raise => true)
            Orocos::Async.step
            sleep 0.1
            assert_raises(Orocos::NotFound) do
                Orocos::Async.step
                Orocos::Async.step
            end
            assert !t1.reachable?
        end

        it "should not raise NotFound if remote task is unreachable and :raise is set to false" do
            t1 = Orocos::Async::TaskContextProxy.new("bla")
            sleep 0.2
            Orocos::Async.step
            assert !t1.reachable?
        end

        it "shortcut must return TaskContexProxy" do
            t1 = Orocos::Async.get_proxy("process_Test",:retry_period => 0.1,:period => 0.1)
            t1.must_be_instance_of Orocos::Async::TaskContextProxy
        end

        it "should connect to a remote task when reachable" do
            t1 = Orocos::Async.get_proxy("process_Test",:retry_period => 0.1,:period => 0.1)

            disconnects = 0
            connects = 0
            reconnects = 0
            connectings = 0

            t1.on_connected do 
                connects += 1
            end
            t1.on_disconnected do 
                disconnects += 1
            end
            t1.on_reconnected do 
                reconnects += 1
            end

            Orocos.run('process') do
                sleep 0.11
                Orocos::Async.step # queue reconnect
                sleep 0.11
                Orocos::Async.step # add reconnect task to thread pool
                sleep 0.11
                Orocos::Async.step # process callback
                assert t1.reachable?
            end
            assert !t1.reachable?
            assert_equal 1, connects 
            assert_equal 1, disconnects
            assert_equal 0, reconnects

            Orocos.run('process') do
                sleep 0.11
                Orocos::Async.step # queue reconnect
                sleep 0.11
                Orocos::Async.step # add reconnect task to thread pool
                sleep 0.11
                Orocos::Async.step # process callback
                assert t1.reachable?
            end
            assert !t1.reachable?
            assert_equal 2, connects
            assert_equal 2, disconnects
            assert_equal 1, reconnects
        end
    end
end

