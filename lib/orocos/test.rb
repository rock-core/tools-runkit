require 'fileutils'
require 'typelib'
require 'orogen'
require 'flexmock/test_unit'
require 'orocos/rake'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        Orocos.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module Orocos
    OROCOS_TEST_MODES = (ENV['OROCOS_TEST_MODES'] || "").split(',')
    TEST_MODEL_LESS = OROCOS_TEST_MODES.include?('no_model')
    TEST_MISSING_MODELS = OROCOS_TEST_MODES.include?('missing_model')
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

        include Mocks

        USE_MQUEUE = Orocos::Rake::USE_MQUEUE

        attr_reader :processes

        def setup
            # Since we are loading typekits over and over again, we need to
            # disable type export
            Orocos.export_types = false
            if File.directory?(WORK_DIR)
                Orocos.default_working_directory = WORK_DIR
            end
            @processes = Array.new
            super if defined? super
        end

        def teardown
            processes.each { |p| p.kill }
            processes.clear
            super if defined? super
            Orocos.clear
        end

        def start(*spec)
            processes.concat Orocos.run(*spec)
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

        attr_reader :processes

        def setup
            if defined?(Orocos::Async)
                Orocos::Async::NameServiceBase.default_period = 0
                Orocos::Async::TaskContextBase.default_period = 0
                Orocos::Async::CORBA::Attribute.default_period = 0
                Orocos::Async::CORBA::Property.default_period = 0
                Orocos::Async::CORBA::OutputReader.default_period = 0
            end

            Orocos::MQueue.auto = Test::USE_MQUEUE
            @old_pkg_config = ENV['PKG_CONFIG_PATH'].dup

            if defined?(WORK_DIR) && File.directory?(WORK_DIR)
                Orocos.default_working_directory = WORK_DIR
                ENV['PKG_CONFIG_PATH'] += ":#{File.join(WORK_DIR, "prefix", 'lib', 'pkgconfig')}"
            end
            Orocos.initialize

	    if TEST_MODEL_LESS
		flexmock(Orocos::TaskContext).new_instances(:get_from_ior).should_receive('model').and_return(nil)
		flexmock(Orocos::TaskContext).new_instances(:do_get).should_receive('model').and_return(nil)
	    elsif TEST_MISSING_MODELS
		flexmock(Orocos).should_receive(:task_model_from_name).and_raise(Orocos::NotFound)
	    end

            @processes = Array.new
            @old_timeout = Orocos::CORBA.connect_timeout
            Orocos::CORBA.connect_timeout = 50
            @allocated_task_contexts = Array.new
            super
        end

        def start(*spec)
            processes.concat Orocos.run(*spec)
        end

        def name_service
            Orocos.name_service
        end

        def read_one_sample(reader, timeout = 1)
            Integer(timeout / 0.01).times do
                if value = reader.read_new
                    return value
                end
                sleep 0.01

            end
            flunk("expected to receive one new sample on #{reader}, but got none (state: #{reader.port.task.rtt_state}")
        end

        def assert_state_equals(state, task, timeout = 1)
            expected_toplevel = task.toplevel_state(state)
            toplevel = task.rtt_state
            if expected_toplevel != toplevel
                flunk("#{task} was expected to be in toplevel state #{expected_toplevel} because of #{state} but is in #{toplevel}")
            end

            Integer(timeout / 0.01).times do
                if task.state == state
                    return
                end
                sleep 0.01
            end
            flunk("#{task} was expected to be in state #{state} but is in #{task.state}")
        end

        def teardown
	    flexmock_teardown
            processes.each do |p|
                begin p.kill
                rescue Exception => e
                    Orocos.warn "failed, in teardown, to stop process #{p}: #{e}"
                end
            end
            processes.clear
            @allocated_task_contexts.each(&:dispose)
            super
            Orocos::CORBA.connect_timeout = @old_timeout if @old_timeout
            Orocos::CORBA.instance_variable_set :@loaded_typekits, []
            ENV['PKG_CONFIG_PATH'] = @old_pkg_config
            Orocos.clear
        end

        def new_ruby_task_context(name, options = Hash.new, &block)
            task = Orocos::RubyTasks::TaskContext.new(name, options, &block)
            @allocated_task_contexts << task
            task
        end

        def wait_for(timeout = 5, &block)
            Orocos::Async.wait_for(0.005, timeout, &block)
        end
    end
end

