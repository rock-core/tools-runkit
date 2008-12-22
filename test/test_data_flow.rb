require 'test/unit'
require 'orocos'
require 'orocos/test'

class TC_Process < Test::Unit::TestCase
    TEST_DIR   = File.dirname(__FILE__)
    DATA_DIR   = File.join(TEST_DIR, 'data')
    PREFIX_DIR = File.join(DATA_DIR, 'prefix')

    include Orocos::Test

    def test_port
        generate_and_build File.join(DATA_DIR, 'simple_source', 'simple_source.orogen'), PREFIX_DIR
        task = spawn_and_get "simple_source", "source"

        assert(port = task.port('cycle'))
        assert_equal('cycle', port.name)
        assert_equal(task, port.task)
        assert_equal("int", port.typename)
    end

    def test_connect
        generate_and_build File.join(DATA_DIR, 'simple_source', 'simple_source.orogen'), PREFIX_DIR
        generate_and_build File.join(DATA_DIR, 'simple_sink', 'simple_sink.orogen'), PREFIX_DIR
        src_task = spawn_and_get "simple_source", "source"
        dst_task = spawn_and_get "simple_sink", "sink"

        dst_port = dst_task.port('cycle')
        src_port = src_task.port('cycle')

        src_port.connect dst_port
        assert(src_port.connected?)
        assert(dst_port.connected?)
        src_port.disconnect
        dst_port.disconnect # TODO: horrible behaviour to be removed later on
        assert(!src_port.connected?)
        assert(!dst_port.connected?)

        # dst_port.connect src_port
        # assert(src_port.connected?)
        # assert(dst_port.connected?)
        # dst_port.disconnect
        # assert(!src_port.connected?)
        # assert(!dst_port.connected?)
    end
end

