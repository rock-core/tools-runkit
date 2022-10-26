# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe Process do
        attr_reader :deployment_m, :task_m

        before do
            @loader = flexmock(OroGen::Loaders::Aggregate.new)
            @loader.should_receive(:find_deployment_binfile)
                   .explicitly.by_default

            project = OroGen::Spec::Project.new(@loader)
            project.default_task_superclass = OroGen::Spec::TaskContext.new(
                project, "base::Task", subclasses: false
            )
            @task_m = OroGen::Spec::TaskContext.new project, "test::Task"
            @deployment_m = OroGen::Spec::Deployment.new project, "test_deployment"
            @default_deployment_m = OroGen::Spec::Deployment.new project, "orogen_default_test__Task"
            @loader.register_task_context_model(@task_m)
            @loader.register_deployment_model(@deployment_m)
            @loader.register_deployment_model(@default_deployment_m)

            flexmock(Process)
                .should_receive(:command?)
                .and_return(true).by_default
        end

        describe "#initialize" do
            it "resolves the binfile" do
                @deployment_m.loader
                    .should_receive(:find_deployment_binfile)
                    .explicitly
                    .with("test_deployment")
                    .and_return("/path/to/file")
                process = Process.new(
                    "test", @deployment_m,
                    name_mappings: { "task" => "renamed_task" }
                )
                assert_equal "/path/to/file", process.binfile
            end
            it "applies the name mappings" do
                @deployment_m.task "task", @task_m
                process = Process.new(
                    "test", @deployment_m,
                    name_mappings: { "task" => "renamed_task"   }
                )
                assert_equal "renamed_task", process.mapped_name_for("task")
            end
        end

        describe ".partition_run_options" do
            it "partitions deployment names from task model names using Runkit.available_task_models" do
                deployments, models, options = Process.partition_run_options(
                    { "test_deployment" => "name2", "test::Task" => "name" },
                    loader: @loader
                )
                assert_equal Hash[deployment_m => "name2"], deployments
                assert_equal Hash[task_m => ["name"]], models
            end
            it "sets to nil the prefix for deployments that should not have one" do
                deployments, models, options = Process.partition_run_options(
                    "test_deployment", { "test::Task" => "name" }, loader: @loader
                )
                assert_equal Hash[deployment_m => nil], deployments
            end
            it "raises if an unexisting name is given" do
                assert_raises(OroGen::NotFound) do
                    Process.partition_run_options "does_not_exist", loader: @loader
                end
            end
            it "raises if a task model is given without a name" do
                assert_raises(ArgumentError) do
                    Process.partition_run_options "test::Task", loader: @loader
                end
            end
        end

        describe "parse_run_options" do
            describe "wrappers" do
                %I{valgrind gdb}.each do |wrapper|
                    it "uses an empty hash as default value if if no #{wrapper} options "\
                       "are explicitely given" do
                        result = Process.parse_run_options(
                            { "fast_source_sink" => "prefix_",
                              "orogen_runkit_tests::Echo" => "echo" },
                            wrapper => true
                        )

                        result.each do |*, spawn|
                            assert_equal({}, spawn[wrapper])
                        end
                    end

                    it "passes the #{wrapper} options to all deployments if "\
                       "given 'true'" do
                        result = Process.parse_run_options(
                            { "fast_source_sink" => "prefix_",
                              "orogen_runkit_tests::Echo" => "echo" },
                            "#{wrapper}": true,
                            "#{wrapper}_options": { "some" => "options" }
                        )
                        result.each do |*, spawn|
                            assert_equal({ "some" => "options" }, spawn[wrapper])
                        end
                    end

                    it "passes the #{wrapper} options to a select set of deployments "\
                       "if given a list of names" do
                        result = Process.parse_run_options(
                            { "fast_source_sink" => "prefix_",
                              "orogen_runkit_tests::Echo" => "echo" },
                            "#{wrapper}": ["prefix_fast_source_sink"],
                            "#{wrapper}_options": { "some" => "options" }
                        )

                        fast = result.find { |name, _| name == "prefix_fast_source_sink" }
                        assert_equal({ "some" => "options" }, fast.last[wrapper])
                        echo = result.find { |name, _| name == "echo" }
                        assert_nil echo.last[wrapper]
                    end

                    it "raises if the name array given as '#{wrapper}' "\
                       "contains non-existent deployments" do
                        assert_raises(ArgumentError) do
                            Process.parse_run_options(
                                { "fast_source_sink" => "prefix_",
                                  "orogen_runkit_tests::Echo" => "echo" },
                                "#{wrapper}": ["does_not_exist"]
                            )
                        end
                    end

                    it "passes per-deployment #{wrapper} options if given a hash" do
                        result = Process.parse_run_options(
                            { "fast_source_sink" => "prefix_",
                              "orogen_runkit_tests::Echo" => "echo" },
                            "#{wrapper}": {
                                "prefix_fast_source_sink" => { "some" => "options" },
                                "echo" => { "other" => "options" }
                            }
                        )

                        fast = result.find { |name, _| name == "prefix_fast_source_sink" }
                        assert_equal({ "some" => "options" }, fast.last[wrapper])
                        echo = result.find { |name, _| name == "echo" }
                        assert_equal({ "other" => "options" }, echo.last[wrapper])
                    end
                end
            end
        end

        describe "#spawn" do
            attr_reader :process
            before do
                @process = create_processes("fast_source_sink").first
            end

            it "starts a new process" do
                process.spawn
                assert process.wait_running(10)
                process.task("fast_source")
                assert process.alive?
                assert process.running?
            end

            it "renames single tasks" do
                process.map_name "fast_source", "foobar"
                process.spawn
                assert process.wait_running(10)
                assert process.task("foobar")
            end
        end

        describe "#load_and_validate_ior_message" do
            attr_reader :process
            before do
                @process = create_processes("fast_source_sink").first
            end

            it "loads and validates the ior message when it is valid" do
                message = JSON.dump(
                    { fast_source: "IOR:123456", fast_sink: "IOR:7890" }
                )
                result = process.load_and_validate_ior_message(message)
                assert_equal(result, JSON.parse(message))
            end

            it "returns nil when the ior message is not parseable" do
                # Missing the `}`
                message = "{\"process_Test\": \"IOR:123456\""
                result = process.load_and_validate_ior_message(message)
                assert_nil(result)
            end

            it "raises invalid ior message when a task is not included in the ior message" do
                message = "{\"another_process\": \"IOR:123456\"}"
                error = assert_raises(InvalidIORMessage) do
                    process.load_and_validate_ior_message(message)
                end
                expected_error = InvalidIORMessage.new(
                    "the following tasks were present on the ior message but werent in the " \
                    "process task names: [\"another_process\"]"
                )
                assert_equal(expected_error.message, error.message)
            end
        end

        describe "#wait_running" do
            attr_reader :process
            before do
                @message = JSON.dump(
                    { fast_source: "IOR:123456", fast_sink: "IOR:7890" }
                )
                @process = create_processes("fast_source_sink").first
                flexmock(process).should_receive(alive?: true).by_default
                @ior_r, @ior_w = IO.pipe
            end

            after do
                @ior_r.close unless @ior_r.closed?
                @ior_w.close unless @ior_w.closed?
            end

            it "resolves the ior mappings" do
                @ior_w.write(@message)
                @ior_w.close
                result = process.wait_running(0, channel: @ior_r)
                assert_equal(JSON.parse(@message), result)
            end

            it "stops waiting after the timeout was reached" do
                assert_nil process.wait_running(0.1, channel: @ior_r)
            end

            it "parses the message correctly even when it was first received partially" do
                @ior_w.write @message.slice(0, 4)
                assert_nil process.wait_running(0, channel: @ior_r)
                @ior_w.write @message.slice(4, @message.length)
                assert_nil process.wait_running(0, channel: @ior_r)
                @ior_w.close
                result = process.wait_running(0.1, channel: @ior_r)
                assert_equal(JSON.parse(@message), result)
            end

            it "stops waiting if the process has crashed" do
                flexmock(process)
                    .should_receive(:alive?)
                    .and_return(true, false)
                e = assert_raises(NotFound) { process.wait_running(2, channel: @ior_r) }
                assert_equal("fast_source_sink was started but crashed", e.message)
            end

            it "raises if the process is dead after waiting" do
                flexmock(process).should_receive(alive?: false)
                e = assert_raises(NotFound) { process.wait_running(2, channel: @ior_r) }
                assert_equal("cannot get a running fast_source_sink module", e.message)
            end
        end

        describe "#resolve_all_tasks" do
            attr_reader :process
            before do
                @process = create_processes({ "fast_source_sink" => "prefix_" }).first
            end

            it "returns all the process tasks when their ior is registered" do
                process.spawn
                assert process.wait_running(10)
                result = process.resolve_all_tasks
                assert_equal(
                    { "prefix_fast_sink" => "prefix_fast_sink",
                      "prefix_fast_source" => "prefix_fast_source" },
                    result.transform_values(&:name)
                )
            end

            it "raises if the process is not ready" do
                e = assert_raises(IORNotRegisteredError) do
                    process.resolve_all_tasks
                end
                assert_equal("no IOR is registered for prefix_fast_source", e.message)
            end
        end

        describe "#kill" do
            attr_reader :process

            before do
                @process = start("fast_source_sink").first
            end

            it "stops a running process" do
                process.kill
                process.join
                refute process.alive?, "process has been killed but alive? returns true"
            end

            it "stops running tasks" do
                task = process.task("fast_source")
                task.configure
                task.start

                state = nil
                flexmock(::Process)
                    .should_receive(:kill)
                    .with(->(*) { state = task.read_toplevel_state }, Integer)
                    .pass_thru

                process.kill
                assert_equal :PRE_OPERATIONAL, state
                process.join
            end

            it "does not attempt to stop the task if cleanup is false" do
                task = process.task("fast_source")
                task.configure
                task.start

                state = nil
                flexmock(::Process)
                    .should_receive(:kill)
                    .with(->(*) { state = task.read_toplevel_state }, Integer)
                    .pass_thru

                process.kill(cleanup: false)
                assert_equal :RUNNING, state
                process.join # to avoid teardown warnings
            end

            it "uses SIGINT by default" do
                flexmock(::Process)
                    .should_receive(:kill)
                    .with("SIGINT", process.pid)
                    .pass_thru

                process.kill
                process.join # to avoid teardown warnings
            end

            it "uses SIGKILL if hard is true" do
                flexmock(::Process)
                    .should_receive(:kill)
                    .with("SIGKILL", process.pid)
                    .pass_thru

                process.kill(hard: true)
                process.join # to avoid teardown warnings
            end
        end

        describe "#task" do
            it "gets a reference on a deployed task context by name" do
                process = start({ "fast_source_sink" => "prefix_" }).first
                assert process.task("prefix_fast_source")
            end

            it "throws NotFound on an unknown task context name" do
                process = start({ "fast_source_sink" => "prefix_" }).first
                assert_raises(NotFound) { process.task("Bla") }
            end
        end

        describe "#task_names" do
            it "enumerates the process own deployed task contexts" do
                process = start({ "fast_source_sink" => "prefix_" }).first
                assert_equal(
                    %w[prefix_fast_sink prefix_fast_source],
                    process.task_names.sort
                )
            end
        end

    end
end
