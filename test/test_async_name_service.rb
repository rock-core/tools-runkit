
$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

MiniTest::Unit.autorun
TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')


describe Orocos::Async::NameService do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    it "should have a global default instance" do
        Orocos::Async.name_service.must_be_instance_of Orocos::Async::NameService
    end

    it "should raise NotFound if remote task is not reachable" do
        ns = Orocos::Async::NameService.new
        assert_raises Orocos::NotFound do 
            ns.get "bla"
        end
    end

    it "should return a TaskContextProxy" do 
        Orocos.run('process') do
            ns = Orocos::Async::NameService.new
            ns << Orocos::Async::CORBA::NameService.new

            t = ns.get "process_Test"
            t.must_be_instance_of Orocos::Async::CORBA::TaskContext

            t2 = nil
            ns.get "process_Test" do |task|
                t2 = task
            end
            sleep 0.1
            Orocos::Async.step
            t2.must_be_instance_of Orocos::Async::CORBA::TaskContext
        end
    end
end

describe Orocos::Async::CORBA::NameService do
    include Orocos::Spec

    before do 
        Orocos::Async.clear
    end

    it "should raise NotFound if remote task is not reachable" do
        ns = Orocos::Async::CORBA::NameService.new
        assert_raises Orocos::NotFound do 
            ns.get "bla"
        end
    end

    it "should not raise NotFound if remote task is not reachable and a block is given" do
        ns = Orocos::Async::CORBA::NameService.new

        not_called = true
        ns.get "bla" do |task|
            not_called = false
        end

        error = nil
        ns.get "bla" do |task,err|
            error = err
        end

        sleep 0.1
        Orocos::Async.step
        assert not_called
        error.must_be_instance_of Orocos::NotFound
    end

    it "should have a global default instance" do
        Orocos::Async::CORBA.name_service.must_be_instance_of Orocos::Async::CORBA::NameService
    end

    it "should return a TaskContextProxy" do 
        Orocos.run('process') do
            ns = Orocos::Async::CORBA::NameService.new
            t = ns.get "process_Test"
            t.must_be_instance_of Orocos::Async::CORBA::TaskContext

            t2 = nil
            ns.get "process_Test" do |task|
                t2 = task
            end
            sleep 0.1
            Orocos::Async.step
            t2.must_be_instance_of Orocos::Async::CORBA::TaskContext
        end
    end
end

