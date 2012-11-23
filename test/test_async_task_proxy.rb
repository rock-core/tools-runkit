
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
    before do 
        Orocos::Async.clear
    end

    describe "initialize" do 
        before do 
            begin
                sleep 0.1
                Orocos::Async.step
            rescue
            ensure
                Orocos::Async.clear
            end
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
            t1 = Orocos::Async.proxy("process_Test",:retry_period => 0.1,:period => 0.1)
            t1.must_be_instance_of Orocos::Async::TaskContextProxy
        end

        it "should return a port proxy" do 
            t1 = Orocos::Async.proxy("process_Test",:retry_period => 0.1,:period => 0.1)
            p = t1.port("test")
            p.must_be_instance_of Orocos::Async::PortProxy
        end

        it "should connect to a remote task when reachable" do
            t1 = Orocos::Async.proxy("process_Test",:retry_period => 0.1,:period => 0.1)

            disconnects = 0
            connects = 0

            t1.on_reachable do 
                connects += 1
            end
            t1.on_unreachable do 
                disconnects += 1
            end

            Orocos.run('process') do
                sleep 0.11
                Orocos::Async.step # queue reconnect
                sleep 0.11
                Orocos::Async.step # add reconnect task to thread pool
                sleep 0.11
                Orocos::Async.step # process callback
                assert t1.reachable?
                t1.instance_variable_get(:@task_context).must_be_instance_of Orocos::Async::CORBA::TaskContext
            end
            assert !t1.reachable?
            assert_equal 1, connects
            assert_equal 1, disconnects

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
        end

        it "should connect its port when reachable" do
            t1 = Orocos::Async.proxy("simple_source_source",:retry_period => 0.1,:period => 0.1)
            p = t1.port("cycle")

            data = []
            p.on_data do |d|
                data << d
            end
            #test reconnect logic
            0.upto(2) do 
                Orocos.run('simple_source') do
                    sleep 0.1
                    Orocos::Async.step
                    sleep 0.1
                    Orocos::Async.step
                    sleep 0.1
                    Orocos::Async.step
                    t1.configure
                    t1.start
                    0.upto(10) do 
                        Orocos::Async.step
                        sleep 0.05
                    end
                end
                sleep 0.2
                Orocos::Async.step
                assert !data.empty?
                data.each_with_index do |d,i|
                    assert_equal i+1,d
                end
                data.clear
            end
        end
    end
end

