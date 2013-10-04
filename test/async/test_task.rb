$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", '..', "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

MiniTest::Unit.autorun

# helper for generating an ior from a name
def ior(name)
    Orocos.name_service.ior(name)
rescue Orocos::NotFound => e
    "IOR:010000001f00000049444c3a5254542f636f7262612f435461736b436f6e746578743a312e300000010000000000000064000000010102000d00000031302e3235302e332e31363000002bc80e000000fe8a95a65000004d25000000000000000200000000000000080000000100000000545441010000001c00000001000000010001000100000001000105090101000100000009010100"
end

describe Orocos::Async::CORBA::TaskContext do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    describe "initialize" do 
        before do 
            Orocos::Async.clear
        end

        it "should raise ComError if remote task is not reachable and :raise is set to true" do
            t1 = Orocos::Async::CORBA::TaskContext.new(:ior => ior("bla"),:raise => true)
            sleep 0.1
            assert_raises(Orocos::CORBA::ComError) do
                Orocos::Async.step
            end
        end

        it "should not raise NotFound if remote task is not reachable and :raise is set to false" do
            Orocos::Async::CORBA::TaskContext.new(:ior => ior("bla")).must_be_kind_of Orocos::Async::CORBA::TaskContext
            Orocos::Async.steps
        end

        it "should raise ArgumentError on wrong option" do
            assert_raises(ArgumentError) do
                Orocos::Async::CORBA::TaskContext.new(:ior2 => "")
            end
        end

        it "should raise ArgumentError if too many parameters" do
            assert_raises(ArgumentError) do
                Orocos::Async::CORBA::TaskContext.new(12,212,:ior => ior('Bla_Blo'))
            end
        end

        it "should raise ArgumentError if no ior is given" do
            assert_raises(ArgumentError) do
                Orocos::Async::CORBA::TaskContext.new()
            end
        end

        it "can be initialized from ior" do
            Orocos.run('process') do
                ior = Orocos.name_service.ior('process_Test')
                t1 = Orocos::Async::CORBA::TaskContext.new(:ior => ior)
                assert t1.reachable?
                t1 = Orocos::Async::CORBA::TaskContext.new(ior)
                assert t1.reachable?
                Orocos::Async.steps
            end
        end

        it "can be initialized from Orocos::TaskContext" do
            Orocos.run('process') do
                t1 = Orocos.name_service.get "process_Test"
                t2 = Orocos::Async::CORBA::TaskContext.new(t1)
                assert t2.reachable?
                t2 = Orocos::Async::CORBA::TaskContext.new(:use => t1)
                assert t2.reachable?
                Orocos::Async.steps
            end
        end

        it "can be initialized from Orocos::Async::CORBA::TaskContext" do
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(:ior => ior("process_Test"))
                assert t1.reachable?
                t2 = Orocos::Async::CORBA::TaskContext.new(t1)
                assert t2.reachable?
                Orocos::Async.steps
            end
        end

        it 'should have the instance methods from Orocos::TaskContext' do 
            methods = Orocos::Async::CORBA::TaskContext.instance_methods
            Orocos::TaskContext.instance_methods.each do |method|
                methods.include?(method).wont_be_nil
            end
        end
    end

    describe "Async access" do 
        it "should raise on all synchronous calls to the remote task if not reachable" do
            t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
            t1.reachable?.must_equal false # only function that should never raise

            assert_raises Orocos::CORBA::ComError do
                t1.has_port?("bla").must_equal false
            end
            assert_raises Orocos::CORBA::ComError do 
                t1.has_attribute?("bla").must_equal false
            end
            t1.attribute_names do |names,e|
                e.must_be_instance_of Orocos::CORBA::ComError
                names.must_equal nil
            end
            sleep 0.1
            Orocos::Async.step
        end

        it "should call on_reachable and on_unreachable if watchdog is on" do
            connect = nil
            disconnect = nil
            t1 = nil
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'),:period => 0.1,:watchdog => true)
                t1.on_reachable do 
                    connect = true
                end
                t1.on_unreachable do 
                    disconnect = true
                end
            end
            sleep 0.11
            Orocos::Async.step # here we queue the next task for checking
            sleep 0.11
            Orocos::Async.step # here we find out that the task is not reachable
            sleep 0.11
            Orocos::Async.step # here we find out that the task is not reachable
            assert connect
            assert disconnect
        end

        it "should call on_port_reachable" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'),:period => 0.1,:watchdog => true)
                ports = []
                t1.on_port_reachable do |name|
                    ports << name
                end
                t1.wait(0.2)
                Orocos::Async.step
                Orocos::Async.step
                assert_equal ["cycle", "cycle_struct", "out0", "out1", "out2", "out3", "state"],ports.sort
                ports.clear
               
                #should be called even if the task is already reachable
                t1.on_port_reachable do |name|
                    ports << name
                end
                Orocos::Async.step
                assert_equal ["cycle", "cycle_struct", "out0", "out1", "out2", "out3", "state"],ports.sort
            end
        end


        it "should call on_port_unreachable" do 
            t1 = nil
            ports = []
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'),:period => 0.1,:watchdog => true)
                t1.on_port_unreachable do |name|
                    ports << name
                end
                t1.wait(1.0)
                Orocos::Async.step
            end
            assert_raises Orocos::NotFound do
                t1.wait 0.11
            end
            Orocos::Async.step
            assert_equal ["cycle", "cycle_struct", "out0", "out1", "out2", "out3", "state"],ports.sort
        end

        it "should call on_property_reachable" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'),:period => 0.1,:watchdog => true)
                properties = []
                t1.on_property_reachable do |name|
                    properties << name
                end
                t1.wait(0.2)
                Orocos::Async.steps
                assert_equal ["dynamic_prop","prop1", "prop2", "prop3"],properties
                properties.clear

                #should be called even if the task is already reachable
                t1.on_property_reachable do |name|
                    properties << name
                end

                Orocos::Async.steps
                assert_equal ["dynamic_prop","prop1", "prop2", "prop3"],properties
            end
        end

        it "should call on_port_reachable if a port was dynamically added" do 
            task = Orocos::RubyTaskContext.new("test")
            t1 = Orocos::Async::CORBA::TaskContext.new(ior('test'),:period => 0.1,:watchdog => true)
            ports = []
            t1.on_port_reachable do |name|
                ports << name
            end
            assert_equal [],ports
            t1.wait(0.2)

            port = task.create_output_port("frame","string")
            port = task.create_output_port("frame2","string")

            sleep 0.1
            Orocos::Async.steps
            sleep 0.1
            Orocos::Async.steps
            assert_equal ["frame","frame2"], ports
        end

        it "should call on_port_unreachable if a port was dynamically removed" do 
            task = Orocos::RubyTaskContext.new("test")
            t1 = Orocos::Async::CORBA::TaskContext.new(ior('test'),:period => 0.1,:watchdog => true)
            port = task.create_output_port("frame","string")

            ports = []
            t1.on_port_unreachable do |name|
                ports << name
            end
            t1.wait(1.0)
            Orocos::Async.step
            task.remove_port(port)
            Orocos::Async.step
            sleep 0.11
            Orocos::Async.step
            sleep 0.11
            Orocos::Async.steps
            assert_equal ["frame"], ports
        end
        
        it "should call on_error" do
            t1 = nil
            error = nil
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                t1.on_error do |e|
                    error = e
                end
            end
            t1.port_names do
            end
            sleep 0.1
            Orocos::Async.steps
            assert_equal Orocos::CORBA::ComError, error.class
        end

        it "should call on_state_change" do
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'),:period => 0.1,:wait => true)
                state = nil
                t1.on_state_change do |val|
                    state = val
                end
                sleep 0.11
                Orocos::Async.step
                assert_equal :RUNNING, state
                t1.stop
                sleep 0.2
                Orocos::Async.step
                sleep 0.2
                Orocos::Async.step
                assert_equal :STOPPED, state
            end
        end

        it "should call disconnect for any call which raises an error" do
            t1 = Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                assert t1.reachable?
                assert t1.valid_delegator?
                Orocos::Async.step
                t1
            end
            t1.port_names do 
            end
            sleep 0.1
            Orocos::Async.steps
            assert !t1.valid_delegator?
        end

        it "should read the remote port names " do
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
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

        it "should return its ports" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                names = t1.port_names
                assert_equal 7,names.size
                names.each do |name|
                    p = t1.port(name)
                    p.must_be_kind_of Orocos::Async::CORBA::OutputPort
                    assert p.reachable?
                end
            end
        end

        it "should asynchronously return its ports" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                queue = Queue.new
                names = t1.port_names
                names.each do |name|
                    t1.port name do |port|
                        queue << port
                    end
                end
                sleep 0.1
                Orocos::Async.step
                assert_equal 7, queue.size
                while !queue.empty?
                    p = queue.pop
                    p.must_be_kind_of Orocos::Async::CORBA::OutputPort
                    assert p.reachable?
                end
            end
        end

        it "should run in parallel" do
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
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

        it "should not run in parallel because the methods are not thread safe" do
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                q = Queue.new
                0.upto 9 do 
                    t1.model do |val|
                        sleep 0.1 # this will ensure that no thread can run twice
                        q << val
                    end
                end
                time = Time.now
                Orocos::Async.steps
                sleep 0.12
                assert_equal 10,q.size
                assert Time.now-time >= 1.0
            end
        end

        it "should be generated from a task context" do
            Orocos.run('process') do
                t1 = Orocos.get "process_Test"
                t1 = t1.to_async
                t1.wait
                assert t1.reachable?
            end
        end
    end
end
