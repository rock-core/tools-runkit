$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'orocos'
require 'minitest/spec'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')
ENV['PKG_CONFIG_PATH'] += ":#{File.join(WORK_DIR, "prefix", 'lib', 'pkgconfig')}"

describe Orocos::Namespace do
    attr_reader :object

    before do
        @object = Object.new
        object.extend Orocos::Namespace
    end
    describe "#split_name" do
        it "returns an empty string for the root namespace" do
            ns, name = object.split_name('/bla')
            assert_equal '', ns
        end
        it "returns the namespace without the leading slash for full names" do
            ns, name = object.split_name('/myns/bla')
            assert_equal '/myns', ns
        end
    end
end

