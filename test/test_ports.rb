$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::Port do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should check equality based on CORBA reference" do
        start_processes('simple_source') do |source|
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

    it "should be able to connect to an input" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
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
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            p_sink.kill
            assert_raises(ComError) { source.connect_to sink }
        end
    end

    it "should raise CORBA::ComError when #connect_to is called on a dead process" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            p_source.kill
            assert_raises(ComError) { source.connect_to sink }
        end
    end

    it "should be able to disconnect from a particular input" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            assert(source.connected?)
            source.disconnect_from sink
            assert(!sink.connected?)
            assert(!source.connected?)
        end
    end

    it "it should be able to disconnect from a dead input" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            source.connect_to sink
            assert(source.connected?)
            p_sink.kill
            assert(source.connected?)
            source.disconnect_from sink
            assert(!source.connected?)
        end
    end

    it "should be able to disconnect from all its InputPort" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
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

    it "it should be able to disconnect all inputs even though some are dead" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")
            source.connect_to sink
            assert(source.connected?)
            p_sink.kill
            assert(source.connected?)
            source.disconnect_all
            assert(!source.connected?)
        end
    end

    it "should refuse connecting to another OutputPort" do
        start_processes('simple_source') do |p_source, p_sink|
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

    it "should be able to disconnect from all connected outputs" do
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
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
        start_processes('simple_source', 'simple_sink') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")
            sink   = p_sink.task("sink").port("cycle")

            source.connect_to sink
            assert(sink.connected?)
            p_source.kill
            assert(sink.connected?)
            sink.disconnect_all
            assert(!sink.connected?)
        end
    end

    it "should refuse connecting to another input" do
        start_processes('simple_source') do |p_source, p_sink|
            source = p_source.task("source").port("cycle")

            assert(!source.connected?)
            assert_raises(ArgumentError) { source.connect_to source }
        end
    end
end

describe Orocos::OutputReader do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should offer read access on an output port" do
        start_processes('simple_source') do |source|
            source = source.task('source')
            output = source.port('cycle')
            
            # Create a new reader. The default policy is data
            reader = output.reader
            assert(reader.kind_of?(Orocos::OutputReader))
            assert_equal(reader.read, nil) # nothing written yet
        end
    end

    it "should be able to read data from an output port using a data connection" do
        start_processes('simple_source') do |source|
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
        start_processes('simple_source') do |source|
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

    it "should be able to clear its connection" do
        start_processes('simple_source') do |source|
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
end

describe Orocos::InputWriter do
    TEST_DIR = File.expand_path(File.dirname(__FILE__))
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "should offer write access on an input port" do
        start_processes('echo') do |echo|
            echo  = echo.task('Echo')
            input = echo.port('input')
            
            writer = input.writer
            assert(writer.kind_of?(Orocos::InputWriter))
            writer.write(0)
        end
    end

    it "should be disconnected after writing on a dead port" do
        start_processes('echo') do |echo_p|
            echo  = echo_p.task('Echo')
            input = echo.port('input')
            
            writer = input.writer
            echo_p.kill
            assert(!writer.write(0))
            assert(!writer.connected?)
        end
    end

    it "should be able to write data to an input port using a data connection" do
        start_processes('echo') do |echo|
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
end

