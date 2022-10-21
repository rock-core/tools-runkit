# frozen_string_literal: true

require "orocos/test"
describe Orocos::InputWriter do
    unless defined? TEST_DIR
        TEST_DIR = __dir__
        DATA_DIR = File.join(TEST_DIR, "data")
        WORK_DIR = File.join(TEST_DIR, "working_copy")
    end

    CORBA = Orocos::CORBA
    include Orocos::Spec

    it "should not be possible to create an instance directly" do
        assert_raises(NoMethodError) { Orocos::InputWriter.new }
    end

    it "should offer write access on an input port" do
        Orocos.run("echo") do |echo|
            echo  = echo.task("Echo")
            input = echo.port("input")

            writer = input.writer
            assert_kind_of Orocos::InputWriter, writer
            writer.write(0)
        end
    end

    it "should raise Corba::ComError when writing on a dead port and be disconnected" do
        Orocos.run("echo") do |echo_p|
            echo  = echo_p.task("Echo")
            input = echo.port("input")

            writer = input.writer
            echo_p.kill(true, "KILL")
            assert_raises(CORBA::ComError) { writer.write(0) }
            assert(!writer.connected?)
        end
    end

    it "should be able to write data to an input port using a data connection" do
        Orocos.run("echo") do |echo|
            echo = echo.task("Echo")
            writer = echo.port("input").writer
            reader = echo.port("output").reader

            echo.start
            assert_equal(nil, reader.read)
            writer.write(10)
            sleep(0.1)
            assert_equal(10, reader.read)
        end
    end

    it "should be able to write structs using a Hash" do
        Orocos.run("echo") do |echo|
            echo = echo.task("Echo")
            writer = echo.port("input_struct").writer
            reader = echo.port("output").reader

            echo.start
            assert_equal(nil, reader.read)
            writer.write(value: 10)
            sleep(0.1)
            assert_equal(10, reader.read)
        end
    end

    it "should allow to write opaque types" do
        Orocos.run("echo") do |echo|
            echo = echo.task("Echo")
            writer = echo.port("input_opaque").writer
            reader = echo.port("output_opaque").reader

            echo.start

            writer.write(x: 84, y: 42)
            sleep(0.2)
            sample = reader.read
            assert_equal(84, sample.x)
            assert_equal(42, sample.y)

            sample = writer.new_sample
            sample.x = 20
            sample.y = 10
            writer.write(sample)
            sleep(0.2)
            sample = reader.read
            assert_equal(20, sample.x)
            assert_equal(10, sample.y)
        end
    end

    if Orocos::SelfTest::USE_MQUEUE
        it "should fallback to CORBA if connection fails with MQ" do
            Orocos::MQueue.validate_sizes = false
            Orocos::MQueue.auto_sizes = false
            Orocos.run("echo") do |echo|
                echo = echo.task("Echo")
                writer = echo.port("input_opaque").writer(transport: Orocos::TRANSPORT_MQ, data_size: Orocos::MQueue.msgsize_max + 1, type: :buffer, size: 1)
                assert writer.connected?
            end
        ensure
            Orocos::MQueue.validate_sizes = true
            Orocos::MQueue.auto_sizes = true
        end
    end

    describe "#connect_to" do
        it "should raise if the provided policy is invalid" do
            producer = Orocos::RubyTasks::TaskContext.new "producer"
            out_p = producer.create_output_port "out", "double"
            consumer = Orocos::RubyTasks::TaskContext.new "consumer"
            in_p = consumer.create_input_port "in", "double"
            assert_raises(ArgumentError) do
                out_p.connect_to in_p, type: :pull,
                                       init: false,
                                       pull: false,
                                       data_size: 0,
                                       size: 0,
                                       lock: :lock_free,
                                       transport: 0,
                                       name_id: ""
            end
        end
    end
end
