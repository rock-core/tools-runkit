# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe InputWriter do
        before do
            Runkit.load_typekit "base"
        end

        it "gives write access on an input port" do
            echo = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            echo.configure
            echo.start
            in_w = echo.port("in").writer
            out_r = echo.port("out").reader

            in_w.write(10)
            assert_equal 10, read_one_sample(out_r)
        end

        it "converts ruby objects to typelib before writing" do
            echo = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            writer = echo.port("struct_in").writer
            reader = echo.port("struct_out").reader

            echo.configure
            echo.start

            assert_nil reader.read_new
            writer.write({ names: ["something"] })
            assert_equal ["something"], read_one_sample(reader).names
        end

        it "handles opaque types" do
            echo = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            writer = echo.port("opaque_in").writer
            reader = echo.port("opaque_out").reader

            echo.configure
            echo.start

            writer.write({ data: [10, 20, 30] })
            assert_equal Eigen::Vector3.new(10, 20, 30), read_one_sample(reader)
        end

        if SelfTest::USE_MQUEUE
            it "should fallback to CORBA if connection fails with MQ" do
                Runkit::MQueue.validate_sizes = false
                Runkit::MQueue.auto_sizes = false
                echo = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
                writer = echo
                         .port("opaque_in")
                         .writer(transport: Runkit::TRANSPORT_MQ,
                                 data_size: Runkit::MQueue.msgsize_max + 1,
                                 type: :buffer, size: 1)
                assert writer.connected?
            ensure
                Runkit::MQueue.validate_sizes = true
                Runkit::MQueue.auto_sizes = true
            end
        end

        describe "#connect_to" do
            it "raises if the provided policy is invalid" do
                producer = new_ruby_task_context "producer"
                out_p = producer.create_output_port "out", "double"
                consumer = new_ruby_task_context "consumer"
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
end
