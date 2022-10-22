# frozen_string_literal: true

require "runkit/test"

describe Runkit::Port do
    include Runkit::Spec

    it "should not be possible to create an instance directly" do
        assert_raises(NoMethodError) { Runkit::Port.new }
    end

    it "should check equality based on CORBA reference" do
        task = new_ruby_task_context "task"
        task.create_output_port "out", "/double"
        task = Runkit.get "task"
        p1 = task.port "out"
        # Remove p1 from source's port cache
        task.instance_variable_get("@ports").delete("out")
        p2 = task.port "out"
        refute_same(p1, p2)
        assert_equal(p1, p2)
    end

    describe ".validate_policy" do
        it "should raise if a buffer is given without a size" do
            assert_raises(ArgumentError) { Runkit::Port.validate_policy type: :buffer }
        end
        it "should raise if a data is given with a size" do
            assert_raises(ArgumentError) { Runkit::Port.validate_policy type: :data, size: 10 }
        end
    end

    describe "handle_mq_transport" do
        attr_reader :port
        before do
            @port = new_ruby_task_context "task" do
                output_port "out", "/double"
            end.out
            Runkit::MQueue.auto = true
        end
        after do
            Runkit::MQueue.auto = false
        end

        it "creates an updated policy" do
            policy = {}
            refute_same policy, port.handle_mq_transport("input", policy)
        end
        it "does nothing if MQueue.auto is false" do
            Runkit::MQueue.auto = false
            policy = Hash[transport: 0]
            updated_policy = port.handle_mq_transport("input", policy)
            assert_equal policy, updated_policy
        end
        it "raises if the transport is explicitely but the MQueues are not available" do
            flexmock(Runkit::MQueue).should_receive(:available?).and_return(false)
            assert_raises(Runkit::Port::InvalidMQTransportSetup) do
                port.handle_mq_transport("input", transport: Runkit::TRANSPORT_MQ)
            end
        end
        it "does nothing if the transport is neither zero nor TRANSPORT_MQ" do
            policy = Hash[transport: Runkit::TRANSPORT_CORBA]
            updated_policy = port.handle_mq_transport("input", policy)
            assert_equal policy, updated_policy
        end
        it "does nothing if the transport is zero and MQueues are not available" do
            flexmock(Runkit::MQueue).should_receive(:available?).and_return(false)
            assert_equal Hash[transport: 0], port.handle_mq_transport("input", transport: 0)
        end

        describe "validation of queue length and message size" do
            it "defaults to a buffer size of MQ_RTT_DEFAULT_QUEUE_LENGTH if no size is given" do
                flexmock(Runkit::MQueue).should_receive(:valid_sizes?)
                                        .with(Runkit::Port::MQ_RTT_DEFAULT_QUEUE_LENGTH, 10, Proc)
                                        .once.pass_thru
                port.handle_mq_transport("input", transport: 0, data_size: 10)
            end
            it "defaults to a buffer size of MQ_RTT_DEFAULT_QUEUE_LENGTH if the size is zero" do
                flexmock(Runkit::MQueue).should_receive(:valid_sizes?)
                                        .with(Runkit::Port::MQ_RTT_DEFAULT_QUEUE_LENGTH, 10, Proc)
                                        .once.pass_thru
                port.handle_mq_transport("input", transport: 0, size: 0, data_size: 10)
            end
            it "validates against the given data size and buffer size" do
                flexmock(Runkit::MQueue).should_receive(:valid_sizes?)
                                        .with(42, 10, Proc)
                                        .once.pass_thru
                port.handle_mq_transport("input", transport: 0, size: 42, data_size: 10)
            end
            it "falls back to the original policy if the sizes are not valid and it was the input policy" do
                flexmock(port).should_receive(:max_marshalling_size).and_return(10)
                flexmock(Runkit::MQueue).should_receive(:valid_sizes?)
                                        .with(42, 10, Proc).once.and_return(false)
                assert_equal Hash[transport: 0, size: 42],
                             port.handle_mq_transport("input", transport: 0, size: 42)
            end
            it "raises if the sizes are not valid and the MQ transport was selected explicitely" do
                flexmock(Runkit::MQueue).should_receive(:valid_sizes?)
                                        .with(42, 10, Proc).once.and_return(false)
                assert_raises(Runkit::Port::InvalidMQTransportSetup) do
                    port.handle_mq_transport("input", transport: Runkit::TRANSPORT_MQ, size: 42, data_size: 10)
                end
            end
        end

        describe "validation of message size" do
            it "initializes data_size by the value returned by #max_marshalling_size f data_size is zero" do
                flexmock(port).should_receive(:max_marshalling_size).and_return(10)
                flexmock(Runkit::MQueue).should_receive(:validate_sizes?).and_return(false)
                assert_equal Hash[transport: Runkit::TRANSPORT_MQ, size: 42, data_size: 10],
                             port.handle_mq_transport("input", transport: 0, size: 42, data_size: 0)
            end
            it "initializes data_size by the value returned by #max_marshalling_size f data_size is not given" do
                flexmock(port).should_receive(:max_marshalling_size).and_return(10)
                flexmock(Runkit::MQueue).should_receive(:validate_sizes?).and_return(false)
                assert_equal Hash[transport: Runkit::TRANSPORT_MQ, size: 42, data_size: 10],
                             port.handle_mq_transport("input", transport: 0, size: 42)
            end
            it "falls back to the original policy if the max marshalling size cannot be computed" do
                flexmock(port).should_receive(:max_marshalling_size).and_return(nil)
                assert_equal Hash[transport: 0, size: 42],
                             port.handle_mq_transport("input", transport: 0, size: 42)
            end
            it "raises if the max marshalling size cannot be computed and the MQ transport was selected explicitely" do
                flexmock(port).should_receive(:max_marshalling_size).and_return(nil)
                assert_raises(Runkit::Port::InvalidMQTransportSetup) do
                    port.handle_mq_transport("input", transport: Runkit::TRANSPORT_MQ, size: 42)
                end
            end
        end
    end
end
