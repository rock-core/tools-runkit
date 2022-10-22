# frozen_string_literal: true

require "runkit/test"

describe "the Runkit module" do
    it "should allow listing task names" do
        Runkit.task_names
    end

    describe "#find_runkit_type_name_by_type" do
        before do
            Runkit.load_typekit "echo"
        end
        it "can be given an opaque type directly" do
            assert_equal "/OpaquePoint", Runkit.find_runkit_type_name_by_type("/OpaquePoint")
            assert_equal "/OpaquePoint", Runkit.find_runkit_type_name_by_type(Runkit.registry.get("/OpaquePoint"))
        end
        it "can be given an opaque-containing type directly" do
            assert_equal "/OpaqueContainingType", Runkit.find_runkit_type_name_by_type("/OpaqueContainingType")
            assert_equal "/OpaqueContainingType", Runkit.find_runkit_type_name_by_type(Runkit.registry.get("/OpaqueContainingType"))
        end
        it "converts a non-exported intermediate type to the corresponding opaque" do
            assert_equal "/OpaquePoint", Runkit.find_runkit_type_name_by_type("/echo/Point")
            assert_equal "/OpaquePoint", Runkit.find_runkit_type_name_by_type(Runkit.registry.get("/echo/Point"))
        end
        it "converts a non-exported m-type to the corresponding opaque-containing type" do
            assert_equal "/OpaqueContainingType", Runkit.find_runkit_type_name_by_type("/OpaqueContainingType_m")
            assert_equal "/OpaqueContainingType", Runkit.find_runkit_type_name_by_type(Runkit.registry.get("/OpaqueContainingType_m"))
        end
        it "successfully converts a basic type to the corresponding runkit type name" do
            typename = Runkit.registry.get("int").name
            refute_equal "int", typename
            assert_equal "/int32_t", Runkit.find_runkit_type_name_by_type(typename)
            assert_equal "/int32_t", Runkit.find_runkit_type_name_by_type(Runkit.registry.get("int"))
        end
        it "raises if given a non-exported type" do
            assert_raises(Runkit::TypekitTypeNotExported) { Runkit.find_runkit_type_name_by_type("/NonExportedType") }
            assert_raises(Runkit::TypekitTypeNotExported) { Runkit.find_runkit_type_name_by_type(Runkit.registry.get("/NonExportedType")) }
        end
    end

    describe ".loaded?" do
        it "should return false after #clear" do
            assert Runkit.loaded? # setup() calls Runkit.initialize
            Runkit.clear
            assert !Runkit.loaded?
        end
        it "should return true after #load" do
            assert Runkit.loaded? # setup() calls Runkit.initialize
            Runkit.clear
            Runkit.load
            assert Runkit.loaded?
        end
    end

    describe "extension runtime loading" do
        attr_reader :project

        before do
            @project = OroGen::Spec::Project.new(Runkit.default_loader)
            task = flexmock
            task.should_receive(:each_extension).and_yield(flexmock(name: "test"))
            project.self_tasks["test_project::Task"] = task
        end

        it "sets up a on_project_load hook that loads the extensions" do
            flexmock(Runkit).should_receive(:load_extension_runtime_library).with("test").once
            Runkit.default_loader.register_project_model(project)
        end

        it "loads the extension file through require" do
            flexmock(Runkit).should_receive(:require).with("runtime/test").once
            Runkit.load_extension_runtime_library("test")
        end

        it "loads the same extension file only once" do
            flexmock(Runkit).should_receive(:require).with("runtime/test").once
            Runkit.load_extension_runtime_library("test")
            Runkit.load_extension_runtime_library("test")
        end
    end
end
