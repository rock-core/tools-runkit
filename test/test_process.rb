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
            assert_equal Hash[task_m => 'name'], models
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
end

