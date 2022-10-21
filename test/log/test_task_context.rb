# frozen_string_literal: true

require "orocos/test"
require "orocos/log"
require "pocolog"

module Orocos
    module Log
        describe TaskContext do
            before do
                log_replay = Replay.new
                @task_context = TaskContext.new(log_replay, "test_task")
            end
            describe "#add_stream" do
                before do
                    dir = make_tmpdir
                    registry = Typelib::CXXRegistry.new
                    logfile = Pocolog::Logfiles.create(
                        File.join(dir, "somefile.0.log"), registry
                    )
                    @stream = logfile.create_stream "test_stream", "/double"
                end

                it "registers the stream as a property if rock_stream_type == 'property'" do
                    @stream.metadata["rock_stream_type"] = "property"
                    flexmock(@task_context).should_receive(:add_property).with(@stream).once
                                           .and_return(ret = flexmock)
                    assert_equal ret, @task_context.add_stream(@stream)
                end
                it "registers the stream as a port if rock_stream_type == 'port'" do
                    @stream.metadata["rock_stream_type"] = "port"
                    flexmock(@task_context).should_receive(:add_port).with(@stream).once
                                           .and_return(ret = flexmock)
                    assert_equal ret, @task_context.add_stream(@stream)
                end
                it "uses the type argument instead of rock_stream_type if provided" do
                    @stream.metadata["rock_stream_type"] = "property"
                    flexmock(@task_context).should_receive(:add_port).with(@stream).once
                                           .and_return(ret = flexmock)
                    assert_equal ret, @task_context.add_stream(@stream, type: "port")
                end
                it "raises ArgumentError if the rock_stream_type metadata is neither port nor property" do
                    @stream.metadata["rock_stream_type"] = "something"
                    e = assert_raises(ArgumentError) do
                        @task_context.add_stream(@stream)
                    end
                    assert_equal "the rock_stream_type metadata of 'test_stream' "\
                        "is 'something', expected either 'port' or 'property'",
                                 e.message
                end
                it "raises ArgumentError if there is no rock_stream_type metadata" do
                    e = assert_raises(ArgumentError) do
                        @task_context.add_stream(@stream)
                    end
                    assert_equal "stream 'test_stream' has no rock_stream_type metadata, "\
                        "cannot guess whether it should back a port or a property",
                                 e.message
                end
                it "accepts having a file_path as first argument for backward-compatibility "\
                        "reasons" do
                    @stream.metadata["rock_stream_type"] = "port"
                    flexmock(@task_context).should_receive(:add_port).with(@stream).once
                                           .and_return(ret = flexmock)
                    assert_equal ret, @task_context.add_stream(flexmock, @stream)
                end
            end

            describe "#add_property" do
                before do
                    dir = make_tmpdir
                    registry = Typelib::CXXRegistry.new
                    logfile = Pocolog::Logfiles.create(
                        File.join(dir, "somefile.0.log"), registry
                    )
                    @stream = logfile.create_stream "test_stream", "/double",
                                                    "rock_task_object_name" => "test"
                end

                it "registers a new property backed by the stream" do
                    @task_context.add_property(@stream)
                    p = @task_context.property("test")
                    assert_equal @task_context, p.task
                    assert_equal "test", p.name
                    assert_equal @stream, p.stream
                end
                it "returns the property" do
                    property = @task_context.add_property(@stream)
                    assert_equal "test", property.name
                    assert_equal property, @task_context.property("test")
                end
                it "raises if the property is already defined" do
                    @task_context.add_property(@stream)
                    e = assert_raises(ArgumentError) do
                        @task_context.add_property(@stream)
                    end
                    assert_equal "property 'test' already exists, probably "\
                        "from a different log stream", e.message
                end
                it "calls the on_reachable blocks" do
                    mock = flexmock
                    mock.should_receive(:called).with("test").once
                    @task_context.on_property_reachable do |name|
                        mock.called(name)
                    end
                    @task_context.add_property(@stream)
                end
                it "accepts to be called with a first argument" do
                    property = @task_context.add_property(flexmock, @stream)
                    assert_equal @stream, property.stream
                    assert_equal property, @task_context.property("test")
                end
            end

            describe "#add_port" do
                before do
                    dir = make_tmpdir
                    registry = Typelib::CXXRegistry.new
                    logfile = Pocolog::Logfiles.create(
                        File.join(dir, "somefile.0.log"), registry
                    )
                    @stream = logfile.create_stream "test_stream", "/double",
                                                    "rock_task_object_name" => "test"
                end

                it "registers a new port backed by the stream" do
                    @task_context.add_port(@stream)
                    p = @task_context.port("test")
                    assert_equal @task_context, p.task
                    assert_equal "test", p.name
                    assert_equal @stream, p.stream
                end
                it "returns the port" do
                    port = @task_context.add_port(@stream)
                    assert_equal "test", port.name
                    assert_equal port, @task_context.port("test")
                end
                it "raises if the port is already defined" do
                    @task_context.add_port(@stream)
                    e = assert_raises(ArgumentError) do
                        @task_context.add_port(@stream)
                    end
                    assert_equal "port 'test' already exists, probably "\
                        "from a different log stream", e.message
                end
                it "calls the on_reachable blocks" do
                    mock = flexmock
                    mock.should_receive(:called).with("test").once
                    @task_context.on_port_reachable do |name|
                        mock.called(name)
                    end
                    @task_context.add_port(@stream)
                end
                it "accepts to be called with a first argument" do
                    port = @task_context.add_port(flexmock, @stream)
                    assert_equal @stream, port.stream
                    assert_equal port, @task_context.port("test")
                end
            end
        end
    end
end
