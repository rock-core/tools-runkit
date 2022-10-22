# frozen_string_literal: true

require "runkit/test"

describe Runkit::TaskContext do
    it "should be possible to create one directly" do
        Runkit.run("process") do
            ior = Runkit.name_service.ior("process_Test")
            assert(t1 = Runkit::TaskContext.new(ior))
        end
    end

    it "should raise NotFound on unknown task contexts" do
        assert_raises(Runkit::NotFound) { Runkit::TaskContext.get("Bla_Blo") }
    end

    it "should check equality based on CORBA reference" do
        Runkit.run("process") do
            assert(t1 = Runkit::TaskContext.get("process_Test"))
            assert(t2 = Runkit::TaskContext.get("process_Test"))
            refute_equal(t1.object_id, t2.object_id)
            assert_equal(t1, t2)
        end
    end

    it "should give access to its own process if it is known" do
        Runkit.run("simple_source") do |process|
            source = Runkit::TaskContext.get("simple_source_source")
            assert_same process, source.process
        end
    end

    it "should allow enumerating its ports" do
        Runkit.run("simple_source", "simple_sink") do
            source = Runkit::TaskContext.get("simple_source_source")
            sink   = Runkit::TaskContext.get("simple_sink_sink")

            expected_ports = %w{cycle cycle_struct out0 out1 out2 out3 state}
                             .map { |name| source.port(name) }
            source.enum_for(:each_port).map(&:name).to_set.must_equal expected_ports.map(&:name).to_set
            source.enum_for(:each_port).sort_by(&:name).must_equal expected_ports.sort_by(&:name)
            expected_ports = %w{cycle in0 in1 in2 in3 state}
                             .map { |name| sink.port(name) }
            sink.enum_for(:each_port).map(&:name).to_set.must_equal expected_ports.map(&:name).to_set
            sink.enum_for(:each_port).sort_by(&:name).must_equal expected_ports.sort_by(&:name)
        end
    end

    it "should allow getting its ports" do
        Runkit.run("simple_source", "simple_sink") do
            source = Runkit::TaskContext.get("simple_source_source")
            sink   = Runkit::TaskContext.get("simple_sink_sink")

            assert(source_p = source.port("cycle"))
            source_p.must_be_kind_of(Runkit::OutputPort)
            source_p.name.must_equal("cycle")
            source_p.task.must_equal(source)
            source_p.runkit_type_name.must_equal("/int32_t")

            assert(sink_p = sink.port("cycle"))
            sink_p.must_be_kind_of(Runkit::InputPort)
            sink_p.name.must_equal("cycle")
            sink_p.task.must_equal(sink)
            sink_p.runkit_type_name.must_equal("/int32_t")
        end
    end

    it "should allow to check an operation availability" do
        Runkit.run("states") do
            t = Runkit::TaskContext.get "states_Task"
            assert(!t.has_operation?("does_not_exist"))
            assert(t.has_operation?("do_runtime_error"))
        end
    end

    it "should allow to check a port availability" do
        Runkit.run("simple_source") do
            t = Runkit::TaskContext.get "simple_source_source"
            assert(!t.has_port?("does_not_exist"))
            assert(t.has_port?("cycle"))
        end
    end

    it "should raise NotFound if a port does not exist" do
        Runkit.run("simple_source") do
            task = Runkit::TaskContext.get("simple_source_source")
            assert_raises(Runkit::InterfaceObjectNotFound) { task.port("does_not_exist") }
        end
    end

    it "should raise either CORBA::ComError or TimeoutError when #port is called "\
       "on a dead remote process" do
        Runkit.run("simple_source") do |p|
            source = Runkit::TaskContext.get("simple_source_source")
            p.kill
            assert_raises(Runkit::CORBA::ComError, Runkit::CORBA::TimeoutError) do
                source.port("cycle")
            end
        end
    end

    it "should allow getting an operation object" do
        Runkit.run "echo" do
            echo = Runkit::TaskContext.get("echo_Echo")
            m = echo.operation(:write)
            assert_equal "write", m.name
            assert_equal ["/int32_t"], m.return_spec
            assert_equal [["value", "value_arg", "/int32_t"]], m.arguments_spec
        end
    end

    # it "should allow getting an operation documentation" do
    #     Runkit.run 'echo' do
    #         echo = Runkit::TaskContext.get('echo_Echo')
    #         m = echo.operation(:write)
    #         assert_equal "write_method", m.description
    #     end
    # end

    it "should raise NotFound on an unknown operation object" do
        Runkit.run "echo" do
            echo = Runkit::TaskContext.get("echo_Echo")
            assert_raises(Runkit::InterfaceObjectNotFound) { echo.operation(:unknown) }
        end
    end

    it "should raise CORBA::ComError when the process "\
       "crashed during a operation call" do
        Runkit.run "echo" do
            echo = Runkit::TaskContext.get("echo_Echo")
            assert_raises(Runkit::CORBA::ComError) do
                echo.operation(:kill).callop
            end
        end
    end

    it "should raise either CORBA::ComError or CORBA::TimeoutError when #operation "\
       "has communication errors" do
        Runkit.run "echo" do |p|
            echo = Runkit::TaskContext.get("echo_Echo")
            p.kill
            assert_raises(Runkit::CORBA::ComError, Runkit::CORBA::TimeoutError) do
                echo.operation(:write)
            end
        end
    end

    it "should be able to manipulate the task state machine and read its state" do
        Runkit.run("simple_source") do
            source = Runkit::TaskContext.get("simple_source_source")
            assert_equal(:PRE_OPERATIONAL, source.state)
            assert_raises(Runkit::StateTransitionFailed) { source.start }
            assert(!source.ready?)
            assert(!source.running?)
            assert(!source.error?)

            source.configure
            assert_equal(:STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)
            assert(!source.error?)

            source.start
            assert_equal(:RUNNING, source.state)
            assert(source.ready?)
            assert(source.running?)
            assert(!source.error?)

            source.stop
            assert_equal(:STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)
            assert(!source.error?)
        end
    end

    it "should raise either CORBA::ComError or CORBA::TimeoutError when state-related "\
       "operations are called on a dead process" do
        Runkit.run("simple_source") do |p|
            source = Runkit::TaskContext.get("simple_source_source")
            assert source.state
            p.kill
            assert_raises(Runkit::CORBA::ComError, Runkit::CORBA::TimeoutError) do
                source.state
            end
            # TimeoutError is due to a race condition on ORB shutdown. After the
            # call to 'state', there is no more race condition and this should
            # always be a ComError
            assert_raises(Runkit::CORBA::ComError) { source.start }
        end
    end

    it "should be pretty-printable" do
        Runkit.run("echo", "process") do
            source = Runkit::TaskContext.get("echo_Echo")
            process = Runkit::TaskContext.get("process_Test")
            PP.pp(source, "")
            PP.pp(process, "")
        end
    end

    it "should allow to record its state trace when using extended state support" do
        Runkit.run("states") do |p|
            t = Runkit::TaskContext.get("states_Task")

            state = t.port("state").reader type: :buffer, size: 20, init: true

            # First check the nominal state changes
            t.configure
            t.start
            t.stop
            t.cleanup
            sleep 0.05
            assert_equal Runkit::TaskContext::STATE_PRE_OPERATIONAL, state.read
            assert_equal Runkit::TaskContext::STATE_STOPPED, state.read
            assert_equal Runkit::TaskContext::STATE_RUNNING, state.read
            assert_equal Runkit::TaskContext::STATE_STOPPED, state.read
            assert_equal Runkit::TaskContext::STATE_PRE_OPERATIONAL, state.read

            # Then test the error states
            t.configure
            t.start
            t.do_recover
            t.do_runtime_error
            t.do_recover
            t.do_runtime_error
            t.do_recover
            t.do_exception
            t.reset_exception
            sleep 0.05

            # Note: we don't have state_pre_operational as we already read it
            # once
            expected = [
                Runkit::TaskContext::STATE_STOPPED,
                Runkit::TaskContext::STATE_RUNNING,
                Runkit::TaskContext::STATE_RUNTIME_ERROR,
                Runkit::TaskContext::STATE_RUNTIME_ERROR,
                Runkit::TaskContext::STATE_RUNNING,
                Runkit::TaskContext::STATE_RUNTIME_ERROR,
                Runkit::TaskContext::STATE_RUNTIME_ERROR,
                Runkit::TaskContext::STATE_RUNNING,
                Runkit::TaskContext::STATE_EXCEPTION,
                Runkit::TaskContext::STATE_EXCEPTION,
                Runkit::TaskContext::STATE_PRE_OPERATIONAL
            ]
            actual = expected.map { state.read }
            assert_equal expected, actual
        end
    end

    it "should handle uncaught exceptions in a nice way" do
        Runkit.run("uncaught") do
            t = Runkit::TaskContext.get("Uncaught")

            assert_raises(Runkit::StateTransitionFailed) { t.configure }
            t.reset_exception
            t.exception_level = 1
            t.configure

            assert_raises(Runkit::StateTransitionFailed) { t.start }
            t.reset_exception
            t.exception_level = 2
            t.start

            sleep 0.1
            assert(t.exception?)

            t.reset_exception
            t.exception_level = 3
            t.configure
            t.start
            sleep 0.2
            assert(t.running?)
            t.do_runtime_error
            sleep 0.2
            assert(t.exception?)
        end
    end

    it "should allow to restart after an exception error if resetException has been called" do
        Runkit.run("states") do
            t = Runkit::TaskContext.get("states_Task")

            t.configure
            t.start
            t.do_exception
            t.reset_exception
            t.configure
            t.start
        end
    end

    it "should allow to trace custom states trace when using extended state support" do
        Runkit.run("states") do
            t = Runkit::TaskContext.get("states_Task")

            state = t.state_reader type: :buffer, size: 20

            sleep 0.05
            assert !t.ready?, "expected to be in state PRE_OPERATIONAL but is in #{t.state}"
            assert !t.running?, "expected to be in state PRE_OPERATIONAL but is in #{t.state}"
            assert !t.error?, "expected to be in state PRE_OPERATIONAL but is in #{t.state}"
            t.configure
            sleep 0.05
            assert t.ready?, "expected to be in state STOPPED but is in #{t.state} (RTT reports #{t.rtt_state})"
            assert !t.running?, "expected to be in state STOPPED but is in #{t.state}"
            assert !t.error?, "expected to be in state STOPPED but is in #{t.state}"
            t.start
            sleep 0.05
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_runtime
            sleep 0.05
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_nominal_running
            sleep 0.05
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_error
            sleep 0.05
            assert t.ready?
            assert t.running?
            assert t.error?
            assert !t.exception?
            assert !t.fatal_error?
            t.do_recover
            sleep 0.05
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_exception
            sleep 0.05
            assert t.ready?
            assert !t.running?
            assert t.error?
            assert t.exception?
            t.reset_exception
            sleep 0.05
            assert !t.ready?
            assert !t.running?
            assert !t.error?

            assert_equal :PRE_OPERATIONAL, state.read
            assert_equal :STOPPED, state.read
            assert_equal :RUNNING, state.read
            assert_equal :CUSTOM_RUNTIME, state.read
            assert_equal :RUNNING, state.read
            assert_equal :CUSTOM_ERROR, state.read
            assert_equal :RUNNING, state.read
            assert_equal :CUSTOM_EXCEPTION, state.read
            assert_equal :PRE_OPERATIONAL, state.read
        end
    end

    it "should report its model name" do
        Runkit.run("echo") do
            t = Runkit::TaskContext.get "echo_Echo"
            assert_equal("echo::Echo", Runkit::TaskContext.get("echo_Echo").getModelName)
        end
    end

    it "should allow getting its model even though its process is unknown" do
        Runkit.run("echo") do
            t = Runkit::TaskContext.get "echo_Echo"

            assert t.process
            t.instance_variable_set :@process, nil
            t.instance_variable_set :@info, nil
            t.instance_variable_set :@model, nil
            assert t.model
            assert_equal("echo::Echo", t.model.name)
            assert !t.process
        end
    end

    describe "#input_port" do
        attr_reader :task, :in_p, :out_p
        before do
            @task = new_ruby_task_context "test"
            @in_p = task.create_input_port "in", "/double"
            @out_p = task.create_output_port "out", "/double"
        end
        it "returns the input port object if there is one" do
            assert_equal in_p, task.input_port("in")
        end
        it "raises NotFound if the port is an input port" do
            assert_raises(Runkit::InterfaceObjectNotFound) { task.input_port "out" }
        end
        it "raises NotFound if the port does not exist" do
            assert_raises(Runkit::InterfaceObjectNotFound) { task.input_port "does_not_exist" }
        end
    end

    describe "#output_port" do
        attr_reader :task, :in_p, :out_p
        before do
            @task = new_ruby_task_context "test"
            @in_p = task.create_input_port "in", "/double"
            @out_p = task.create_output_port "out", "/double"
        end
        it "returns the output port object if there is one" do
            assert_equal out_p, task.output_port("out")
        end
        it "raises NotFound if the port is an input port" do
            assert_raises(Runkit::InterfaceObjectNotFound) { task.output_port "in" }
        end
        it "raises NotFound if the port does not exist" do
            assert_raises(Runkit::InterfaceObjectNotFound) { task.output_port "does_not_exist" }
        end
    end

    describe "#model" do
        attr_reader :task
        before do
            start "echo"
            @task = Runkit.name_service.get "echo_Echo"
            task.process = nil
            task.model = nil
        end

        it "should create a default model if the task does not have a getModelName operation" do
            m = Runkit.create_orogen_task_context_model("/echo_Echo")
            flexmock(task).should_receive(:getModelName).and_raise(NoMethodError)
            flexmock(Runkit).should_receive(:create_orogen_task_context_model).once
                            .with("/echo_Echo").and_return(m)
            flexmock(task).should_receive(:model=).with(m).once.pass_thru

            assert_equal m, task.model
            assert_equal m, task.model
        end

        it "should create a default model if the task getModelName operation returns an empty name" do
            m = Runkit.create_orogen_task_context_model("/echo_Echo")
            flexmock(task).should_receive(:getModelName).and_return("")
            flexmock(Runkit).should_receive(:create_orogen_task_context_model).once
                            .with.and_return(m)
            flexmock(task).should_receive(:model=).with(m).once.pass_thru

            assert_equal m, task.model
            assert_equal m, task.model
        end

        it "should create a default model if the returned model name cannot be resolved" do
            m = Runkit.create_orogen_task_context_model("/echo_Echo")
            flexmock(task).should_receive(:getModelName).and_return("test::Task")
            flexmock(Runkit.default_loader).should_receive(:task_model_from_name)
                                           .with("test::Task").and_raise(OroGen::NotFound)
            flexmock(Runkit).should_receive(:create_orogen_task_context_model).once
                            .with("test::Task").and_return(m)
            flexmock(task).should_receive(:model=).with(m).once.pass_thru

            assert_equal m, task.model
            assert_equal m, task.model
        end

        it "sets as model the value returned by the loader" do
            m = Runkit.create_orogen_task_context_model("/echo_Echo")
            flexmock(task).should_receive(:getModelName).and_return("test::Task")
            flexmock(Runkit.default_loader).should_receive(:task_model_from_name)
                                           .with("test::Task").and_return(m)
            flexmock(task).should_receive(:model=).with(m).once.pass_thru

            assert_equal m, task.model
            assert_equal m, task.model
        end
    end
end
