# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe InputPort do
        describe "connection handling" do
            attr_reader :source, :sink

            before do
                task = new_ruby_task_context "source"
                @source = task.create_output_port "out", "/double"
                task = new_ruby_task_context "sink"
                @sink = task.create_input_port "in", "/double"
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
                    task, pid = new_external_ruby_task_context(
                        "remote_source", output_ports: Hash["out" => "/double"]
                    )
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
