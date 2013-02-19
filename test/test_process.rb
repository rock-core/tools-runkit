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
        process = nil
	process = Orocos::Process.new('process')
        begin
            process.spawn
            process.wait_running(10)
            assert(process.alive?)
            assert(process.running?)
	ensure
	    process.kill if process.running?
        end
    end

    it "can stop a running process and clean up the name server" do
        Orocos.run('process') do |process|
            assert( Orocos.task_names.find { |name| name == '/process_Test' } )
            process.kill
            assert(!process.alive?, "process has been killed but alive? returns true")
            assert( !Orocos.task_names.find { |name| name == 'process_Test' } )
        end
    end

    it "can start a process with a prefix" do
        Orocos.run('process' => 'prefix') do |process|
            assert(Orocos::TaskContext.get('prefixprocess_Test'))
        end
    end

    it "can get a reference on a deployed task context by name" do
        Orocos.run('process') do |process|
            assert(direct   = Orocos::TaskContext.get('process_Test'))
            assert(indirect = process.task("Test"))
            assert_equal(direct, indirect)
        end
    end

    it "can get a reference on a deployed task context by class" do
        Orocos.run('process') do |process|
            assert(direct   = Orocos::TaskContext.get(:provides => "process::Test"))
            assert(indirect = process.task("Test"))
            assert_equal(direct, indirect)
        end
    end

    it "throws NotFound on an unknown task context name" do
        Orocos.run('process') do |process|
            assert_raises(Orocos::NotFound) { process.task("Bla") }
        end
    end

    it "can enumerate its own deployed task contexts" do
        Orocos.run('process') do |process|
            process.task_names.must_equal %w{process_Test}
        end
    end

    it "can automatically add prefixes to tasks" do
        process = Orocos::Process.new 'process'
        begin
            process.spawn :prefix => 'prefix'
            assert_equal Hash["process_Test" => "prefixprocess_Test"], process.name_mappings
            assert Orocos.name_service.get('prefixprocess_Test')
        ensure
            process.kill
        end
    end

    it "can rename single tasks" do
        process = Orocos::Process.new 'process'
        begin
            process.map_name "process_Test", "prefixprocess_Test"
            process.spawn
            assert Orocos.name_service.get('prefixprocess_Test')
        ensure
            process.kill
        end
    end
end

