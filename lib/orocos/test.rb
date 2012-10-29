require 'fileutils'
require 'typelib'
require 'orogen'
require 'flexmock/test_unit'
require 'orocos/rake'

module Orocos
    OROCOS_TEST_MODES = (ENV['OROCOS_TEST_MODES'] || "").split(',')
    TEST_MODEL_LESS = OROCOS_TEST_MODES.include?('no_model')
    TEST_MISSING_MODELS = OROCOS_TEST_MODES.include?('missing_model')
    module Test
        module Mocks
            class FakeTaskContext
            end

            def mock_task_context_model(&block)
                flexmock(Orocos.create_orogen_interface(&block))
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

        include Mocks

        USE_MQUEUE = Orocos::Rake::USE_MQUEUE

        attr_reader :processes

        def setup
            # Since we are loading typekits over and over again, we need to
            # disable type export
            Orocos.export_types = false
            Orocos.default_working_directory = WORK_DIR
            @processes = Array.new
            super if defined? super
        end

        def teardown
            processes.each { |p| p.kill }
            processes.clear
            super if defined? super
            Orocos.clear
        end

        def spawn_and_get(component, task = component)
            begin
                process = Orocos::Process.new component
                process.spawn
                process.wait_running(0.5)
            rescue Exception
                process.kill if process
                raise
            end

            processes << process
            Orocos::TaskContext.get "#{component}.#{task}"
        end
    end

    module Spec
        include FlexMock::ArgumentTypes
        include FlexMock::MockContainer

        def setup
            Orocos.default_working_directory = WORK_DIR
            Orocos::MQueue.auto = Test::USE_MQUEUE
            @old_pkg_config = ENV['PKG_CONFIG_PATH'].dup
            ENV['PKG_CONFIG_PATH'] += ":#{File.join(WORK_DIR, "prefix", 'lib', 'pkgconfig')}"
            Orocos.initialize
            Orocos.export_types = false

	    if TEST_MODEL_LESS
		flexmock(Orocos::TaskContext).new_instances(:get_from_ior).should_receive('model').and_return(nil)
		flexmock(Orocos::TaskContext).new_instances(:do_get).should_receive('model').and_return(nil)
	    elsif TEST_MISSING_MODELS
		flexmock(Orocos).should_receive(:task_model_from_name).and_raise(Orocos::NotFound)
	    end

            @old_timeout = Orocos::CORBA.connect_timeout
            Orocos::CORBA.connect_timeout = 50
            super
        end
        def teardown
	    flexmock_teardown
            super
            Orocos::CORBA.connect_timeout = @old_timeout if @old_timeout
            Orocos.instance_variable_set :@registry, nil
            Orocos::CORBA.instance_variable_set :@loaded_typekits, []
            ENV['PKG_CONFIG_PATH'] = @old_pkg_config
            Orocos.clear
        end
    end
end

