# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe OutputReader do
        before do
        end

        it "returns nil if there are no samples" do
            task = start_and_get({ "orogen_runkit_tests::SimpleSource" => "t" }, "t")
            reader = task.port("out1").reader

            assert reader.kind_of?(Runkit::OutputReader)
            assert_nil reader.read_new
            assert_nil reader.read
        end

        it "returns the received samples" do
            task = start_and_get({ "orogen_runkit_tests::SimpleSource" => "t" }, "t")
            reader = task.port("out0").reader

            task.property("increment").write(0)
            task.configure
            task.start
            assert_equal 0, read_one_sample(reader)
        end

        it "supports having more than one reader opened on a given port" do
            task = start_and_get({ "orogen_runkit_tests::SimpleSource" => "t" }, "t")
            reader0 = task.port("out0").reader
            reader1 = task.port("out0").reader

            assert reader0.connected?
            assert reader1.connected?

            task.property("increment").write(0)
            task.configure
            task.start
            assert_equal 0, read_one_sample(reader0)
            assert_equal 0, read_one_sample(reader1)
        end

        it "handles opaque types" do
            task = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            writer = task.port("opaque_in").writer
            reader = task.port("opaque_out").reader

            task.configure
            task.start

            v = Eigen::Vector3.new(1, 2, 3)
            writer.write(v)
            assert_equal v, read_one_sample(reader)
        end

        it "uses a sample if passed as argument" do
            task = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            writer = task.port("struct_in").writer
            reader = task.port("struct_out").reader

            task.configure
            task.start

            v = writer.new_sample
            v.names = ["test"]
            writer.write(v)
            assert_equal v, read_one_sample(reader)

            v.names = []
            assert_same v, reader.read(v)
            assert_equal ["test"], v.names
        end

        it "passes the policy argument" do
            task = start_and_get("fast_source_sink", "fast_source")
            task.property("increment").write(1)
            reader = task.port("out0").reader type: :buffer, size: 10

            task.configure
            task.start
            sleep(0.1)
            task.stop

            values = []
            while (v = reader.read_new)
                values << v
            end
            assert(values.size > 1)
            values.each_cons(2) do |a, b|
                assert(b == a + 1, "non-consecutive values #{a.inspect} and #{b.inspect}")
            end
        end

        it "clears its connection" do
            task = start_and_get("fast_source_sink", "fast_source")
            reader = task.port("out0").reader type: :buffer, size: 10

            task.configure
            task.start
            sleep(0.1)
            task.stop

            assert reader.read
            reader.clear
            refute reader.read
        end

        it "gets the last written value :init is specified" do
            task = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            task.configure
            task.start

            writer = task.port("in").writer
            reader = task.port("ondemand").reader

            writer.write(10)
            read_one_sample(reader)

            reader = task.port("ondemand").reader init: true
            assert_equal 10, read_one_sample(reader)
            assert_nil reader.read_new
        end

        describe "#disconnect" do
            it "disconnects from the port" do
                task = new_ruby_task_context
                task.create_output_port "out", "/double"
                reader = task.out.reader
                reader.disconnect
                refute reader.connected?
                refute task.out.connected?
            end

            it "does not affect the port's other connections" do
                task = new_ruby_task_context
                task.create_output_port "out", "/double"
                reader0 = task.out.reader
                reader1 = task.out.reader
                reader0.disconnect
                refute reader0.connected?
                assert reader1.connected?
                assert task.out.connected?
            end
        end

        if Runkit::SelfTest::USE_MQUEUE
            it "should fallback to CORBA if connection fails with MQ" do
                Runkit::MQueue.validate_sizes = false
                Runkit::MQueue.auto_sizes = false
                task = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
                reader = task.out.reader(
                    transport: Runkit::TRANSPORT_MQ,
                    data_size: Runkit::MQueue.msgsize_max + 1,
                    type: :buffer, size: 1
                )
                assert reader.connected?
            ensure
                Runkit::MQueue.validate_sizes = true
                Runkit::MQueue.auto_sizes = true
            end
        end
    end
end
