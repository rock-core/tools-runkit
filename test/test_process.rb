$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::Process do
    TEST_DIR = File.dirname(__FILE__)
    DATA_DIR = File.join(TEST_DIR, 'data')
    WORK_DIR = File.join(TEST_DIR, 'working_copy')

    include Orocos::Spec

    it "raises NotFound when the deployment name does not exist" do
        assert_raises(Orocos::NotFound) { Orocos::Process.new("does_not_exist") }
    end

    it "can spawn a new process and waits for it" do
        cleanup_process(Orocos::Process.new 'process') do |process|
            process.spawn
            process.wait_running(0.5)
            assert(process.alive?)
        end
    end

    it "can kill a running process" do
        start_processes('process') do |process|
            process.kill
            assert(!process.alive?)
        end
    end

    it "can get a reference on a deployed task context" do
        start_processes('process') do |process|
            assert(direct   = Orocos::TaskContext.get('process_Test'))
            assert(indirect = process.task("Test"))
            assert_equal(direct, indirect)
        end
    end

    it "can enumerate its own deployed task contexts" do
        start_processes('process') do |process|
            process.task_names.must_equal %w{Test}
        end
    end

    it "cleanups dead reference on the name server" do
        start_processes('process') do |process|
            process.kill('KILL')

            assert( Orocos.components.find { |name| name == 'process_Test' } )
            assert_raises(Orocos::NotFound) { Orocos::TaskContext.get 'process_Test' }
            assert( !Orocos.components.find { |name| name == 'process_Test' } )
        end
    end
end

