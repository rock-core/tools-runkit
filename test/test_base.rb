require 'orocos/test'

describe "the Orocos module" do
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
            assert_raises(Orocos::TypekitTypeNotExported) { Orocos.find_orocos_type_name_by_type('/NonExportedType') }
            assert_raises(Orocos::TypekitTypeNotExported) { Orocos.find_orocos_type_name_by_type(Orocos.registry.get('/NonExportedType')) }
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

    describe "extension runtime loading" do
        attr_reader :project

        before do
            @project = OroGen::Spec::Project.new(Orocos.default_loader)
            task = flexmock
            task.should_receive(:each_extension).and_yield(flexmock(:name => 'test'))
            project.self_tasks['test_project::Task'] = task
        end

        it "sets up a on_project_load hook that loads the extensions" do
            flexmock(Orocos).should_receive(:load_extension_runtime_library).with('test').once
            Orocos.default_loader.register_project_model(project)
        end

        it "loads the extension file through require" do
            flexmock(Orocos).should_receive(:require).with("runtime/test").once
            Orocos.load_extension_runtime_library('test')
        end

        it "loads the same extension file only once" do
            flexmock(Orocos).should_receive(:require).with("runtime/test").once
            Orocos.load_extension_runtime_library('test')
            Orocos.load_extension_runtime_library('test')
        end
    end
end

