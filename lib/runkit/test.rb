# frozen_string_literal: true

# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV["TEST_ENABLE_COVERAGE"] == "1"
    begin
        require "simplecov"
        SimpleCov.start
    rescue LoadError
        require "runkit"
        Runkit.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require "runkit"
        Runkit.warn "coverage is disabled: #{e.message}"
    end
elsif ENV["TEST_ENABLE_PRY"] != "0"
    begin
        require "pry"
        require "pry-rescue/minitest" if ENV["TEST_DEBUG"] == "1"
    rescue Exception
        require "runkit"
        Runkit.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

if ENV["TEST_ENABLE_PRY"] != "0"
    begin
        require "pry"
    rescue Exception
        Runkit.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

require "minitest/autorun"
require "minitest/spec"
require "flexmock/minitest"

require "runkit"
require "runkit/rake"
require "runkit/test/mocks"
require "runkit/test/ruby_tasks"

module Runkit
    module SelfTest
        include Test::Mocks
        include Test::RubyTasks

        # A set of "modes" that can be used to control how the tests will be
        # performed
        TEST_MODES = (ENV["OROCOS_TEST_MODES"] || "").split(",")
        # Test without models
        TEST_MODEL_LESS = TEST_MODES.include?("no_model")
        # Test with models that cannot be loaded
        TEST_MISSING_MODELS = TEST_MODES.include?("missing_model")
        # Whether we should enable MQ support during tests
        USE_MQUEUE = Runkit::Rake::USE_MQUEUE

        if defined? FlexMock
            include FlexMock::ArgumentTypes
            include FlexMock::MockContainer
        end

        def work_dir
            File.join(@test_dir, "working_copy")
        end

        def data_dir
            File.join(@test_dir, "data")
        end

        def setup
            Runkit::MQueue.auto = USE_MQUEUE

            @test_dir = File.expand_path(File.join("..", "..", "test"), __dir__)
            @__tmpdirs = []

            Runkit.default_working_directory = work_dir if File.directory?(work_dir)

            @processes = []

            Runkit.initialize
            @__runkit_corba_timeouts =
                [Runkit::CORBA.call_timeout, Runkit::CORBA.connect_timeout]
            Runkit::CORBA.call_timeout = 10_000
            Runkit::CORBA.connect_timeout = 10_000

            if TEST_MODEL_LESS
                flexmock(Runkit::TaskContext).new_instances(:get_from_ior).should_receive("model").and_return(nil)
                flexmock(Runkit::TaskContext).new_instances(:do_get).should_receive("model").and_return(nil)
            elsif TEST_MISSING_MODELS
                flexmock(Runkit).should_receive(:task_model_from_name).and_raise(Runkit::NotFound)
            end
            super
        end

        def teardown
            flexmock_teardown if defined? FlexMock

            @__tmpdirs.each do |dir|
                FileUtils.rm_rf dir
            end

            processes.each do |p|
                p.kill
            rescue StandardError => e
                Runkit.warn "failed, in teardown, to stop process #{p}: #{e}"
            end

            processes.clear

            super

            if @__runkit_corba_timeouts # can be nil if setup failed
                Runkit::CORBA.call_timeout, Runkit::CORBA.connect_timeout =
                    *@__runkit_corba_timeouts
            end

            ENV["PKG_CONFIG_PATH"] = @old_pkg_config_path if @old_pkg_config_path
            Runkit::CORBA.instance_variable_set :@loaded_typekits, []
        ensure
            Runkit.clear
        end

        attr_reader :processes

        def make_tmpdir
            dir = Dir.mktmpdir
            @__tmpdirs << dir
            dir
        end

        def start(*spec)
            processes.concat Runkit.run(*spec)
        end

        def spawn_and_get(component, task = component)
            begin
                process = Runkit::Process.new component
                process.spawn
                process.wait_running(0.5)
            rescue Exception
                process&.kill
                raise
            end

            processes << process
            Runkit::TaskContext.get "#{component}.#{task}"
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
            flunk("#{task} was expected to be in toplevel state #{expected_toplevel} because of #{state} but is in #{toplevel}") if expected_toplevel != toplevel

            Integer(timeout / 0.01).times do
                return if task.state == state

                sleep 0.01
            end
            flunk("#{task} was expected to be in state #{state} but is in #{task.state}")
        end

        def wait_for(timeout = 5, &block)
            Runkit::Async.wait_for(0.005, timeout, &block)
        end

        def name_service
            Runkit.name_service
        end

        # helper for generating an ior from a name
        def ior(name)
            name_service.ior(name)
        rescue Runkit::NotFound
            "IOR:010000001f00000049444c3a5254542f636f7262612f435461736b436f6e746578743a312e300000010000000000000064000000010102000d00000031302e3235302e332e31363000002bc80e000000fe8a95a65000004d25000000000000000200000000000000080000000100000000545441010000001c00000001000000010001000100000001000105090101000100000009010100"
        end

        # Polls the async event loop until a condition is met
        #
        # @yieldreturn a falsy value if the condition is not met yet (i.e. false
        #   or nil), and a truthy value if the condition has been met. This
        #   value is returned by {#async_poll_until}
        #
        # @param [Float] period the period in seconds
        # @param [Float] timeout the timeout in seconds. The test will flunk if
        #   the condition is not met within that many seconds
        def assert_async_polls_until(period: 0.01, timeout: 5)
            start = Time.now
            loop do
                Runkit::Async.step
                if result = yield
                    return result
                end

                flunk("timed out while waiting for condition") if Time.now - start > timeout
                sleep period
            end
        end
    end
end

module Minitest
    class Test
        include Runkit::SelfTest
    end
end
