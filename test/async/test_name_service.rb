$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", '..', "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'
require 'orocos/async'

TEST_DIR = File.expand_path('..', File.dirname(__FILE__))
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

    it "should be reachable" do
        assert Orocos::Async.name_service.reachable?
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

    it "should report that new task are added and removed" do 
        ns = Orocos::Async::NameService.new(:period => 0.08)
        ns << Orocos::Async::CORBA::NameService.new
        names_added = []
        names_removed = []
        ns.on_task_added do |n|
            names_added << n
        end
        ns.on_task_removed do |n|
            names_removed << n
        end
        Orocos.run('process') do
            sleep 0.1
            Orocos::Async.steps
            assert_equal 1,names_added.size
            assert_equal 0,names_removed.size
            assert_equal "/process_Test",names_added.first
        end
        sleep 0.1
        Orocos::Async.steps
        assert_equal 1,names_added.size
        assert_equal 1,names_removed.size
        assert_equal "/process_Test",names_removed.first
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

describe Orocos::Async::Local::NameService do
    include Orocos::Spec

    before do
        Orocos::Async.clear
    end

    it "should raise NotFound if remote task is not reachable" do
        ns = Orocos::Async::Local::NameService.new
        assert_raises Orocos::NotFound do 
            ns.get "bla"
        end
    end

    it "should not raise NotFound if remote task is not reachable and a block is given" do
        ns = Orocos::Async::Local::NameService.new

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

    it "should return a TaskContextProxy" do 
        Orocos.run('process') do
            ns = Orocos::Async::Local::NameService.new
            t = Orocos.get "process_Test"
            ns.register t
            t = ns.get "process_Test"
            t.must_be_instance_of Orocos::Async::CORBA::TaskContext
            t.wait
            assert t.reachable?
        end
    end

    it "should return a TaskContextProxy" do 
        Orocos.run('process') do
            ns = Orocos::Async::Local::NameService.new
            t = Orocos.get "process_Test"
            ns.register t
            t = ns.proxy "process_Test"
            t.must_be_instance_of Orocos::Async::TaskContextProxy
            t.wait
            assert t.reachable?
        end
    end
end

