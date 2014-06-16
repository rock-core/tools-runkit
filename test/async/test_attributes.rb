require 'orocos/test'
require 'orocos/async'

describe Orocos::Async::CORBA::Property do
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
