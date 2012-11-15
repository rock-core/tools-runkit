$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Async::TaskContext do
    include Orocos::Spec

    describe "initialize" do 
        before do 
            Orocos::Async.clear
        end

        it "should raise NotFound if remote task is not reachable and :raise is set to true" do
            t1 = Orocos::Async::TaskContext.new(:name => "bla",:raise => true)
            sleep 0.1
            assert_raises(Orocos::NotFound) do
                Orocos::Async.step
            end
            assert_raises(Orocos::NotFound) do
                t1.port_names
            end
        end

        it "should not raise NotFound if remote task is not reachable and :raise is set to false" do
            Orocos::Async::TaskContext.new(:name => "bla").must_be_kind_of Orocos::Async::TaskContext
            Orocos::Async.steps
        end

        it "should raise ArgumentError on wrong option" do
            assert_raises(ArgumentError) do
                Orocos::Async::TaskContext.new(:name2 => 'Bla_Blo')
            end
        end

        it "should raise ArgumentError if too many parameters" do
            assert_raises(ArgumentError) do
                Orocos::Async::TaskContext.new(12,212,:name2 => 'Bla_Blo')
            end
        end

        it "should raise ArgumentError if a name is given but no name service" do
            assert_raises(ArgumentError) do
                Orocos::Async::TaskContext.new(:name_service => nil,:name2 => 'Bla_Blo')
            end
        end

        it "should raise ArgumentError if no name and ior is given" do
            assert_raises(ArgumentError) do
                Orocos::Async::TaskContext.new()
            end
        end

        it "can be initialized from name" do
            Orocos.run('process') do
                t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
                assert t1.reachable? 
                Orocos::Async.steps
            end
        end

        it "can be initialized from ior" do
            Orocos.run('process') do
                ior = Orocos.name_service.ior('process_Test')
                t1 = Orocos::Async::TaskContext.new(:ior => ior)
                assert t1.reachable? 
                t1 = Orocos::Async::TaskContext.new(ior)
                assert t1.reachable?
                Orocos::Async.steps
            end
        end

        it "can be initialized from Orocos::TaskContext" do
            Orocos.run('process') do
                t1 = Orocos.name_service.get "process_Test"
                t2 = Orocos::Async::TaskContext.new(t1)
                assert t2.reachable? 
                t2 = Orocos::Async::TaskContext.new(:task => t1)
                assert t2.reachable?
                Orocos::Async.steps
            end
        end

        it "can be initialized from Orocos::Async::TaskContext" do
            Orocos.run('process') do
                t1 = Orocos::Async::TaskContext.new(:name => "process_Test")
                assert t1.reachable?
                t2 = Orocos::Async::TaskContext.new(:task => t1)
                assert t2.reachable?
                Orocos::Async.steps
            end
        end

        it 'should have the instance methods from Orocos::TaskContext' do 
            methods = Orocos::Async::TaskContext.instance_methods
            Orocos::TaskContext.instance_methods.each do |method|
                methods.include?(method).wont_be_nil
            end
        end
    end

    describe "Async access" do 
        it "should automatically (re)connect to the remote task when reachable" do
            t1 = Orocos::Async::TaskContext.new(:name => 'process_Test',:watchdog => false)
            assert !t1.reachable?
            Orocos.run('process') do
                assert t1.reachable?
            end
            assert !t1.reachable?
            Orocos.run('process') do
                assert t1.reachable?
            end
        end

        it "should ignore all calls to the remote task if not reachable" do
            t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
            t1.reachable?.must_equal false
            t1.has_port?("bla").must_equal false
            t1.has_attribute?("bla").must_equal false
            t1.has_property?("bla").must_equal false
            t1.has_operation?("bla").must_equal false
            t1.port_names.must_equal []
            t1.attribute_names.must_equal []
            t1.property_names.must_equal []
            t1.rtt_state.must_equal nil
            t1.attribute_names do |names,e|
                e.must_be_instance_of Orocos::NotFound
                names.must_equal []
            end
            sleep 0.1
            Orocos::Async.step
        end

        it "should call on_connect and on_disconnect" do
            t1 = Orocos::Async::TaskContext.new(:name => 'process_Test',:period => 0.1)
            assert !t1.reachable?
            connect = nil
            disconnect = nil
            t1.on_connected do 
                connect = true
            end
            t1.on_disconnected do 
                disconnect = true
            end
            Orocos.run('process') do
                sleep 0.11
                Orocos::Async.step
            end
            sleep 0.11
            Orocos::Async.step
            assert connect
            assert disconnect
        end

        it "should call on_error" do
            t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
            error = nil
            t1.on_error Exception do |e|
                error = e
            end
            t1.port_names do 
            end
            sleep 0.1
            Orocos::Async.step
            assert_equal Orocos::NotFound, error.class
        end

        it "should call disconnect for any call which raises an error" do
            t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
            Orocos.run('process') do
                assert t1.reachable?
                assert t1.instance_variable_get(:@__task_context)
                Orocos::Async.step
            end
            
            t1.port_names do 
            end
            sleep 0.1
            Orocos::Async.step
            assert !t1.instance_variable_get(:@__task_context)
        end

        it "should read the remote port names " do
            Orocos.run('process') do
                t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
                val = t1.port_names # sync call
                val2 = nil
                assert val
                # async call
                t1.port_names do |names,e|
                    puts e
                    val2 = names
                end
                sleep 0.1
                Orocos::Async.steps
                assert_equal val,val2
            end
        end

        it "should run in parallel" do
            Orocos.run('process') do
                t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
                q = Queue.new
                0.upto 19 do 
                    t1.reachable? do |val|
                        sleep 0.15 # this will ensure that no thread can run twice
                        q << val
                    end
                end
                sleep 0.2
                Orocos::Async.step
                assert_equal 20,q.size
            end
        end

        it "not should run in paralleli because the methods are not thread safe" do
            Orocos.run('process') do
                t1 = Orocos::Async::TaskContext.new(:name => 'process_Test')
                q = Queue.new
                0.upto 9 do 
                    t1.model do |val|
                        sleep 0.1 # this will ensure that no thread can run twice
                        q << val
                    end
                end
                time = Time.now
                Orocos::Async.steps
                assert_equal 10,q.size
                assert Time.now-time >= 1.0
            end
        end
    end
end
