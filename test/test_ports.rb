$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

Orocos::CORBA.call_timeout = 10000
Orocos::CORBA.connect_timeout = 10000

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Port do
    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::Port.new }
    end

    it "should check equality based on CORBA reference" do
        Orocos::Process.spawn 'simple_source' do |source|
            source = source.task("source")
            p1 = source.port("cycle")
            # Remove p1 from source's port cache
            source.instance_variable_get("@ports").delete("cycle")
            p2 = source.port("cycle")
            refute_equal(p1.object_id, p2.object_id)
            assert_equal(p1, p2)
        end
    end
end

describe Orocos::OutputPort do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    ComError = Orocos::CORBA::ComError

    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::OutputPort.new }
    end

    it "should be able to connect to an input" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            assert(!sink.connected?)
            assert(!source.connected?)
            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
        end
    end

    it "should raise CORBA::ComError when connected to a dead input" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            p_sink.kill(true, 'KILL')
            assert_raises(ComError) { source.connect_to sink }
        end
    end

    it "should raise CORBA::ComError when #connect_to is called on a dead process" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            p_source.kill(true, 'KILL')
            assert_raises(ComError) { source.connect_to sink }
        end
    end

    it "should be able to disconnect from a particular input" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            assert(!source.disconnect_from(sink))
            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            assert(source.disconnect_from(sink))
            assert(!sink.connected?)
            assert(!source.connected?)
            assert(!source.disconnect_from(sink))
        end
    end

    it "it should be able to disconnect from a dead input" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            source.connect_to sink
            assert(source.connected?)
            p_sink.kill(true, 'KILL')
            assert(source.connected?)
            source.disconnect_from sink
            assert(!source.connected?)
        end
    end

    it "should be able to disconnect from all its InputPort" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            source.disconnect_all
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "it should be able to initiate disconnection while running" do
        Orocos::Process.spawn('simple_source', 'simple_sink', :output => "%m.log") do |p_source, p_sink|
            source_task = p_source.task("fast_source")
            source = source_task.port("cycle")
            sink_task = p_sink.task("sink")
            sink = sink_task.port("cycle")

            source_task.configure
            source_task.start
            sink_task.start
            1000.times do |i|
                source.connect_to sink
                source.disconnect_all
            end
        end
    end

    it "it should be able to disconnect all inputs even though some are dead" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            source.connect_to sink
            assert(source.connected?)
            p_sink.kill(true, 'KILL')
            assert(source.connected?)
            source.disconnect_all
            assert(!source.connected?)
        end
    end

    it "should refuse connecting to another OutputPort" do
        Orocos::Process.spawn('simple_source') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")

            assert(!source.connected?)
            assert_raises(ArgumentError) { source.connect_to source }
        end
    end
end

describe Orocos::InputPort do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::InputPort.new }
    end

    it "should be able to disconnect from all connected outputs" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            sink.disconnect_all
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "should be able to disconnect from all connected outputs even though some are dead" do
        Orocos::Process.spawn('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            p_source.kill(true, 'KILL')
            assert(sink.connected?)
            sink.disconnect_all
            assert(!sink.connected?)
        end
    end

    it "should refuse connecting to another input" do
        Orocos::Process.spawn('simple_source') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")

            assert(!source.connected?)
            assert_raises(ArgumentError) { source.connect_to source }
        end
    end

    it "it should be able to initiate disconnection while running" do
        Orocos::Process.spawn('simple_source', 'simple_sink', :output => "%m.log"
                             ) do |p_source, p_sink|
            source_task = p_source.task("fast_source")
            source = source_task.port("cycle")
            sink_task = p_sink.task("sink")
            sink = sink_task.port("cycle")

            source_task.configure
            source_task.start
            sink_task.start
            1000.times do |i|
                source.connect_to sink
                sink.disconnect_all
            end
        end
    end
end

describe Orocos::OutputReader do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::OutputReader.new }
    end

    it "should offer read access on an output port" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle')
            
            # Create a new reader. The default policy is data
            reader = output.reader
            assert(reader.kind_of?(Orocos::OutputReader))
            assert_equal(reader.read, nil) # nothing written yet
        end
    end

    it "should allow to read opaque types" do
        Orocos::Process.spawn('echo') do |source|
            source = source.task('Echo')
            output = source.port('output_opaque')
            reader = output.reader
            source.configure
            source.start
            source.write_opaque(42)

            sleep(0.2)
            
            # Create a new reader. The default policy is data
            sample = reader.read
            assert_equal(42, sample.x)
            assert_equal(84, sample.y)
        end
    end

    it "should be able to read data from an output port using a data connection" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle')
            source.configure
            source.start
            
            # The default policy is data
            reader = output.reader
            sleep(0.2)
            assert(reader.read > 1)
        end
    end

    it "should be able to read data from an output port using a buffer connection" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle')
            reader = output.reader :type => :buffer, :size => 10
            source.configure
            source.start
            sleep(0.5)
            source.stop

            values = []
            while v = reader.read
                values << v
            end
            assert(values.size > 1)
            values.each_cons(2) do |a, b|
                assert(b == a + 1, "non-consecutive values #{a.inspect} and #{b.inspect}")
            end
        end
    end

    it "should be able to read data from an output port using a struct" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle_struct')
            reader = output.reader :type => :buffer, :size => 10
            source.configure
            source.start
            sleep(0.5)
            source.stop

            values = []
            while v = reader.read
                values << v.value
            end
            assert(values.size > 1)
            values.each_cons(2) do |a, b|
                assert(b == a + 1, "non-consecutive values #{a.inspect} and #{b.inspect}")
            end
        end
    end

    it "should be able to clear its connection" do
        Orocos::Process.spawn('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle')
            reader = output.reader
            source.configure
            source.start
            sleep(0.5)
            source.stop

            assert(reader.read)
            reader.clear
            assert(!reader.read)
        end
    end

    it "should raise ComError if the remote end is dead and be disconnected" do
	Orocos::Process.spawn 'simple_source' do |source_p|
            source = source_p.task('source')
            output = source.port('cycle')
            reader = output.reader
            source.configure
            source.start
            sleep(0.5)

	    source_p.kill(true, 'KILL')

	    assert_raises(Orocos::CORBA::ComError) { reader.read }
	    assert(!reader.connected?)
	end
    end
end

describe Orocos::InputWriter do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    CORBA = Orocos::CORBA
    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::InputWriter.new }
    end

    it "should offer write access on an input port" do
        Orocos::Process.spawn('echo') do |echo|
            echo  = echo.task('Echo')
            input = echo.port('input')
            
            writer = input.writer
            assert(writer.kind_of?(Orocos::InputWriter))
            writer.write(0)
        end
    end

    it "should raise Corba::ComError when writing on a dead port and be disconnected" do
        Orocos::Process.spawn('echo') do |echo_p|
            echo  = echo_p.task('Echo')
            input = echo.port('input')
            
            writer = input.writer
            echo_p.kill(true, 'KILL')
	    assert_raises(CORBA::ComError) { writer.write(0) }
	    assert(!writer.connected?)
        end
    end

    it "should be able to write data to an input port using a data connection" do
        Orocos::Process.spawn('echo') do |echo|
            echo  = echo.task('Echo')
            writer = echo.port('input').writer
            reader = echo.port('output').reader

            echo.start
            assert_equal(nil, reader.read)
            writer.write(10)
            sleep(0.1)
            assert_equal(10, reader.read)
        end
    end

    it "should be able to write structs using a Hash" do
        Orocos::Process.spawn('echo') do |echo|
            echo  = echo.task('Echo')
            writer = echo.port('input_struct').writer
            reader = echo.port('output').reader

            echo.start
            assert_equal(nil, reader.read)
            writer.write(:value => 10)
            sleep(0.1)
            assert_equal(10, reader.read)
        end
    end

    it "should allow to write opaque types" do
        Orocos::Process.spawn('echo') do |echo|
            echo  = echo.task('Echo')
            writer = echo.port('input_opaque').writer
            reader = echo.port('output_opaque').reader

            echo.start

            writer.write(:x => 84, :y => 42)
            sleep(0.2)
            sample = reader.read
            assert_equal(84, sample.x)
            assert_equal(42, sample.y)

            sample = writer.new_sample
            sample.x = 20
            sample.y = 10
            writer.write(sample)
            sleep(0.2)
            sample = reader.read
            assert_equal(20, sample.x)
            assert_equal(10, sample.y)
        end
    end
end

