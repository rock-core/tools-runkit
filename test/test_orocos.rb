$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'set'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe "Orocos module features" do
    include Orocos::Spec

    it "should be able to enumerate the name of all registered task contexts" do
        Orocos::CORBA.cleanup
        Orocos.task_names.must_equal []
        deployments = %w{process simple_source simple_sink}
        tasks       = %w{process_Test simple_source_source simple_sink_sink}
        Orocos::Process.spawn(*deployments) do |*processes|
            Orocos.task_names.to_set.
                must_equal tasks.to_set
        end
        Orocos.task_names.must_equal []
    end
end


