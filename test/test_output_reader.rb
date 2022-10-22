# frozen_string_literal: true

require "runkit/test"

describe Runkit::OutputReader do
    unless defined? TEST_DIR
        TEST_DIR = __dir__
        DATA_DIR = File.join(TEST_DIR, "data")
        WORK_DIR = File.join(TEST_DIR, "working_copy")
    end

    include Runkit::Spec

    it "should not be possible to create an instance directly" do
        assert_raises(NoMethodError) { Runkit::OutputReader.new }
    end

    it "should offer read access on an output port" do
        Runkit.run("simple_source") do |source|
            source = source.task("source")
            output = source.port("cycle")

            # Create a new reader. The default policy is data
            reader = output.reader
            assert(reader.kind_of?(Runkit::OutputReader))
            assert_equal(nil, reader.read) # nothing written yet
        end
    end

    it "should allow to read opaque types" do
        Runkit.run("echo") do |source|
            source = source.task("Echo")
            output = source.port("output_opaque")
            reader = output.reader
            source.configure
            source.start
            source.write_opaque(42)

            sleep(0.2)

            # Create a new reader. The default policy is data
            sample = reader.read
            assert_equal(42, sample.x)
            assert_equal(84, sample.y)
        end
    end

    it "should allow reusing a sample" do
        Runkit.run("echo") do |source|
            source = source.task("Echo")
            output = source.port("output_opaque")
            reader = output.reader
            source.configure
            source.start
            source.write_opaque(42)

            sleep(0.2)

            # Create a new reader. The default policy is data
            sample = output.new_sample
            returned_sample = reader.read(sample)
            assert_same returned_sample, sample
            assert_equal(42, sample.x)
            assert_equal(84, sample.y)
        end
    end

    it "should be able to read data from an output port using a data connection" do
        Runkit.run("simple_source") do |source|
            source = source.task("source")
            output = source.port("cycle")
            source.configure
            source.start

            # The default policy is data
            reader = output.reader
            sleep(0.2)
            assert(reader.read > 1)
        end
    end

    it "should be able to read data from an output port using a buffer connection" do
        Runkit.run("simple_source") do |source|
            source = source.task("source")
            output = source.port("cycle")
            reader = output.reader type: :buffer, size: 10
            source.configure
            source.start
            sleep(0.5)
            source.stop

            values = []
            while v = reader.read_new
                values << v
            end
            assert(values.size > 1)
            values.each_cons(2) do |a, b|
                assert(b == a + 1, "non-consecutive values #{a.inspect} and #{b.inspect}")
            end
        end
    end

    it "should be able to read data from an output port using a struct" do
        Runkit.run("simple_source") do |source|
            source = source.task("source")
            output = source.port("cycle_struct")
            reader = output.reader type: :buffer, size: 10
            source.configure
            source.start
            sleep(0.5)
            source.stop

            values = []
            while v = reader.read_new
                values << v.value
            end
            assert(values.size > 1)
            values.each_cons(2) do |a, b|
                assert(b == a + 1, "non-consecutive values #{a.inspect} and #{b.inspect}")
            end
        end
    end

    it "should be able to clear its connection" do
        Runkit.run("simple_source") do |source|
            source = source.task("source")
            output = source.port("cycle")
            reader = output.reader
            source.configure
            source.start
            sleep(0.5)
            source.stop

            assert(reader.read)
            reader.clear
            assert(!reader.read)
        end
    end

    it "does not raise if the remote end is dead, but is disconnected" do
        Runkit.run "simple_source" do |source_p|
            source = source_p.task("source")
            output = source.port("cycle")
            reader = output.reader
            source.configure
            source.start
            sleep(0.5)

            source_p.kill(true, "KILL")

            reader.read # should not raise
            refute reader.connected?
        end
    end

    it "should get an initial value when :init is specified" do
        Runkit.run("echo") do |echo|
            echo = echo.task("Echo")
            echo.start

            reader = echo.ondemand.reader
            assert(!reader.read, "got data on 'ondemand': #{reader.read}")
            echo.write(10)
            sleep 0.1
            assert_equal(10, reader.read)
            reader = echo.ondemand.reader(init: true)
            sleep 0.1
            assert_equal(10, reader.read)
        end
    end

    describe "#disconnect" do
        it "disconnects from the port" do
            task = new_ruby_task_context "test" do
                output_port "out", "/double"
            end
            reader = task.out.reader
            reader.disconnect
            assert !reader.connected?
            assert !task.out.connected?
        end

        it "does not affect the port's other connections" do
            task = new_ruby_task_context "test" do
                output_port "out", "/double"
            end
            reader0 = task.out.reader
            reader1 = task.out.reader
            reader0.disconnect
            assert !reader0.connected?
            assert reader1.connected?
            assert task.out.connected?
        end
    end

    if Runkit::SelfTest::USE_MQUEUE
        it "should fallback to CORBA if connection fails with MQ" do
            Runkit::MQueue.validate_sizes = false
            Runkit::MQueue.auto_sizes = false
            Runkit.run("echo") do |echo|
                echo = echo.task("Echo")
                reader = echo.ondemand.reader(transport: Runkit::TRANSPORT_MQ, data_size: Runkit::MQueue.msgsize_max + 1, type: :buffer, size: 1)
                assert reader.connected?
            end
        ensure
            Runkit::MQueue.validate_sizes = true
            Runkit::MQueue.auto_sizes = true
        end
    end
end
