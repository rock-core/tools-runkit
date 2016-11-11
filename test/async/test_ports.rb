require 'orocos/test'
require 'orocos/async'

describe Orocos::Async::CORBA::OutputPort do
    attr_reader :source
    before do
        @source = new_ruby_task_context 'source'
        source.create_output_port 'cycle', 'int'
    end

    after do 
        Orocos::Async.clear
    end

    it "synchronously returns a reader for output ports if called without a block" do 
        t1 = Orocos::Async::CORBA::TaskContext.new(source.ior)
        t1.port("cycle").reader.must_be_kind_of Orocos::Async::CORBA::OutputReader
    end

    it "asynchronously returns a reader for output ports if called with a block" do 
        t1 = Orocos::Async::CORBA::TaskContext.new(source.ior)
        reader = nil
        t1.port("cycle").reader do |r|
            reader = r
        end
        assert_async_polls_until { reader }
        reader.must_be_kind_of Orocos::Async::CORBA::OutputReader
    end
end

describe Orocos::Async::CORBA::InputPort do
    attr_reader :sink
    before do
        @sink = new_ruby_task_context 'sink'
        sink.create_input_port 'cycle', 'int'
    end

    after do 
        Orocos::Async.clear
    end

    describe "When connect to a remote task" do 
        it "must return a writer for input ports" do 
            t1 = Orocos::Async::CORBA::TaskContext.new(sink.ior)
            t1.port("cycle").writer.must_be_kind_of Orocos::Async::CORBA::InputWriter
        end

        it "must asynchronously return a writer for input ports" do 
            t1 = Orocos::Async::CORBA::TaskContext.new(sink.ior)
            writer = nil
            t1.port("cycle").writer { |w| writer = w }
            assert_async_polls_until { writer }
            writer.must_be_kind_of Orocos::Async::CORBA::InputWriter
        end
    end
end

describe Orocos::Async::CORBA::OutputReader do
    attr_reader :source
    before do
        @source = new_ruby_task_context 'source'
        source.create_output_port 'cycle', 'int'
    end

    after do 
        Orocos::Async.clear
    end

    it "reads data" do 
        t1 = Orocos::Async::CORBA::TaskContext.new(source.ior)
        reader = t1.port("cycle").reader(type: :buffer, size: 10)

        t1.configure
        t1.start

        5.times do |i|
            source.cycle.write(i)
            value = assert_async_polls_until { reader.read_new }
            assert_equal i, value
        end
    end

    it "calls on_data if new data are available and a block is registered" do 
        t1 = Orocos::Async::CORBA::TaskContext.new(source.ior)
        data = []
        t1.port("cycle").on_data(period: 0.01) do |d|
            data << d
        end
        t1.configure
        t1.start
        10.times do |i|
            source.cycle.write(i)
            assert_async_polls_until { data.last == i }
        end
        t1.stop
        assert_equal (0...10).to_a, data
    end

    it "reads buffers in a loop" do 
        t1 = Orocos::Async::CORBA::TaskContext.new(source.ior)
        port = t1.port("cycle")

        start_time = nil
        data = []
        port.on_data(type: :buffer, size: 100, period: 5) do |sample|
            start_time ||= Time.now
            data << sample
        end

        t1.configure
        t1.start

        # We use the first write as a way to wait for the global reader to be
        # resolved. The API does not give us any feedback for this.
        #
        # Moreover, the Time.now-start_time check verifies that all samples are
        # read in one thread period, instead of read one sample per period
        source.cycle.write(0)
        assert_async_polls_until { !data.empty? }
        49.times { |i| source.cycle.write(i + 1) }
        start_time = nil
        assert_async_polls_until { data.size == 50 }
        assert (Time.now - start_time) < 1
        assert_equal (0...50).to_a, data
    end
end
