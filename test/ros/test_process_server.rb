$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

include Test::Unit::Assertions

describe Orocos::ROS::ProcessServer do
    include Orocos
    include Orocos::Spec

    describe "loading" do
        Orocos.initialize
        Orocos::ROS.load(File.join(DATA_DIR,"ros_test","specs"))

        process_server = Orocos::ROS::ProcessServer.new
        launcher = process_server.load_orogen_deployment('test')
        assert_equal launcher.name, 'test'

        process_server.start("test_launcher", "test")

        assert_raise ArgumentError do
            process_server.start("test_launcher", "test")
        end

        process_server.stop("test_launcher")
    end
end

describe Orocos::ROS::Launcher do 
    include Orocos
    include Orocos::Spec

    describe "spawn_and_kill" do 
        Orocos.initialize
        Orocos::ROS.load(File.join(DATA_DIR,"ros_test","specs"))

        _,path = Orocos::ROS.available_projects['manipulator_config']
        p = Orocos::ROS::Generation::Project.load(path)
        model = p.ros_launchers[0]

        launcher = Orocos::ROS::Launcher.new(nil, "test", model)
        assert launcher.spawn
        assert launcher.alive?

        launcher.each_task do |p|
            puts "task: #{p}"
        end

        launcher.kill
    end
end
