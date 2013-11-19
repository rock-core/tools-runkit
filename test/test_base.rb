$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe "the Orocos module" do
    include Orocos::Spec

    it "should allow listing task names" do
        Orocos.task_names
    end

    describe "#find_orocos_type_name_by_type" do
        before do
            Orocos.load_typekit 'echo'
        end
        it "can be given an opaque type directly" do
            assert_equal '/OpaquePoint', Orocos.find_orocos_type_name_by_type('/OpaquePoint')
            assert_equal '/OpaquePoint', Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/OpaquePoint'))
        end
        it "can be given an opaque-containing type directly" do
            assert_equal '/OpaqueContainingType', Orocos.find_orocos_type_name_by_type('/OpaqueContainingType')
            assert_equal '/OpaqueContainingType', Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/OpaqueContainingType'))
        end
        it "converts a non-exported intermediate type to the corresponding opaque" do
            assert_equal '/OpaquePoint', Orocos.find_orocos_type_name_by_type('/echo/Point')
            assert_equal '/OpaquePoint', Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/echo/Point'))
        end
        it "converts a non-exported m-type to the corresponding opaque-containing type" do
            assert_equal '/OpaqueContainingType', Orocos.find_orocos_type_name_by_type('/OpaqueContainingType_m')
            assert_equal '/OpaqueContainingType', Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/OpaqueContainingType_m'))
        end
        it "successfully converts a basic type to the corresponding orocos type name" do
            typename = Orocos.registry.get('int').name
            refute_equal 'int', typename
            assert_equal '/int32_t', Orocos.find_orocos_type_name_by_type(typename)
            assert_equal '/int32_t', Orocos.find_orocos_type_name_by_type(Orocos.registry.get('int'))
        end
        it "raises if given a non-exported type" do
            assert_raises(Orocos::ConfigError) { Orocos.find_orocos_type_name_by_type('/NonExportedType') }
            assert_raises(Orocos::ConfigError) { Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/NonExportedType')) }
        end
    end

    describe ".loaded?" do
        it "should return false after #clear" do
            assert Orocos.loaded? # setup() calls Orocos.initialize
            Orocos.clear
            assert !Orocos.loaded?
        end
        it "should return true after #load" do
            assert Orocos.loaded? # setup() calls Orocos.initialize
            Orocos.clear
            Orocos.load
            assert Orocos.loaded?
        end
    end
end

