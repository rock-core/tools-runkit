require 'orocos/test'

module Orocos
    describe PortBase do
        describe "#distance_to" do
            attr_reader :source, :sink
            before do
                @source = new_ruby_task_context 'source' do
                    output_port 'out', '/double'
                end
                @sink = new_ruby_task_context 'sink'  do
                    input_port 'in', '/double'
                end
            end

            it "returns D_UNKNOWN if the input port has no process" do
                flexmock(sink).should_receive(:process).and_return(nil)
                assert_equal PortBase::D_UNKNOWN, source.out.distance_to(sink.in)
            end
            it "returns D_UNKNOWN if the output port has no process" do
                flexmock(source).should_receive(:process).and_return(nil)
                assert_equal PortBase::D_UNKNOWN, source.out.distance_to(sink.in)
            end
            it "returns D_SAME_PROCESS if both tasks have the same process" do
                process = flexmock
                flexmock(sink).should_receive(:process).and_return(process)
                flexmock(source).should_receive(:process).and_return(process)
                assert_equal PortBase::D_SAME_PROCESS, source.out.distance_to(sink.in)
            end
            it "returns D_SAME_HOST if both tasks have different processes on the same host" do
                flexmock(sink).should_receive(:process).and_return(flexmock(host_id: 'here'))
                flexmock(source).should_receive(:process).and_return(flexmock(host_id: 'here'))
                assert_equal PortBase::D_SAME_HOST, source.out.distance_to(sink.in)
            end
            it "returns D_DIFFERENT_HOSTS if both tasks have different processes on different hosts" do
                flexmock(sink).should_receive(:process).and_return(flexmock(host_id: 'here'))
                flexmock(source).should_receive(:process).and_return(flexmock(host_id: 'there'))
                assert_equal PortBase::D_DIFFERENT_HOSTS, source.out.distance_to(sink.in)
            end
        end
    end

    describe InputPortBase do
        describe "#writer" do
            attr_reader :input_port
            before do
                @input_port = new_ruby_task_context 'source' do
                    input_port 'out', '/double'
                end.out
            end
            def assert_creates_writer_port(*expected_args)
                flexmock(Orocos.ruby_task).should_receive(:create_output_port).
                    once.pass_thru do |port|
                        yield(port)
                        port
                    end
            end

            it "creates a transient port and connects it" do
                assert_creates_writer_port do |port|
                    assert_kind_of OutputPort, port
                    flexmock(port).should_receive(:connect_to).
                        with(input_port, Hash).
                        pass_thru
                    port
                end.with(String, String, hsh(permanent: false))
                input_port.writer
            end
            it "sets the port attribute on the returned writer" do
                assert_equal input_port, input_port.writer.port
            end
            it "sets the policy attribute on the returned writer" do
                assert_equal Hash[type: :buffer, size: 10], input_port.writer(type: :buffer, size: 10).policy
            end
            it "passes D_UNKNOWN as distance by default" do
                assert_creates_writer_port do |port|
                    flexmock(port).should_receive(:connect_to).
                        with(input_port, hsh(distance: PortBase::D_UNKNOWN))
                end
                input_port.writer
            end
            it "passes the distance argument to the connection" do
                distance = flexmock
                assert_creates_writer_port do |port|
                    flexmock(port).should_receive(:connect_to).
                        with(input_port, hsh(distance: distance))
                end
                input_port.writer(distance: distance)
            end
            it "passes the policy to the connection" do
                distance = flexmock
                assert_creates_writer_port do |port|
                    flexmock(port).should_receive(:connect_to).
                        with(input_port, hsh(distance: distance))
                end
                input_port.writer(distance: distance)
            end
        end
    end

    describe OutputPortBase do
        describe "#reader" do
            attr_reader :output_port
            before do
                @output_port = new_ruby_task_context 'source' do
                    output_port 'out', '/double'
                end.out
            end
            def assert_creates_reader_port(*expected_args)
                flexmock(Orocos.ruby_task).should_receive(:create_input_port).
                    once.pass_thru do |port|
                        yield(port)
                        port
                    end
            end

            it "creates a transient port and connects it" do
                assert_creates_reader_port do |port|
                    assert_kind_of InputPort, port
                    flexmock(port).should_receive(:connect_to).
                        with(output_port, Hash).
                        pass_thru
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
                    flexmock(port).should_receive(:connect_to).
                        with(output_port, hsh(distance: PortBase::D_UNKNOWN))
                end
                output_port.reader
            end
            it "passes the distance argument to the connection" do
                distance = flexmock
                assert_creates_reader_port do |port|
                    flexmock(port).should_receive(:connect_to).
                        with(output_port, hsh(distance: distance))
                end
                output_port.reader(distance: distance)
            end
            it "passes the policy to the connection" do
                distance = flexmock
                assert_creates_reader_port do |port|
                    flexmock(port).should_receive(:connect_to).
                        with(output_port, hsh(distance: distance))
                end
                output_port.reader(distance: distance)
            end
        end
    end
end


