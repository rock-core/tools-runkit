$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::Command do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should not be possible to create one directly" do
        assert_raises(NoMethodError) { Orocos::Command.new }
    end

    def common_setup
        start_processes 'echo' do |echo|
            echo = echo.task 'Echo'
            echo.start
            reader = echo.port('output').reader
            writer = echo.port('input').writer
            command = echo.command 'AsyncWrite'

            begin
                yield(command, reader, writer)
            ensure
                if !command.done?
                    writer.write(42)
                    sleep(0.1)
                end
            end
        end
    end
    def assert_command_advanced(reader, old)
        new = reader.read
        assert old < new, "expected the write value to advance, but got old=#{old} and new=#{new}"
        new
    end

    it "should be possible to call it with arguments" do
        common_setup do |c, reader, writer|
            c.call(10, 42)
            sleep 0.1; v = reader.read
            sleep 0.1; v = assert_command_advanced(reader, v)
            writer.write(42)
            sleep 0.1; v = reader.read
            sleep 0.1; assert(v == reader.read)
        end
    end

    it "should be possible to track its status (valid call)" do
        common_setup do |c, reader, writer|
            assert c.ready?
            assert !c.sent?
            assert_same nil, c.accepted?
            assert !c.executed?
            assert_same nil, c.valid?
            assert !c.done?
            c.call(10, 42)

            assert !c.ready?
            assert c.sent?
            # Can't know for executed and valid
            assert !c.done?

            sleep 0.1
            assert !c.ready?
            assert c.sent?
            assert_same true, c.accepted?
            assert c.executed?
            assert_same true, c.valid?
            assert !c.done?

            writer.write(42)
            sleep(0.1)
            assert(10, reader.read)
            assert !c.ready?
            assert c.sent?
            assert c.accepted?
            assert c.executed?
            assert_same true, c.valid?
            assert c.done?

            assert c.successful?
            assert !c.failed?
        end
    end

    it "should be possible to track its status (non-running processor)" do
        start_processes 'echo' do |echo|
            echo = echo.task 'Echo'
            c = echo.command 'AsyncWrite'
            c.call(10, 42)

            assert !c.ready?
            assert c.sent?
            assert !c.accepted?
        end
    end

    it "should be possible to track its status (invalid call)" do
        common_setup do |c, reader, writer|
            c.call(0, 42)

            sleep 0.1
            assert !c.ready?
            assert c.sent?
            assert c.accepted?
            assert c.executed?
            assert_same false, c.valid?
            assert c.finished?
            assert c.failed?
        end
    end

    Command = Orocos::Command
    StateError = Orocos::Command::StateError;
    it "should raise StateError if called on a non-ready state (valid call)" do
        common_setup do |c, reader, writer|
            c.call(10, 42)
            assert_raises(StateError) { c.call(10, 42) }
            sleep 0.1
            assert_raises(StateError) { c.call(10, 42) }
            writer.write(42)
            sleep(0.1)
            assert_same true, c.valid?
            assert(c.done?, "command was expected to be in DONE state (#{Command::STATE_DONE}), but is in state #{c.state}")
            assert_raises(StateError) { c.call(10, 42) }
        end
    end

    it "should raise StateError if called on a non-ready state (invalid call)" do
        common_setup do |c, reader, writer|
            c.call(0, 42)
            sleep 0.1
            assert_same false, c.valid?
            assert c.finished?
            assert c.failed?
            assert_raises(StateError) { c.call(10, 42) }
        end
    end

    it "should allow #reset to reset after a finished execution" do
        common_setup do |c, reader, writer|
            c.call(10, 42)
            writer.write(42)
            sleep(0.1)
            assert(c.done?)
            c.reset
            c.call(10, 42)
        end
    end

    it "should allow #reset to reset after an invalid call" do
        common_setup do |c, reader, writer|
            c.call(0, 42)
            sleep(0.1)
            assert_same false, c.valid?
            c.reset
            c.call(10, 42)
        end
    end
end



