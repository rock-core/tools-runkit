# frozen_string_literal: true

require "runkit/test"
module Runkit
    describe OutputPort do
        describe "connection handling" do
            attr_reader :source, :sink

            before do
                task = new_ruby_task_context "source"
                @source = task.create_output_port "out", "/double"
                task = new_ruby_task_context "sink"
                @sink = task.create_input_port "in", "/double"
            end

            def dataflow_stress_test_count
                return unless (count = ENV["DATAFLOW_STRESS_TEST"])

                Integer(count)
            end

            describe "#connect_to" do
                it "connects an output to an input" do
                    refute sink.connected?
                    refute source.connected?
                    source.connect_to sink
                    assert sink.connected?
                    assert source.connected?
                end

                it "raises ComError when connected to a dead input" do
                    sink.task.dispose
                    assert_raises(ComError) { source.connect_to sink }
                end

                it "raises ComError when called on a dead output" do
                    source.task.dispose
                    assert_raises(ComError) { source.connect_to sink }
                end

                it "raises InterfaceObjectNotFound if the source has disappeared" do
                    source.remove
                    e = assert_raises(InterfaceObjectNotFound) do
                        source.connect_to sink
                    end
                    assert_equal "port 'in' disappeared from task 'sink'", e.message
                end

                it "raises InterfaceObjectNotFound if the sink has disappeared" do
                    sink.remove
                    e = assert_raises(InterfaceObjectNotFound) do
                        source.connect_to sink
                    end
                    assert_equal "port 'out' disappeared from task 'source'", e.message
                end

                it "refuses connecting to another OutputPort" do
                    task = new_ruby_task_context "other_source"
                    task.create_input_port "out", "/double"

                    assert_raises(ArgumentError) { source.connect_to source }
                    refute source.connected?
                end
            end

            describe "#disconnect_from" do
                attr_reader :other_sink
                before do
                    task = new_ruby_task_context "other_sink"
                    @other_sink = task.create_input_port "in", "/double"
                end

                it "returns false if the connection did not exist" do
                    refute source.disconnect_from(sink)
                end

                it "disconnects from a specific input" do
                    source.connect_to sink
                    source.connect_to other_sink
                    assert source.disconnect_from(sink)

                    assert source.connected?
                    refute sink.connected?
                    assert other_sink.connected?
                end

                it "disconnects from a dead input" do
                    task, pid = new_external_ruby_task_context(
                        "remote_sink", input_ports: Hash["in" => "/double"]
                    )
                    sink = task.port("in")

                    source.connect_to sink
                    assert source.connected?
                    ::Process.kill "KILL", pid
                    ::Process.waitpid pid
                    assert source.connected?
                    assert source.disconnect_from(sink)
                    refute source.connected?
                end
            end

            describe "#disconnect_all" do
                it "disconnects all connections" do
                    task = new_ruby_task_context "other_sink"
                    other_sink = task.create_input_port "in", "/double"
                    source.connect_to sink
                    source.connect_to other_sink
                    source.disconnect_all
                    refute source.connected?
                    refute other_sink.connected?
                    refute sink.connected?
                end

                it "disconnects all inputs even though some are dead" do
                    task, pid = new_external_ruby_task_context(
                        "remote_sink", input_ports: Hash["in" => "/double"]
                    )
                    other_sink = task.port("in")

                    source.connect_to sink
                    source.connect_to other_sink
                    ::Process.kill "KILL", pid
                    ::Process.waitpid pid
                    assert source.connected?
                    source.disconnect_all
                    refute source.connected?
                    refute sink.connected?
                end
            end

            it "behaves correctly if connections are modified while running" do
                last = nil

                process = start("fast_source_sink").first
                source_task = process.task "fast_source"
                sink_task = process.task "fast_sink"
                sources = (0...4).map { |i| source_task.port("out#{i}") }
                sinks = (0...4).map { |i| sink_task.port("in#{i}") }

                count, display = nil
                if dataflow_stress_test_count
                    count   = dataflow_stress_test_count
                    display = true
                else
                    count = 10_000
                end

                source_task.configure
                source_task.start
                sink_task.configure
                sink_task.start
                count.times do |i|
                    p_out = sources[rand(4)]
                    p_in  = sinks[rand(4)]
                    p_out.connect_to p_in, pull: (rand > 0.5)
                    p_out.disconnect_all if rand > 0.8

                    if display && (i % 1000 == 0)
                        delay = Time.now - last if last
                        last = Time.now
                        STDERR.puts "#{i} #{delay}"
                    end
                end
            end
        end

        describe "POSIX MQ handling" do
            before do
                skip "MQ is not compiled-in" if SelfTest::USE_MQUEUE
            end

            it "should fallback to CORBA if connection fails with MQ" do
                MQueue.validate_sizes = false
                MQueue.auto_sizes = false
                flexmock(Runkit)
                    .should_receive(:warn)
                    .with("failed to create a connection from source.out to sink.in "\
                          "using the MQ transport, falling back to CORBA")
                    .once
                task = new_ruby_task_context "source"
                source = task.create_output_port "out", "/double"
                task = new_ruby_task_context "sink"
                sink = task.create_input_port "in", "/double"

                source.connect_to sink, transport: TRANSPORT_MQ,
                                        data_size: MQueue.msgsize_max + 1,
                                        type: :buffer, size: 1
                assert source.connected?
            ensure
                MQueue.validate_sizes = true
                MQueue.auto_sizes = true
            end
        end
    end
end
