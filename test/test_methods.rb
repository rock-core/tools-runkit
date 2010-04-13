$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::RTTMethod do
    include Orocos::Spec

    it "should not be possible to create one directly" do
        assert_raises(NoMethodError) { Orocos::RTTMethod.new }
    end

    it "should be possible to call a method with arguments" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start

            port_reader = echo.port('output').reader

            m = echo.rtt_method 'write'
            assert_equal(10, m.call(10))
            assert(10, port_reader.read)
        end
    end

    it "should be possible to reuse a method object with different arguments" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start

            port_reader = echo.port('output').reader

            m = echo.rtt_method 'write'
            m.call(10)
            assert_equal(10, m.recall)
            m.call(11)
            assert_equal(11, m.recall)
        end
    end

    it "should be possible to use a shortcut" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start
            assert_equal(10, echo.write(10))
        end
    end

    it "should be possible to recall an already called method" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start

            port_reader = echo.port('output').reader

            m = echo.rtt_method 'write'
            m.call(10)
            assert_equal(10, m.recall)
        end
    end

    it "should be possible to have mutliple RTTMethod instances referring to the same remote method" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start

            port_reader = echo.port('output').reader

            m = echo.rtt_method 'write'
            m.call(10)
            assert(10, port_reader.read)
            m2 = echo.rtt_method 'write'
            m2.call(11)
            assert(11, port_reader.read)
            m.recall
            assert(10, port_reader.read)
        end
    end
end
