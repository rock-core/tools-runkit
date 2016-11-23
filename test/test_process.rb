require 'orocos/test'

describe Orocos::Process do
    describe ".partition_run_options" do
        attr_reader :deployment_m, :task_m
        before do
            @deployment_m = Orocos.default_loader.deployment_model_from_name('process')
            @task_m = Orocos.default_loader.task_model_from_name('process::Test')
        end
        it "partitions deployment names from task model names using Orocos.available_task_models" do
            deployments, models, options =
                Orocos::Process.partition_run_options 'process' => 'name2', 'process::Test' => 'name'
            assert_equal Hash[deployment_m => 'name2'], deployments
            assert_equal Hash[task_m => ['name']], models
        end
        it "sets to nil the prefix for deployments that should not have one" do
            deployments, models, options =
                Orocos::Process.partition_run_options 'process', 'process::Test' => 'name'
            assert_equal Hash[deployment_m => nil], deployments
        end
        it "raises if an unexisting name is given" do
            assert_raises(ArgumentError) do
                Orocos::Process.partition_run_options 'does_not_exist'
            end
        end
        it "raises if a task model is given without a name" do
            assert_raises(ArgumentError) do
                Orocos::Process.partition_run_options 'process::Test'
            end
        end
    end

    it "raises NotFound when the deployment name does not exist" do
        assert_raises(OroGen::DeploymentModelNotFound) { Orocos::Process.new("does_not_exist") }
    end

    describe 'parse_run_options' do
        describe 'per-deployment wrappers' do
            before do
                flexmock(Orocos::Process).should_receive(:partition_run_options).with('foo', 'bar', any).
                    and_return([Hash[flexmock(name: 'foo_prefixed'), nil,
                                     flexmock(name: 'bar_prefixed'), nil],
                                Hash.new])
            end
            let(:wrapper_options) { flexmock }

            def parse_run_options(wrapper_name, arg, options: wrapper_options)
                opts = Hash[wrapper_name.to_sym => arg]
                if options
                    opts["#{wrapper_name}_options".to_sym] = options
                end

                processes, _ = Orocos::Process.parse_run_options('foo', 'bar', **opts)
                processes.inject(Hash.new) do |h, (_, _, name, spawn)|
                    h.merge(name => spawn[wrapper_name.to_sym])
                end
            end

            %w{valgrind gdb}.each do |wrapper|
                it "uses an empty hash as default value if if no #{wrapper} options are explicitely given" do
                    result = parse_run_options(wrapper, true, options: nil)
                    assert_equal Hash.new, result['foo_prefixed']
                    assert_equal Hash.new, result['bar_prefixed']
                end
                it "passes the #{wrapper} options to all deployments if given 'true'" do
                    result = parse_run_options(wrapper, true)
                    assert_equal wrapper_options, result['foo_prefixed']
                    assert_equal wrapper_options, result['bar_prefixed']
                end
                it "passes the #{wrapper} options to a select set of deployments if given a list of names" do
                    result = parse_run_options(wrapper, ['foo_prefixed'])
                    assert_equal wrapper_options, result['foo_prefixed']
                    assert !result['bar_prefixed']
                end
                it "raises if the name array given as '#{wrapper}' contains non-existent deployments" do
                    assert_raises(ArgumentError) do
                        parse_run_options(wrapper, ['foo'])
                    end
                end
                it "passes per-deployment #{wrapper} options if given a hash" do
                    result = parse_run_options(wrapper, Hash[
                        'foo_prefixed' => (options0 = flexmock),
                        'bar_prefixed' => (options1 = flexmock)])
                    assert_equal options0, result['foo_prefixed']
                    assert_equal options1, result['bar_prefixed']
                end
            end
        end

        describe 'per-model wrappers' do
            before do
                flexmock(Orocos::Process).should_receive(:partition_run_options).with('foo', 'bar', any).
                    and_return([Hash.new,
                                Hash[flexmock, ['foo_prefixed'],
                                     flexmock, ['bar_prefixed']]])
                flexmock(Orocos::Process).should_receive(:resolve_name_mappings).
                    and_return do |_, models|
                        models.flat_map do |obj, new_names|
                            Array(new_names).map { |n| [flexmock, Hash.new, n] }
                        end
                    end
            end
            let(:wrapper_options) { flexmock }

            def parse_run_options(wrapper_name, arg, options: wrapper_options)
                opts = Hash[wrapper_name.to_sym => arg]
                if options
                    opts["#{wrapper_name}_options".to_sym] = options
                end

                processes, _ = Orocos::Process.parse_run_options('foo', 'bar', **opts)
                processes.inject(Hash.new) do |h, (_, _, name, spawn)|
                    h.merge(name => spawn[wrapper_name.to_sym])
                end
            end

            %w{valgrind gdb}.each do |wrapper|
                it "uses an empty hash as default value if if no #{wrapper} options are explicitely given" do
                    result = parse_run_options(wrapper, true, options: nil)
                    assert_equal Hash.new, result['foo_prefixed']
                    assert_equal Hash.new, result['bar_prefixed']
                end
                it "passes the #{wrapper} options to all deployments if given 'true'" do
                    result = parse_run_options(wrapper, true)
                    assert_equal wrapper_options, result['foo_prefixed']
                    assert_equal wrapper_options, result['bar_prefixed']
                end
                it "passes the #{wrapper} options to a select set of deployments if given a list of names" do
                    result = parse_run_options(wrapper, ['foo_prefixed'])
                    assert_equal wrapper_options, result['foo_prefixed']
                    assert !result['bar_prefixed']
                end
                it "raises if the name array given as '#{wrapper}' contains non-existent deployments" do
                    assert_raises(ArgumentError) do
                        parse_run_options(wrapper, ['foo'])
                    end
                end
                it "passes per-deployment #{wrapper} options if given a hash" do
                    result = parse_run_options(wrapper, Hash[
                        'foo_prefixed' => (options0 = flexmock),
                        'bar_prefixed' => (options1 = flexmock)])
                    assert_equal options0, result['foo_prefixed']
                    assert_equal options1, result['bar_prefixed']
                end
            end
        end
    end
    
    describe "#spawn" do
        it "starts a new process and waits for it with a timeout" do
            process = Orocos::Process.new('process')
            # To ensure that the test teardown will kill it
            processes << process
            process.spawn :wait => 10
            Orocos.get "process_Test"
            assert(process.alive?)
            assert(process.running?)
        end

        it "starts a new process and waits for it without a timeout" do
            process = Orocos::Process.new('process')
            # To ensure that the test teardown will kill it
            processes << process
            process.spawn :wait => true
            Orocos.get "process_Test"
            assert(process.alive?)
            assert(process.running?)
        end

        it "can automatically add prefixes to tasks" do
            process = Orocos::Process.new 'process'
            begin
                process.spawn :prefix => 'prefix'
                assert_equal Hash["process_Test" => "prefixprocess_Test"], process.name_mappings
                assert Orocos.name_service.get('prefixprocess_Test')
            ensure
                process.kill
            end
        end

        it "can rename single tasks" do
            process = Orocos::Process.new 'process'
            begin
                process.map_name "process_Test", "prefixprocess_Test"
                process.spawn
                assert Orocos.name_service.get('prefixprocess_Test')
            ensure
                process.kill
            end
        end
    end

    describe "#kill" do
        it "stops a running process and clean up the name server" do
            Orocos.run('process') do |process|
                assert( Orocos.task_names.find { |name| name == '/process_Test' } )
                process.kill
                assert(!process.alive?, "process has been killed but alive? returns true")
                assert( !Orocos.task_names.find { |name| name == 'process_Test' } )
            end
        end
    end

    describe "#task" do
        it "can get a reference on a deployed task context by name" do
            Orocos.run('process') do |process|
                assert(direct   = Orocos::TaskContext.get('process_Test'))
                assert(indirect = process.task("Test"))
                assert_equal(direct, indirect)
            end
        end

        it "throws NotFound on an unknown task context name" do
            Orocos.run('process') do |process|
                assert_raises(Orocos::NotFound) { process.task("Bla") }
            end
        end
    end

    describe "#task_names" do
        it "enumerates the process own deployed task contexts" do
            Orocos.run('process') do |process|
                process.task_names.must_equal %w{process_Test}
            end
        end
    end

    describe "run" do
        it "can start a process with a prefix" do
            Orocos.run('process' => 'prefix') do |process|
                assert(Orocos::TaskContext.get('prefixprocess_Test'))
            end
        end

        it "can wait for the process to be running without a timeout" do
            Orocos.run 'process', :wait => true do
                Orocos.get 'process_Test'
            end
        end
    end

    describe "#setup_default_logger" do
        attr_reader :logger, :process
        before do
            orogen_project = OroGen::Spec::Project.new(Orocos.default_loader)
            orogen_deployment = orogen_project.deployment('test')
            @process = Orocos::Process.new('test', orogen_deployment)
            @logger = Orocos::RubyTasks::TaskContext.from_orogen_model(
                'test_logger', Orocos.default_loader.task_model_from_name('logger::Logger'))
        end

        describe "remote: true" do
            it "increases the last known index at each call" do
                process.setup_default_logger(logger, log_file_name: 'test', remote: true)
                assert_equal 'test.0.log', logger.file
                process.setup_default_logger(logger, log_file_name: 'test', remote: true)
                assert_equal 'test.1.log', logger.file
            end

            it "maintains the index per-file" do
                process.setup_default_logger(logger, log_file_name: 'foo', remote: true)
                assert_equal 'foo.0.log', logger.file
                process.setup_default_logger(logger, log_file_name: 'bar', remote: true)
                assert_equal 'bar.0.log', logger.file
            end
        end

        describe "remote: false" do
            attr_reader :log_dir
            before do
                @log_dir = make_tmpdir
            end
            it "takes the first non-existing index" do
                process.setup_default_logger(logger, log_file_name: 'test', log_dir: log_dir)
                assert_equal File.join(log_dir, "test.0.log"), logger.file
                process.setup_default_logger(logger, log_file_name: 'test', log_dir: log_dir)
                assert_equal File.join(log_dir, "test.0.log"), logger.file
                FileUtils.touch logger.file
                process.setup_default_logger(logger, log_file_name: 'test', log_dir: log_dir)
                assert_equal File.join(log_dir, "test.1.log"), logger.file
            end
        end
    end
end

