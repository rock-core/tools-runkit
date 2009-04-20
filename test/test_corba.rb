$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

describe Orocos::CORBA do
    it "should be already initialized" do
        assert !Orocos::CORBA::init
    end

    it "should allow listing task names" do
        Orocos.task_names
    end
end

