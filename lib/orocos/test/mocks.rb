# frozen_string_literal: true

module Orocos
    module Test
        module Mocks
            class FakeTaskContext
            end

            def mock_task_context_model(&block)
                project = OroGen::Spec::Project.new(Orocos.default_loader)
                interface = OroGen::Spec::TaskContext.new(project)
                interface.instance_eval(&block)
                flexmock(interface)
            end

            def mock_input_port(port_model)
                port = flexmock("mock for #{port_model}")
                port.should_receive(:model).and_return(port_model)
                port_writer = flexmock("mock for input writer to #{port_model}")
                port_writer.should_receive(:connected?).and_return(false)
                port.should_receive(:writer).and_return(port_writer).by_default
                port
            end

            def mock_output_port(port_model)
                port = flexmock("mock for #{port_model}")
                port.should_receive(:model).and_return(port_model)
                port.should_receive(:connected?).and_return(false)
                port_reader = flexmock("mock for output reader from #{port_model}")
                port_reader.should_receive(:connected?).and_return(false)
                port.should_receive(:reader).and_return(port_reader).by_default
                port
            end

            def mock_task_context(orogen_model)
                mock = flexmock(FakeTaskContext.new)
                mock.should_receive(:model).and_return(orogen_model)
                mock.should_receive(:port_names).and_return(orogen_model.each_input_port.map(&:name).to_a + orogen_model.each_output_port.map(&:name))
                orogen_model.each_input_port do |port_model|
                    port = mock_input_port(port_model)
                    mock.should_receive(:port).with(port_model.name).and_return(port)
                    mock.should_receive(:port).with(port_model.name, FlexMock.any).and_return(port)
                end
                orogen_model.each_output_port do |port_model|
                    port = mock_output_port(port_model)
                    mock.should_receive(:port).with(port_model.name).and_return(port)
                    mock.should_receive(:port).with(port_model.name, FlexMock.any).and_return(port)
                end
                mock
            end
        end
    end
end
