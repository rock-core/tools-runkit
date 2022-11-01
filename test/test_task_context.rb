# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe TaskContext do
        it "gives access to an existing remote task" do
            start_and_get({ "orogen_runkit_tests::EmptyTask" => "empty_task" },
                          "empty_task").ping
        end

        it "raises if the task does not exist anymore" do
            task = new_ruby_task_context
            task.dispose
            assert_raises(CORBA::ComError) do
                TaskContext.new(task.ior, model: task.model)
            end
        end

        it "returns equality for two TaskContext that point to the same actual task" do
            task1 = new_ruby_task_context
            task2 = TaskContext.new(task1.ior, name: "test")
            assert_equal task1, task2
        end

        it "reports that a port exists" do
            task = new_remote_task_context do |t|
                t.create_input_port "in", "/base/Vector3d"
            end
            assert task.port?("in")
        end

        it "reports that a port does not exist" do
            task = new_remote_task_context
            refute task.port?("does_not_exist")
        end

        it "enumerates its ports" do
            in_p, out_p = nil
            task = new_remote_task_context do |t|
                in_p = t.create_input_port "in", "/base/Vector3d"
                out_p = t.create_output_port "out", "/base/Vector3d"
            end

            assert_equal [in_p], task.each_input_port.to_a
            assert_equal [out_p, task.port("state")],
                         task.each_output_port.sort_by(&:name)
        end

        it "raises if a port does not exist" do
            task = new_remote_task_context
            assert_raises(Runkit::InterfaceObjectNotFound) { task.port("does_not_exist") }
        end

        it "raises either CORBA::ComError or TimeoutError when #port is called "\
           "on a dead remote process" do
            process = start({ "orogen_runkit_tests::Echo" => "echo" }).first
            task = process.task("echo")

            process.kill
            process.join
            assert_raises(Runkit::CORBA::ComError, Runkit::CORBA::TimeoutError) do
                task.port("out0")
            end
        end

        it "allows passing the `distance` argument to state_reader" do
            task = start_and_get({ "orogen_runkit_tests::EmptyTask" => "empty" }, "empty")
            state_port = task.port("state")
            flexmock(task).should_receive(:port).with("state").and_return(state_port)

            distance = flexmock
            flexmock(state_port)
                .should_receive(:reader).with(hsh(distance: distance)).pass_thru
            task.state_reader distance: distance
        end

        it "manipulates the task state machine and read its state" do
            task = start_and_get({ "orogen_runkit_tests::EmptyTask" => "empty" }, "empty")
            state_r = task.state_reader type: :buffer, size: 20

            assert_equal :PRE_OPERATIONAL, task.read_toplevel_state
            task.configure
            assert_equal(:STOPPED, task.read_toplevel_state)
            task.start
            assert_equal(:RUNNING, task.read_toplevel_state)
            task.stop
            assert_equal(:STOPPED, task.read_toplevel_state)

            expected = %I[PRE_OPERATIONAL STOPPED RUNNING STOPPED]
            actual = expected.map { read_one_sample(state_r) }
            assert_equal expected, actual
        end

        it "raises either CORBA::ComError or CORBA::TimeoutError when state-related "\
           "operations are called on a dead process" do
            process = start({ "orogen_runkit_tests::EmptyTask" => "empty" }).first
            task = process.task("empty")

            process.kill
            process.join
            assert_raises(Runkit::CORBA::ComError, Runkit::CORBA::TimeoutError) do
                task.read_toplevel_state
            end

            # TimeoutError is due to a race condition on ORB shutdown. After the
            # call to 'state', there is no more race condition and this should
            # always be a ComError
            assert_raises(Runkit::CORBA::ComError) { task.start }
        end

        it "should be pretty-printable" do
            operations = start_and_get(
                { "orogen_runkit_tests::Operations" => "ops" }, "ops"
            )
            ports = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")

            PP.pp(operations, +"")
            PP.pp(ports, +"")
        end

        it "records its state trace when using extended state support" do
            t = start_and_get(
                { "orogen_runkit_tests::StateTransitions" => "states" }, "states"
            )
            state_r = t.state_reader type: :buffer, size: 20

            t.configure
            t.start
            t.do_custom_runtime
            t.do_custom_error
            t.do_recover
            t.do_custom_exception
            t.reset_exception

            # Note: we don't have state_pre_operational as we already read it
            # once
            expected =
                %I[PRE_OPERATIONAL STOPPED RUNNING CUSTOM_RUNTIME
                   CUSTOM_ERROR RUNNING CUSTOM_EXCEPTION PRE_OPERATIONAL]
            expected.each_with_index do |expected_state, i|
                assert_equal expected_state, read_one_sample(state_r),
                             "#{i}-th state failed"
            end
        end

        it "properly resolves custom states if the exact orogen model is set after "\
           "the state reader was created" do
            full_task = start_and_get(
                { "orogen_runkit_tests::StateTransitions" => "test" }, "test"
            )
            t = TaskContext.new(full_task.ior, name: "test")
            state_r = t.state_reader type: :buffer, size: 20
            t.model = full_task.model

            t.configure
            t.start
            t.do_custom_runtime
            t.do_custom_error
            t.do_recover
            t.do_custom_exception
            t.reset_exception

            # Note: we don't have state_pre_operational as we already read it
            # once
            expected =
                %I[PRE_OPERATIONAL STOPPED RUNNING CUSTOM_RUNTIME
                   CUSTOM_ERROR RUNNING CUSTOM_EXCEPTION PRE_OPERATIONAL]
            expected.each_with_index do |expected_state, i|
                assert_equal expected_state, read_one_sample(state_r),
                             "#{i}-th state failed"
            end
        end

        it "handles uncaught exceptions in a nice way" do
            t = start_and_get({ "orogen_runkit_tests::Uncaught" => "uncaught" },
                              "uncaught")

            assert_raises(Runkit::StateTransitionFailed) { t.configure }
            assert_equal :EXCEPTION, t.read_toplevel_state
            t.reset_exception

            t.exception_level = 1
            t.configure
            assert_raises(Runkit::StateTransitionFailed) { t.start }
            assert_equal :EXCEPTION, t.read_toplevel_state
            t.reset_exception
            assert_equal :PRE_OPERATIONAL, t.read_toplevel_state
            t.exception_level = 2
            t.configure
            t.start
            assert_toplevel_state_becomes :EXCEPTION, t

            t.reset_exception
            t.exception_level = 3
            t.configure
            t.start
            t.do_runtime_error
            assert_toplevel_state_becomes :EXCEPTION, t
        end

        it "traces custom states trace when using extended state support" do
            t = start_and_get(
                { "orogen_runkit_tests::StateTransitions" => "states" }, "states"
            )

            state_r = t.state_reader type: :buffer, size: 20

            t.configure
            t.start
            t.do_custom_runtime
            t.do_nominal_running
            t.do_custom_error
            t.do_recover
            t.do_custom_exception
            t.reset_exception

            expected = %I[PRE_OPERATIONAL STOPPED RUNNING CUSTOM_RUNTIME RUNNING
                          CUSTOM_ERROR RUNNING CUSTOM_EXCEPTION PRE_OPERATIONAL]

            actual = expected.map { read_one_sample(state_r) }
            assert_equal expected, actual
        end

        it "reports its model name" do
            t = start_and_get({ "orogen_runkit_tests::Echo" => "echo" }, "echo")
            assert_equal "orogen_runkit_tests::Echo", t.getModelName
        end

        def new_remote_task_context
            task = new_ruby_task_context
            yield(task) if block_given?

            TaskContext.new(task.ior, name: task.name)
        end
    end
end
