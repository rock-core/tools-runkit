$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::TaskContext do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should check equality based on CORBA reference" do
        start_processes('process') do |process|
            assert(t1 = Orocos::TaskContext.get('process_Test'))
            assert(t2 = Orocos::TaskContext.get('process_Test'))
            refute_equal(t1.object_id, t2.object_id)
            assert_equal(t1, t2)
        end
    end

    it "should allow enumerating its ports" do
        start_processes('simple_source', 'simple_sink') do |source, sink|
            source = source.task("source")
            sink   = sink.task("sink")

            source.enum_for(:each_port).to_a.must_equal [source.port("cycle")]
            sink.enum_for(:each_port).to_a.must_equal [sink.port("cycle")]
        end
    end

    it "should allow getting its ports" do
        start_processes('simple_source', 'simple_sink') do |source, sink|
            source = source.task("source")
            sink   = sink.task("sink")

            assert(source_p = source.port('cycle'))
            source_p.must_be_kind_of(Orocos::OutputPort)
            source_p.name.must_equal("cycle")
            source_p.task.must_equal(source)
            source_p.type_name.must_equal("int")

            assert(sink_p   = sink.port('cycle'))
            sink_p.must_be_kind_of(Orocos::InputPort)
            sink_p.name.must_equal("cycle")
            sink_p.task.must_equal(sink)
            sink_p.type_name.must_equal("int")
        end
    end

    it "should raise NotFound if a port does not exist" do
        start_processes('simple_source', 'simple_sink') do |source, sink|
            assert_raises(Orocos::NotFound) { source.task("source").port("does_not_exist") }
        end
    end

    it "should be able to manipulate the task state machine and read its state" do
        start_processes('simple_source') do |source|
            source = source.task("source")
            assert_equal(Orocos::TaskContext::STATE_PRE_OPERATIONAL, source.state)
            assert(!source.start)
            assert(!source.ready?)
            assert(!source.running?)

            assert(source.configure)
            assert_equal(Orocos::TaskContext::STATE_STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)

            assert(source.start)
            assert_equal(Orocos::TaskContext::STATE_RUNNING, source.state)
            assert(source.ready?)
            assert(source.running?)

            assert(source.stop)
            assert_equal(Orocos::TaskContext::STATE_STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)
        end
    end
end

