$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::Process do
    include Orocos::Spec

    it "raises NotFound when the deployment name does not exist" do
        assert_raises(Orocos::NotFound) { Orocos::Process.new("does_not_exist") }
    end

    it "can spawn a new process and waits for it" do
        Orocos.guard do
            process = Orocos::Process.new('process')
            process.spawn
            process.wait_running(0.5)
            assert(process.alive?)
        end
    end

    it "can stop a running process and clean up the name server" do
        Orocos::Process.spawn('process') do |process|
            assert( Orocos.task_names.find { |name| name == 'process_Test' } )
            process.kill
            assert(!process.alive?, "process has been killed but alive? returns true")
            assert( !Orocos.task_names.find { |name| name == 'process_Test' } )
        end
    end

    it "can get a reference on a deployed task context by name" do
        Orocos::Process.spawn('process') do |process|
            assert(direct   = Orocos::TaskContext.get('process_Test'))
            assert(indirect = process.task("Test"))
            assert_equal(direct, indirect)
        end
    end

    it "can get a reference on a deployed task context by class" do
        Orocos::Process.spawn('process') do |process|
            assert(direct   = Orocos::TaskContext.get(:provides => "process::Test"))
            assert(indirect = process.task("Test"))
            assert_equal(direct, indirect)
        end
    end

    it "throws NotFound on an unknown task context name" do
        Orocos::Process.spawn('process') do |process|
            assert_raises(Orocos::NotFound) { process.task("Bla") }
        end
    end

    it "can enumerate its own deployed task contexts" do
        Orocos::Process.spawn('process') do |process|
            process.task_names.must_equal %w{process_Test}
        end
    end

    it "loads the toolkits associated with any given deployment" do
        assert(!Orocos::CORBA.loaded_toolkit?("process"))
        Orocos::Process.spawn('process') do |process|
            assert(Orocos::CORBA.loaded_toolkit?("process"))
        end
    end
end

