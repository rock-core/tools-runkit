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

            source.enum_for(:each_port).to_a.must_equal [source.port("cycle")]
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

    it "should raise NotFound if a port does not exist" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |source, sink|
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
            assert_equal(Orocos::TaskContext::STATE_PRE_OPERATIONAL, source.state)
            assert_raises(Orocos::StateTransitionFailed) { source.start }
            assert(!source.ready?)
            assert(!source.running?)

            source.configure
            assert_equal(Orocos::TaskContext::STATE_STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)

            source.start
            assert_equal(Orocos::TaskContext::STATE_RUNNING, source.state)
            assert(source.ready?)
            assert(source.running?)

            source.stop
            assert_equal(Orocos::TaskContext::STATE_STOPPED, source.state)
            assert(source.ready?)
            assert(!source.running?)
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
end

