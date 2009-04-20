$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'set'

MiniTest::Unit.autorun

describe "Orocos module features" do
    TEST_DIR = File.dirname(__FILE__)
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should be able to enumerate the name of all registered task contexts" do
        Orocos.task_names.must_equal []
        deployments = %w{process simple_source simple_sink}
        tasks       = %w{process_Test simple_source_source simple_sink_sink}
        start_processes(*deployments) do |*processes|
            Orocos.task_names.to_set.
                must_equal tasks.to_set
        end
    end
end


