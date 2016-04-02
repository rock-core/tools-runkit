require 'orocos/test'
require 'orocos/async'

describe Orocos::Async::CORBA::OutputPort do
    before do 
        Orocos::Async.clear
    end

    describe "When connect to a remote task" do 
        it "must return a reader for output ports" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                port = t1.port("cycle")
                port.reader.must_be_kind_of Orocos::Async::CORBA::OutputReader
            end
        end
        it "must asynchronously return a reader for output ports" do 
            Orocos.run('simple_source') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                port = t1.port("cycle")
                reader = nil
                port.reader do |r|
                    reader = r
                end
                sleep 0.1
                Orocos::Async.step
                reader.must_be_kind_of Orocos::Async::CORBA::OutputReader
            end
        end
        it "must call on_data if new data are available and a block is registered" do 
            start 'simple_source::source' => 'source'
            t1 = Orocos::Async::CORBA::TaskContext.new(ior('source'))
            port = t1.port("cycle")
            data = []
            port.on_data :period => 0.05 do |d|
                data << d
            end
            t1.configure
            t1.start
            1.upto(10) do
                Orocos::Async.step
                sleep 0.05
            end
            t1.stop
            assert !data.empty?
            data.each_with_index do |v,i|
                assert_equal i+1,v
            end
        end
    end
end

describe Orocos::Async::CORBA::InputPort do
    include Orocos::Spec

    describe "When connect to a remote task" do 
        it "must return a writer for input ports" do 
            Orocos.run('simple_sink') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_sink_sink'))
                port = t1.port("cycle")
                port.writer.must_be_kind_of Orocos::Async::CORBA::InputWriter
            end
        end

        it "must asynchronously return a writer for input ports" do 
            Orocos.run('simple_sink') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_sink_sink'))
                port = t1.port("cycle")
                writer = nil
                port.writer do |w|
                    writer = w
                end
                sleep 0.1
                Orocos::Async.step
                writer.must_be_kind_of Orocos::Async::CORBA::InputWriter
            end
        end
    end
end

describe Orocos::Async::CORBA::OutputReader do
    include Orocos::Spec

    describe "When connect to a remote task" do 
        it "should be possible to read data" do 
            Orocos.run('simple_source') do
                data = []
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                port = t1.port("cycle")
                reader = port.reader(:type => :buffer,:size => 10)

                #for now operations are not possible
                t1.configure
                t1.start

                1.upto(5) do |v|
                    sleep 0.5
                    assert_equal v,reader.read
                end
            end
        end

        it "should call on data each time new data are available" do 
            Orocos.run('simple_source') do
                data = []
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                port = t1.port("cycle")
                reader = port.reader(:period => 0.09)
                data = []
                reader.on_data do |val|
                    data << val
                end

                t1.configure
                t1.start
                1.upto(10) do 
                    Orocos::Async.step
                    sleep 0.05
                end
                t1.stop
                assert !data.empty?
                data.each_with_index do |v,i|
                    assert_equal i+1,v
                end
            end
        end

        it "should read all data from a buffered connection even if the period of the reader is too large" do 
            Orocos.run('simple_source') do
                data = []
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('simple_source_source'))
                port = t1.port("cycle",:type => :buffer,:size => 100,:period => 100)
                port.on_data do |sample|
                    data << sample
                end
                t1.configure
                t1.start
                1.upto(5) do |v|
                    Orocos::Async.steps
                    sleep 0.5
                end
                assert !data.empty?
            end
        end
    end
end
