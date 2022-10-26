# frozen_string_literal: true

require "runkit/test"
require "runkit/ruby_tasks/process"

module Runkit
    module RubyTasks
        describe Process do
            attr_reader :process

            before do
                project = OroGen::Spec::Project.new(Runkit.default_loader)
                project.task_context "Task"
                deployment_m = project.deployment "test" do
                    task "task", "Task"
                end
                @process = Process.new(nil, "test", deployment_m)
            end

            describe "#spawn" do
                it "spawns a RubyTask per task described in the oroGen model" do
                    process.spawn
                    assert process.wait_running(10)
                    task = process.task "task"
                    task.configure
                end
                it "applies name mappings" do
                    process.map_name "task", "mytask"
                    process.spawn
                    task = process.task "mytask"
                    task.configure
                end
            end
        end
    end
end
