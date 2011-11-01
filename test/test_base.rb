$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe "the Orocos module" do
    include Orocos::Spec

    it "should allow listing task names" do
        Orocos.task_names
    end

    it "should be able to list all available task libraries" do
        test_deployments = %w{configurations echo operations process simple_sink simple_source states system_test uncaught}
        assert_equal test_deployments.sort, Orocos.available_task_libraries.keys.sort

        pkgconfig_names = test_deployments.
            map { |name| "#{name}-tasks-#{Orocos.orocos_target}" }.
            sort
        assert_equal pkgconfig_names, Orocos.available_task_libraries.values.map(&:name).sort
    end

    it "should be able to list all available task models" do
        assert_equal 'echo', Orocos.available_task_models['echo::Echo']
        assert_equal 'process', Orocos.available_task_models['process::Test']
        assert_equal 'simple_sink', Orocos.available_task_models['simple_sink::sink']
    end
end

