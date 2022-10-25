# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe OutputPortBase do
        describe "#reader" do
            attr_reader :output_port

            before do
                task = new_ruby_task_context "source"
                @output_port = task.create_output_port "out", "/double"
            end

            def assert_creates_reader_port(*expected_args)
                flexmock(Runkit.ruby_task).should_receive(:create_input_port)
                                          .once.pass_thru do |port|
                    yield(port)
                    port
                end
            end

            it "creates a transient port and connects it" do
                assert_creates_reader_port do |port|
                    assert_kind_of InputPort, port
                    flexmock(port).should_receive(:connect_to)
                                  .with(output_port, Hash)
                                  .pass_thru
                    port
                end.with(String, String, hsh(permanent: false))
                output_port.reader
            end
            it "sets the port attribute on the returned reader" do
                assert_equal output_port, output_port.reader.port
            end
            it "sets the policy attribute on the returned reader" do
                assert_equal Hash[type: :buffer, size: 10], output_port.reader(type: :buffer, size: 10).policy
            end
            it "passes D_UNKNOWN as distance by default" do
                assert_creates_reader_port do |port|
                    flexmock(port).should_receive(:connect_to)
                                  .with(output_port, hsh(distance: PortBase::D_UNKNOWN))
                end
                output_port.reader
            end
            it "passes the distance argument to the connection" do
                distance = flexmock
                assert_creates_reader_port do |port|
                    flexmock(port).should_receive(:connect_to)
                                  .with(output_port, hsh(distance: distance))
                end
                output_port.reader(distance: distance)
            end
            it "passes the policy to the connection" do
                distance = flexmock
                assert_creates_reader_port do |port|
                    flexmock(port).should_receive(:connect_to)
                                  .with(output_port, hsh(distance: distance))
                end
                output_port.reader(distance: distance)
            end
        end
    end
end

