require 'orocos/test'
require 'orocos/log'
require 'pocolog'

module Orocos
    module Log
        describe Replay do
            before do
                @log_replay = Replay.new
            end

            describe "#load_task_from_stream" do
                before do
                    dir = make_tmpdir
                    registry = Typelib::CXXRegistry.new
                    logfile = Pocolog::Logfiles.create(
                            File.join(dir, 'somefile.0.log'), registry)
                    @stream = logfile.create_stream 'test.stream', '/double'
                end

                it "uses the rock_task_name metadata if present" do
                    @stream.metadata['rock_task_name'] = "valid_metadata"
                    task = @log_replay.load_task_from_stream(@stream, '/some/path/to/port.0.log')
                    assert_equal "/valid_metadata", task.name
                end
                it "ignores an invalid rock_task_name metadata, using the stream name instead" do
                    @stream.metadata['rock_task_name'] = "///"
                    task = @log_replay.load_task_from_stream(@stream, '/some/path/to/port.0.log')
                    assert_equal "/test", task.name
                end
                it "guesses the stream type to 'port' if the logfile's name is not properties.0.log" do
                    flexmock(TaskContext).new_instances.should_receive(:add_stream).
                        with(@stream, type: 'port').once
                    @log_replay.load_task_from_stream(@stream, '/some/path/to/port.0.log')
                end
                it "guesses the stream type to 'property' if the logfile's name is properties.0.log" do
                    flexmock(TaskContext).new_instances.should_receive(:add_stream).
                        with(@stream, type: 'property').once
                    @log_replay.load_task_from_stream(@stream, '/some/path/to/properties.0.log')
                end
                it "passes the type from the rock_stream_type metadata if it is present" do
                    @stream.metadata['rock_stream_type'] = 'property'
                    flexmock(TaskContext).new_instances.should_receive(:add_stream).
                        with(@stream, type: 'property').once
                    @log_replay.load_task_from_stream(@stream, '/some/path/to/port.0.log')
                end
            end

            describe "#align" do
                before do
                    dir = make_tmpdir
                    registry = Typelib::CXXRegistry.new
                    logfile = Pocolog::Logfiles.create(
                            File.join(dir, 'somefile'), registry)
                    logfile.create_stream 'test_stream', '/double',
                        'rock_task_name' => 'task_name',
                        'rock_task_object_name' => 'port_name',
                        'rock_cxx_type_name' => '/double',
                        'rock_stream_type' => 'port'
                    logfile.close
                    logfile = Pocolog::Logfiles.open(File.join(dir, 'somefile.0.log'))
                    @stream = logfile.streams.first
                end

                it "aligns empty streams" do
                    @log_replay.load_task_from_stream(@stream, "log_file")
                    @log_replay.align
                    assert @log_replay.used_streams.include?(@stream)
                end
            end
        end
    end
end
