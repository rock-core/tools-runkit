# frozen_string_literal: true

require "runkit/test"

module Runkit
    module NameServices
        describe Local do
            before do
                @task = TaskContextBase.new("dummy")
                @service = Local.new [@task]
            end

            it "returns all registered task names" do
                assert_includes @service.names, "dummy"
            end

            it "returns a registered task by name" do
                assert_equal @task, @service.get("dummy")
            end

            it "raises NotFound for a non-registered task" do
                assert_raises(NotFound) { @service.get("foo") }
            end

            it "lets the caller dynamically register new tasks" do
                task = TaskContextBase.new("dummy2")
                @service.register task
                assert_includes @service.names, "dummy2"
                assert_equal task, @service.get("dummy2")
            end

            it "lets the caller dynamically deregister tasks" do
                task = TaskContextBase.new("dummy2")
                @service.register task
                @service.deregister "dummy2"
                refute_includes @service.names, "dummy2"
            end
        end
    end
end
