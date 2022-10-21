# frozen_string_literal: true

require "orocos/test"
require "orocos/log"
require "pocolog"

module Orocos
    module Log
        describe InterfaceObject do
            describe "#initialize" do
                describe "the object name" do
                    before do
                        dir = make_tmpdir
                        registry = Typelib::CXXRegistry.new
                        @logfile = Pocolog::Logfiles.create(
                            File.join(dir, "somefile.0.log"), registry
                        )
                        @stream = @logfile.create_stream "test.pattern", "/double",
                                                         "rock_task_object_name" => "test",
                                                         "rock_orocos_type_name" => "/cxx/type/name"
                    end

                    it "uses the rock_task_object_name metadata by default" do
                        object = InterfaceObject.new(@stream)
                        assert_equal "test", object.name
                    end
                    it "falls back on the PORT.NAME pattern if the metadata does not exist" do
                        @stream.metadata.delete("rock_task_object_name")
                        flexmock(Log).should_receive(:warn)
                                     .with("stream 'test.pattern' has no rock_task_object_name "\
                                 "metadata, guessing the Orocos::Log::InterfaceObject "\
                                 "name from the stream name").once
                        object = InterfaceObject.new(@stream)
                        assert_equal "pattern", object.name
                    end
                    it "finally falls back to the whole stream name if the name does not "\
                        "match the PORT.NAME pattern" do
                        stream = @logfile.create_stream "test_pattern", "/double",
                                                        "rock_orocos_type_name" => "/cxx/type/name"

                        flexmock(Log).should_receive(:warn)
                                     .with("stream 'test_pattern' has no rock_task_object_name "\
                                 "metadata, guessing the Orocos::Log::InterfaceObject "\
                                 "name from the stream name").once
                        flexmock(Log).should_receive(:warn)
                                     .with("stream name 'test_pattern' does not follow the "\
                                 "convention TASKNAME.PORTNAME, taking it whole "\
                                 "as the Orocos::Log::InterfaceObject name").once
                        object = InterfaceObject.new(stream)
                        assert_equal "test_pattern", object.name
                    end
                end
                describe "the orocos type name" do
                    before do
                        dir = make_tmpdir
                        registry = Typelib::CXXRegistry.new
                        logfile = Pocolog::Logfiles.create(
                            File.join(dir, "somefile.0.log"), registry
                        )
                        @stream = logfile.create_stream "test.pattern", "/double",
                                                        "rock_task_object_name" => "test",
                                                        "rock_cxx_type_name" => "/orocos/type/name",
                                                        "rock_orocos_type_name" => "/cxx/type/name"
                    end

                    it "uses first the rock_orocos_type_name metadata" do
                        object = InterfaceObject.new(@stream)
                        assert_equal "/cxx/type/name", object.orocos_type_name
                    end
                    it "first falls back to rock_cxx_type_name metadata" do
                        @stream.metadata.delete "rock_orocos_type_name"
                        object = InterfaceObject.new(@stream)
                        assert_equal "/orocos/type/name", object.orocos_type_name
                    end
                    it "uses the type name last" do
                        @stream.metadata.delete "rock_cxx_type_name"
                        @stream.metadata.delete "rock_orocos_type_name"
                        flexmock(Log).should_receive(:warn)
                                     .with("stream 'test.pattern' has neither the "\
                                 "rock_cxx_type_name nor the rock_orocos_type_name "\
                                 "metadata set, falling back on the "\
                                 "Typelib type's name").once
                        object = InterfaceObject.new(@stream)
                        assert_equal "/double", object.orocos_type_name
                    end
                    it "filters out the _m type pattern when using the type name" do
                        @stream.metadata.delete "rock_cxx_type_name"
                        @stream.metadata.delete "rock_orocos_type_name"
                        flexmock(@stream.type).should_receive(name: "/double_m")
                        flexmock(Log).should_receive(:warn)
                                     .with("stream 'test.pattern' has neither the "\
                                 "rock_cxx_type_name nor the rock_orocos_type_name "\
                                 "metadata set, falling back on the "\
                                 "Typelib type's name").once
                        object = InterfaceObject.new(@stream)
                        assert_equal "/double", object.orocos_type_name
                    end
                end
            end
        end
    end
end
