$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::Port do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should check equality based on CORBA reference" do
        start_processes('simple_source') do |source|
            source = source.task("source")
            p1 = source.port("cycle")
            # Remove p1 from source's port cache
            source.instance_variable_get("@ports").delete("cycle")
            p2 = source.port("cycle")
            refute_equal(p1.object_id, p2.object_id)
            assert_equal(p1, p2)
        end
    end
end

describe Orocos::OutputPort do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should be able to connect to an input" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            assert(!sink.connected?)
            assert(!source.connected?)
            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
        end
    end

    it "should be able to disconnect from a particular input" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            source.disconnect_from sink
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "should be able to disconnect from all its InputPort" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            source.disconnect_all
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "should refuse connecting to another OutputPort" do
        start_processes('simple_source') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")

            assert(!source.connected?)
            assert_raises(ArgumentError) { source.connect_to source }
        end
    end
end

describe Orocos::InputPort do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should be able to disconnect from a particular output" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            sink.disconnect_from source
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "should be able to disconnect from all connected outputs" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            sink.disconnect_all
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "should refuse connecting to another input" do
        start_processes('simple_source') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")

            assert(!source.connected?)
            assert_raises(ArgumentError) { source.connect_to source }
        end
    end
end

