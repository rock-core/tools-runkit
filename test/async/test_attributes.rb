$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", '..', "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

# helper for generating an ior from a name
def ior(name)
    Orocos.name_service.ior(name)
rescue Orocos::NotFound => e
    "IOR:010000001f00000049444c3a5254542f636f7262612f435461736b436f6e746578743a312e300000010000000000000064000000010102000d00000031302e3235302e332e31363000002bc80e000000fe8a95a65000004d25000000000000000200000000000000080000000100000000545441010000001c00000001000000010001000100000001000105090101000100000009010100"
end

describe Orocos::Async::CORBA::Property do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    describe "When connect to a remote task" do 
        it "must return a property object" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                p = t1.property("prop1")
                p.must_be_kind_of Orocos::Async::CORBA::Property
            end
        end
        it "must asynchronously return a property" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                p = nil
                t1.property("prop1") do |prop|
                    p = prop
                end
                sleep 0.1
                Orocos::Async.step
                p.must_be_kind_of Orocos::Async::CORBA::Property
            end
        end
        it "must call on_change" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                p = t1.property("prop2")
                p.period = 0.1
                vals = Array.new
                p.on_change do |data|
                    vals << data
                end
                sleep 0.1
                Orocos::Async.steps
                assert_equal 1,vals.size
                p.write 33
                sleep 0.1
                Orocos::Async.steps
                assert_equal 2,vals.size
                assert_equal 33,vals.last
            end
        end
    end
end

describe Orocos::Async::CORBA::Attribute do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    describe "When connect to a remote task" do 
        it "must return a attribute object" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                a = t1.attribute("att2")
                a.must_be_kind_of Orocos::Async::CORBA::Attribute
            end
        end
        it "must asynchronously return a attribute" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                a = nil
                t1.attribute("att2") do |prop|
                    a = prop
                end
                sleep 0.1
                Orocos::Async.step
                a.must_be_kind_of Orocos::Async::CORBA::Attribute
            end
        end
        it "must call on_change" do 
            Orocos.run('process') do
                t1 = Orocos::Async::CORBA::TaskContext.new(ior('process_Test'))
                a = t1.attribute("att2")
                a.period = 0.1
                vals = Array.new
                a.on_change do |data|
                    vals << data
                end
                sleep 0.1
                Orocos::Async.steps
                assert_equal 1,vals.size
                a.write 33
                sleep 0.1
                Orocos::Async.steps
                assert_equal 2,vals.size
                assert_equal 33,vals.last
            end
        end
    end
end
