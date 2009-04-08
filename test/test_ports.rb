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
            p2 = source.port("cycle")
            refute_equal(p1.object_id, p2.object_id)
            assert_equal(p1, p2)
        end
    end
end

