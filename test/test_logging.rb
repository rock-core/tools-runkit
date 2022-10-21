# frozen_string_literal: true

require "orocos/test"
module Orocos
    describe "logging" do
        attr_reader :orogen_project, :orogen_deployment, :process
        before do
            @orogen_project = OroGen::Spec::Project.new(Orocos.default_loader)
            @orogen_deployment = orogen_project.deployment("test")
            @process = Process.new("test", orogen_deployment)
            flexmock(process)
        end

        def create_mock_deployment
            task_model = OroGen::Spec::TaskContext.new(orogen_project)
            yield(task_model) if block_given?
            orogen_deployment.task "test", task_model

            default_logger = RubyTasks::TaskContext.from_orogen_model(
                "test_logger", Orocos.default_loader.task_model_from_name("logger::Logger")
            )
            flexmock(default_logger).should_receive(:log).by_default
            ruby_task = RubyTasks::TaskContext.from_orogen_model(
                "test", task_model
            )

            register_allocated_ruby_tasks(default_logger, ruby_task)
            process.should_receive(:task).with("test").and_return(ruby_task)
            process.default_logger = default_logger

            [default_logger, ruby_task]
        end

        it "returns an empty set if the process has no default logger" do
            process.default_logger = false
            assert_equal Set.new, Orocos.log_all_process_ports(process)
        end

        it "calls the process' #setup_default_logger method with the value returned by process.default_logger" do
            default_logger, _ = create_mock_deployment
            process.should_receive(:setup_default_logger)
                   .with(default_logger, log_file_name: "testfile")
                   .once
                   .pass_thru
            Orocos.log_all_process_ports(process, log_file_name: "testfile")
        end

        it "configures and starts a pre-operational logger" do
            default_logger, _ = create_mock_deployment
            Orocos.log_all_process_ports(process)
            assert default_logger.running?
        end

        it "starts a stopped logger" do
            default_logger, _ = create_mock_deployment
            default_logger.configure
            Orocos.log_all_process_ports(process)
            assert default_logger.running?
        end

        it "does not change the logger's state if it is already running" do
            default_logger, _ = create_mock_deployment
            default_logger.configure
            default_logger.start
            Orocos.log_all_process_ports(process)
            assert default_logger.running?
        end

        it "setups logging for the task's output ports" do
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/int32_t"
            end

            default_logger.should_receive(:log)
                          .with(ruby_task.port("state")).once
            default_logger.should_receive(:log)
                          .with(ruby_task.test).once
            assert_equal Set[%w[test state], %w[test test]],
                         Orocos.log_all_process_ports(process)
        end

        it "excludes a task whose name is not matched by the tasks object" do
            matcher = flexmock do |m|
                m.should_receive(:===).and_return { |task_name| task_name != "test" }
            end
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/int32_t"
            end
            default_logger.should_receive(:log).never
            assert_equal Set.new, Orocos.log_all_process_ports(process, tasks: matcher)
        end

        it "includes a task whose name is matched by the tasks object" do
            matcher = flexmock do |m|
                m.should_receive(:===).and_return { |task_name| task_name == "test" }
            end
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/int32_t"
            end
            default_logger.should_receive(:log)
                          .with(ruby_task.port("state")).once
            default_logger.should_receive(:log)
                          .with(ruby_task.test).once
            assert_equal Set[%w[test test], %w[test state]],
                         Orocos.log_all_process_ports(process, tasks: matcher)
        end

        it "excludes a port whose name is matched by the exclude_ports object" do
            matcher = flexmock do |m|
                m.should_receive(:===).and_return { |port_name| port_name == "state" }
            end
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/int32_t"
            end
            default_logger.should_receive(:log)
                          .with(ruby_task.port("state")).never
            default_logger.should_receive(:log)
                          .with(ruby_task.test).once
            assert_equal Set[%w[test test]],
                         Orocos.log_all_process_ports(process, exclude_ports: matcher)
        end

        it "excludes a port whose type name is matched by the exclude_types object" do
            matcher = flexmock do |m|
                m.should_receive(:===).and_return { |type_name| type_name == "/double" }
            end
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/double"
            end
            default_logger.should_receive(:log)
                          .with(ruby_task.port("state")).once
            default_logger.should_receive(:log)
                          .with(ruby_task.test).never
            assert_equal Set[%w[test state]],
                         Orocos.log_all_process_ports(process, exclude_types: matcher)
        end

        it "excludes a port for which the block returns false" do
            default_logger, ruby_task = create_mock_deployment do |task_m|
                task_m.output_port "test", "/double"
            end
            default_logger.should_receive(:log)
                          .with(ruby_task.port("state")).never
            default_logger.should_receive(:log)
                          .with(ruby_task.test).once
            assert_equal Set[%w[test test]],
                         Orocos.log_all_process_ports(process) { |port| port.name != "state" }
        end
    end
end
