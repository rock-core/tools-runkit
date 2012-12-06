$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Async::PortProxy do 
    include Orocos::Spec
    before do 
        Orocos::Async.clear
    end

    describe "when not connected" do 
        it "should be an input and output port at the same time because the exact type is unknown" do 
            t1 = Orocos::Async.proxy("process_Test")
            p = t1.port("test")
            assert p.input?
            assert p.output?
        end

        it "should raise Orocos::NotFound if some one is accessing the type name of a port which is not yet known" do 
            t1 = Orocos::Async.proxy("simple_source_source")
            p = t1.port("cycle")
            assert_raises Orocos::NotFound do 
                p.type_name
            end
        end

        it "should return a sub port for a given subfield" do
            t1 = Orocos::Async.proxy("simple_source_source")
            p = t1.port("cycle")
            sub_port = p.sub_port(:frame)
            sub_port.must_be_instance_of Orocos::Async::PortProxy
            sub_port = p.sub_port([:frame,:size])
            sub_port.must_be_instance_of Orocos::Async::PortProxy
        end
    end

    describe "when connected" do 
        it "should raise RuntimeError if an operation is performed which is not available for this port type" do
            Orocos.run('simple_sink') do
                t1 = Orocos::Async.proxy("simple_sink_sink")
                p = t1.port("cycle",:wait => true)
                assert_raises RuntimeError do
                    p.period = 1
                end
                assert_raises RuntimeError do
                    p.on_data do
                    end
                end
            end
        end

        it "should return the type name of the port if known or connected" do 
            t1 = Orocos::Async.proxy("simple_source_source",:retry_period => 0.08,:period => 0.1)
            p = t1.port("cycle2",:type => Fixnum)
            assert_equal "Fixnum",p.type_name

            p2 = t1.port("cycle")
            Orocos.run('simple_source') do
                sleep 0.1
                Orocos::Async.step
                sleep 0.1
                Orocos::Async.step
                sleep 0.1
                Orocos::Async.step
                assert_equal "Fixnum",p.type_name
            end
        end

        it "should raise RuntimeError if the given type name differes from the real one" do
            Orocos.run('simple_sink') do
                t1 = Orocos::Async.proxy("simple_sink_sink")
                assert_raises RuntimeError do
                    p = t1.port("cycle",:type => Float,:wait => true)
                end
            end
        end

    end
end

describe Orocos::Async::SubPortProxy do 
    include Orocos::Spec
    before do 
        Orocos::Async.clear
    end

    describe "when not connected" do
        it "should return the given sub type" do
            t1 = Orocos::Async.proxy("simple_source_source")
            p = t1.port("cycle")
            sub_port = p.sub_port(:frame,Orocos.registry.get("/int32_t"))
            assert_equal Orocos.registry.get("/int32_t"),sub_port.type
            assert_equal "/int32_t",sub_port.type_name
        end

        it "should raise if the type is accessed but not given" do 
            t1 = Orocos::Async.proxy("simple_source_source")
            p = t1.port("cycle")
            sub_port = p.sub_port(:frame)
            assert_raises Orocos::NotFound do 
                sub_port.type
            end
        end
    end

    describe "when connected" do
        it "should return the given sub type" do
            t1 = Orocos::Async.proxy("simple_source_source")
            Orocos.run('simple_source') do
                p = t1.port("cycle_struct",:wait => true)
                sub_port = p.sub_port(:value)
                assert_equal Orocos.registry.get("/int32_t"),sub_port.type
                assert_equal "/int32_t",sub_port.type_name
            end
        end

        it "should raise RuntimeError if the given sub type differs from the real one" do
            t1 = Orocos::Async.proxy("simple_source_source")
            Orocos.run('simple_source') do
                p = t1.port("cycle_struct",:wait => true)
                t1.configure
                t1.start
                sub_port = p.sub_port(:value,Orocos.registry.get("/double"))
                assert_raises RuntimeError do
                    sub_port.on_data do |sample|
                    end
                    Orocos::Async.step
                    sleep 0.1
                    Orocos::Async.step
                    sleep 0.1
                    Orocos::Async.step
                end
            end
        end

        it "should call the code block with the sub sample" do
            t1 = Orocos::Async.proxy("simple_source_source")
            Orocos.run('simple_source') do
                p = t1.port("cycle_struct",:wait => true)
                t1.configure
                t1.start
                sub_port = p.sub_port(:value)
                data = nil
                sub_port.on_data do |sample|
                    data = sample
                end
                Orocos::Async.step
                sleep 0.1
                Orocos::Async.step
                sleep 0.1
                Orocos::Async.step
                data.must_be_instance_of Fixnum
            end
        end
    end
end

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
            t1 = Orocos::Async.proxy("process_Test",:retry_period => 0.08,:period => 0.1)

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


        it "should block until the task is reachable if wait option is given" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async.proxy("simple_source_source",:wait => true)
                assert t1.reachable?
            end
        end

        it "should connect its port when reachable" do
            t1 = Orocos::Async.proxy("simple_source_source",:retry_period => 0.08,:period => 0.1)
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

