# frozen_string_literal: true

require "orocos/test"

describe Orocos::ROS::ProcessManager do
    attr_reader :loader
    before do
        @loader = OroGen::ROS::DefaultLoader.new
        loader.search_path << File.join(data_dir, "ros_test", "specs")
    end

    it "should be able to start a node" do
        process_server = Orocos::ROS::ProcessManager.new(loader)
        launcher = process_server.load_orogen_deployment("test")
        assert_equal launcher.name, "test"

        process_server.start("test_launcher", "test")

        assert_raise ArgumentError do
            process_server.start("test_launcher", "test")
        end

        process_server.stop("test_launcher")
    end
end

describe Orocos::ROS::LauncherProcess do
    attr_reader :loader
    before do
        @loader = OroGen::ROS::DefaultLoader.new
        loader.search_path << File.join(data_dir, "ros_test", "specs")
    end

    it "should be able to spawn and kill a node" do
        project = loader.load_project_from_name("manipulator_config")
        model = project.ros_launchers[0]

        launcher = Orocos::ROS::LauncherProcess.new(nil, "test", model)
        assert launcher.spawn
        assert launcher.alive?

        launcher.each_task do |p|
            puts "task: #{p}"
        end

        launcher.kill
    end
end
