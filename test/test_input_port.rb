# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe InputPort do
        it "should not be possible to create an instance directly" do
            assert_raises(NoMethodError) { InputPort.new }
        end

        it "should have the right model" do
            Runkit.run("simple_sink") do
                task = Runkit.get("simple_sink_sink")
                port = task.port("cycle")
                assert_same port.model, task.model.find_input_port("cycle")
            end
        end

        describe "connection handling" do
            attr_reader :source, :sink

            before do
                task = new_ruby_task_context "source"
                @source = task.create_output_port "out", "/double"
                task = new_ruby_task_context "sink"
                @sink = task.create_input_port "in", "/double"
            end

            describe "#connect_to" do
                it "raises if given another input port" do
                    task = new_ruby_task_context "other_sink"
                    other_sink = task.create_input_port "in", "/double"
                    assert_raises(ArgumentError) do
                        sink.connect_to other_sink
                    end
                end
                it "calls the output port's connect_to" do
                    flexmock(source).should_receive(:connect_to)
                                    .with(sink, policy = flexmock)
                                    .once
                    sink.connect_to source, policy
                end
            end

            describe "#disconnect_all" do
                it "disconnects all connections" do
                    task = new_ruby_task_context "other_source"
                    other_source = task.create_output_port "out", "/double"
                    source.connect_to sink
                    other_source.connect_to sink
                    sink.disconnect_all
                    refute source.connected?
                    refute other_source.connected?
                    refute sink.connected?
                end

                it "disconnects all inputs even though some are dead" do
                    task, pid = new_external_ruby_task_context "remote_source",
                                                               output_ports: Hash["out" => "/double"]
                    other_source = task.port("out")

                    source.connect_to sink
                    other_source.connect_to sink
                    ::Process.kill "KILL", pid
                    ::Process.waitpid pid
                    assert sink.connected?
                    sink.disconnect_all
                    refute sink.connected?
                    refute source.connected?
                end
            end
        end
    end
end
