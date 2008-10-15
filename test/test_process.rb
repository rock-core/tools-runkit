require 'test/unit'
require 'orocos'
require 'orocos/test'

class TC_Process < Test::Unit::TestCase
    TEST_DIR   = File.dirname(__FILE__)
    DATA_DIR   = File.join(TEST_DIR, 'data')
    PREFIX_DIR = File.join(DATA_DIR, 'prefix')

    include Orocos::Test

    def test_spawn
        generate_and_build File.join(DATA_DIR, 'process', 'process.orogen'), PREFIX_DIR

        process = Orocos::Process.new 'process'
        process.spawn
        process.wait_running

        assert(process.alive?)
        # We should now be able to get a reference on the TaskContext instances
        task = Orocos::TaskContext.get 'process.Test'

        process.kill
        assert(!process.alive?)

    ensure
        process.kill if process && process.alive?
    end
end
