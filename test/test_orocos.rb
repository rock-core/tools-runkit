$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'set'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos do
    include Orocos::Spec

    it "should be able to enumerate the name of all registered task contexts" do
        Orocos::CORBA.cleanup
        Orocos.task_names.must_equal []
        deployments = %w{process simple_source simple_sink}
        tasks       = %w{/process_Test /simple_source_source /fast_sink /fast_source /simple_sink_sink}.
            map { |name| Orocos::CORBA.map_to_namespace(name) }
        Orocos.run(*deployments) do |*processes|
            Orocos.task_names.to_set.
                must_equal tasks.to_set
        end
        Orocos.task_names.must_equal []
    end

    describe "deployment_model_from_name" do
        it "should be able to load a model by name" do
            model = Orocos.deployment_model_from_name 'echo'
            assert_equal Orocos.master_project.using_task_library('echo').find_deployment_by_name('echo'), model
        end
        it "should raise NotFound if an unknown deployment is requested" do
            assert_raises(Orocos::NotFound) { Orocos.deployment_model_from_name 'bla' }
        end
    end

    describe "deployed_task_model_from_name" do
        it "should be able to load a model by name" do
            model = Orocos.deployed_task_model_from_name 'echo_Echo'

            expected_model = Orocos.master_project.using_task_library('echo').
                find_deployment_by_name('echo').
                find_task_by_name('echo_Echo')
            assert_equal expected_model, model
        end
        it "should raise NotFound if an unknown deployment is requested" do
            assert_raises(Orocos::NotFound) { Orocos.deployed_task_model_from_name 'bla' }
        end
        it "should raise NotFound if a wrong task name - deployment name combination is given" do
            assert_raises(Orocos::NotFound) { Orocos.deployed_task_model_from_name 'bla', 'echo_Echo' }
        end
        it "should raise NotFound if an unknown deployment name is given" do
            assert_raises(Orocos::NotFound) { Orocos.deployed_task_model_from_name 'bla', 'wront deployment' }
        end
    end
end


