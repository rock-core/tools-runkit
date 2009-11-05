$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::TaskContext do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should not be possible to create one directly" do
	assert_raises(NoMethodError) { Orocos::TaskContext.new }
    end

    it "should raise NotFound on unknown task contexts" do
	assert_raises(Orocos::NotFound) { Orocos::TaskContext.get('Bla_Blo') }
    end

    it "should check equality based on CORBA reference" do
        Orocos::Process.spawn('process') do |process|
            assert(t1 = Orocos::TaskContext.get('process_Test'))
            assert(t2 = Orocos::TaskContext.get('process_Test'))
            refute_equal(t1.object_id, t2.object_id)
            assert_equal(t1, t2)
        end
    end

    it "should allow enumerating its ports" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |source, sink|
            source = source.task("source")
            sink   = sink.task("sink")

            source.enum_for(:each_port).to_a.must_equal [source.port("cycle"), source.port("cycle_struct")]
            sink.enum_for(:each_port).to_a.must_equal [sink.port("cycle")]
        end
    end

    it "should allow getting its ports" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |source, sink|
            source = source.task("source")
            sink   = sink.task("sink")

            assert(source_p = source.port('cycle'))
            source_p.must_be_kind_of(Orocos::OutputPort)
            source_p.name.must_equal("cycle")
            source_p.task.must_equal(source)
            source_p.type_name.must_equal("int")

            assert(sink_p   = sink.port('cycle'))
            sink_p.must_be_kind_of(Orocos::InputPort)
            sink_p.name.must_equal("cycle")
            sink_p.task.must_equal(sink)
            sink_p.type_name.must_equal("int")
        end
    end

    it "should allow to check a method availability" do
        Orocos::Process.spawn('states') do |p|
            t = p.task "Task"
            assert(!t.has_method?("does_not_exist"))
            assert(t.has_method?("do_runtime_warning"))
        end
    end

    it "should allow to check a command availability" do
        Orocos::Process.spawn('echo') do |p|
            t = p.task "Echo"
            assert(!t.has_command?("does_not_exist"))
            assert(t.has_command?("AsyncWrite"))
        end
    end

    it "should allow to check a port availability" do
        Orocos::Process.spawn('simple_source') do |p|
            t = p.task "source"
            assert(!t.has_port?("does_not_exist"))
            assert(t.has_port?("cycle"))
        end
    end

    it "should raise NotFound if a port does not exist" do
        Orocos::Process.spawn('simple_source') do |source|
            assert_raises(Orocos::NotFound) { source.task("source").port("does_not_exist") }
        end
    end

    it "should raise CORBA::ComError when #port is called on a dead remote process" do
        Orocos::Process.spawn('simple_source') do |source_p|
            source = source_p.task("source")
            source_p.kill
            assert_raises(Orocos::CORBA::ComError) { source.port("cycle") }
        end
    end

    it "should allow getting a method object" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task('Echo')
            m = echo.rtt_method(:write)
            assert_equal "write", m.name
            assert_equal "write_method", m.description
            assert_equal "int", m.return_spec
            assert_equal [["value", "value_arg", "int"]], m.arguments_spec
        end
    end

    it "should raise NotFound on an unknown method object" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task('Echo')
            assert_raises(Orocos::NotFound) { echo.rtt_method(:unknown) }
        end
    end

    it "should raise CORBA::ComError when #rtt_method has communication errors" do
        Orocos::Process.spawn 'echo' do |echo_p|
            echo = echo_p.task('Echo')
            echo_p.kill
            assert_raises(Orocos::CORBA::ComError) { echo.rtt_method(:write) }
        end
    end

    it "should allow getting a command object" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task('Echo')
            m = echo.command(:AsyncWrite)
            assert_equal "AsyncWrite", m.name
            assert_equal "async_write_command", m.description
            assert_equal [["value", "value_arg", "int"], ["stop", "stop_value", "int"]], m.arguments_spec
        end
    end

    it "should raise NotFound on an unknown method object" do
        Orocos::Process.spawn 'echo' do |echo|
            echo = echo.task('Echo')
            assert_raises(Orocos::NotFound) { echo.command(:unknown) }
        end
    end

    it "should raise CORBA::ComError when #command has communication errors" do
        Orocos::Process.spawn 'echo' do |echo_p|
            echo = echo_p.task('Echo')
            echo_p.kill
            assert_raises(Orocos::CORBA::ComError) { echo.command(:write) }
        end
    end

    it "should be able to manipulate the task state machine and read its state" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task("source")
            assert_equal(:PRE_OPERATIONAL, source.state)
            assert_raises(Orocos::StateTransitionFailed) { source.start }
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

    it "should raise CORBA::ComError when state-related methods are called on a dead process" do
        Orocos::Process.spawn('simple_source') do |source_p|
            source = source_p.task("source")
            source_p.kill
            assert_raises(Orocos::CORBA::ComError) { source.state }
            #assert_raises(Orocos::CORBA::ComError) { source.start }
            #assert_raises(Orocos::CORBA::ComError) { source.stop }
            #assert_raises(Orocos::CORBA::ComError) { source.configure }
        end
    end

    it "should be pretty-printable" do
        Orocos::Process.spawn('echo', 'process') do |source_p, process_p|
            source = source_p.task("Echo")
            process = process_p.task('Test')
            PP.pp(source, '')
            PP.pp(process, '')
        end
    end

    it "should allow to record its state trace when using extended state support" do
        Orocos::Process.spawn('states') do |p|
            t = p.task("Task")

            state = t.port('state').reader :type => :buffer, :size => 20, :init => true

            # First check the nominal state changes
            t.configure
            t.start
            t.stop
            t.cleanup
            assert_equal Orocos::TaskContext::STATE_PRE_OPERATIONAL, state.read
            assert_equal Orocos::TaskContext::STATE_STOPPED, state.read
            assert_equal Orocos::TaskContext::STATE_RUNNING, state.read
            assert_equal Orocos::TaskContext::STATE_STOPPED, state.read
            assert_equal Orocos::TaskContext::STATE_PRE_OPERATIONAL, state.read

            # Then test the error states
            t.configure
            t.start
            t.do_runtime_warning
            t.do_recover
            t.do_runtime_error
            t.do_recover
            t.do_runtime_warning
            t.do_runtime_error
            t.do_recover
            t.do_fatal_error
            t.reset_error
            t.cleanup

            # Note: we don't have state_pre_operational as we already read it
            # once
            assert_equal Orocos::TaskContext::STATE_STOPPED, state.read
            assert_equal Orocos::TaskContext::STATE_RUNNING, state.read
            assert_equal Orocos::TaskContext::STATE_RUNTIME_WARNING, state.read
            assert_equal Orocos::TaskContext::STATE_RUNNING, state.read
            assert_equal Orocos::TaskContext::STATE_RUNTIME_ERROR, state.read
            assert_equal Orocos::TaskContext::STATE_RUNNING, state.read
            assert_equal Orocos::TaskContext::STATE_RUNTIME_WARNING, state.read
            assert_equal Orocos::TaskContext::STATE_RUNTIME_ERROR, state.read
            assert_equal Orocos::TaskContext::STATE_RUNNING, state.read
            assert_equal Orocos::TaskContext::STATE_FATAL_ERROR, state.read
            assert_equal Orocos::TaskContext::STATE_STOPPED, state.read
            assert_equal Orocos::TaskContext::STATE_PRE_OPERATIONAL, state.read
        end
    end

    it "should allow to trace custom states trace when using extended state support" do
        Orocos::Process.spawn('states') do |p|
            t = p.task("Task")

            state = t.state_reader :type => :buffer, :size => 20

            assert !t.ready?
            assert !t.running?
            assert !t.error?
            t.configure
            assert t.ready?
            assert !t.running?
            assert !t.error?
            t.start
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_runtime
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_nominal_running
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_error
            assert t.ready?
            assert t.running?
            assert t.error?
            t.do_recover
            assert t.ready?
            assert t.running?
            assert !t.error?
            t.do_custom_fatal
            assert t.ready?
            assert !t.running?
            assert t.error?
            t.reset_error
            assert t.ready?
            assert !t.running?
            assert !t.error?
            t.cleanup
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
            assert_equal :CUSTOM_FATAL, state.read
            assert_equal :STOPPED, state.read
            assert_equal :PRE_OPERATIONAL, state.read
        end
    end

    it "should report its model name" do
        Orocos::Process.spawn('echo') do |p|
            t = p.task "Echo"
            assert_equal("echo::Echo", p.task("Echo").getModelName)
        end
    end

    it "should allow getting its model even though its process is unknown" do
        Orocos::Process.spawn('echo') do |p|
            t = p.task "Echo"

            assert t.process
            t.instance_variable_set :@process, nil
            t.instance_variable_set :@info, nil
            t.instance_variable_set :@model, nil
            assert t.model
            assert_equal("echo::Echo", t.model.name)
            assert !t.process
        end

    end
end

