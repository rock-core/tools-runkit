# frozen_string_literal: true

require "runkit/test"

module Runkit
    module RubyTasks
        describe StubTaskContext do
            before do
                Runkit.load_typekit "base"
                @loader = OroGen::Loaders::RTT.new(Runkit.orocos_target)
                @loader.typekit_model_from_name("std")
                @loader.typekit_model_from_name("base")
            end

            it "stubs the operations" do
                project = OroGen::Spec::Project.new(@loader)
                task_m = OroGen::Spec::TaskContext.new(project, "test")
                task_m.operation("some")

                task = StubTaskContext.from_orogen_model("test", task_m)
                flexmock(task).should_receive(:some).and_return(42)
                assert_equal 42, task.operation("some").callop
                assert_equal [SEND_SUCCESS, 42], task.operation("some").sendop.collect
            end

            it "stubs dynamic property operations to write the property" do
                project = OroGen::Spec::Project.new(@loader)
                task_m = OroGen::Spec::TaskContext.new(project, "test")
                task_m.property("some", "/int").dynamic

                task = StubTaskContext.from_orogen_model("test", task_m)
                task.configure
                task.start
                flexmock(task).should_receive(:__orogen_setSome).once.pass_thru
                task.property("some").write(42)
                assert_equal 42, task.some
            end
        end
    end
end
