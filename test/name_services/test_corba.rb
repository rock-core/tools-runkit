# frozen_string_literal: true

require "runkit/test"

module Runkit
    module NameServices
        describe CORBA do
            attr_reader :name_service

            before do
                @name_service = spawn_omninames
            end

            after do
                ::Process.kill "INT", @pid
                ::Process.waitpid @pid
            end

            it "raises ComError if the name service host does not exist" do
                assert_raises(::Runkit::CORBA::ComError) do
                    service = CORBA.new("UNREACHABLE_HOST_NAME.does.not.exist")
                    service.names
                end
            end

            it "returns the list of all registered task context names" do
                task = new_ruby_task_context "test"
                @name_service.register task
                assert_includes name_service.names, "test"
            end

            it "returns an empty list if there are no task contexts" do
                assert_equal [], name_service.names
            end

            describe "#get" do
                it "resolves an existing task" do
                    task = new_ruby_task_context "test"
                    name_service.register task
                    assert_equal task, name_service.get("test")
                end
            end

            describe "#ior" do
                it "returns the task's IOR" do
                    task = new_ruby_task_context "runkitrb_test"
                    name_service.register task
                    assert_equal task.ior, name_service.ior("runkitrb_test")
                end

                it "raises NotFound for an unknown task" do
                    assert_raises(NotFound) do
                        name_service.ior("invalid_ior")
                    end
                end

                it "raises NotFound for an unreachable IOR" do
                    task = new_ruby_task_context "runkitrb_test"
                    ior = task.ior
                    task.dispose
                    assert_raises(Runkit::NotFound) do
                        name_service.ior(ior)
                    end
                end
            end

            describe "#ip" do
                it "returns an empty string by default" do
                    assert_equal "", CORBA.new.ip
                end

                it "returns the name service IP" do
                    name_service.ip = "localhost"
                    assert_equal "localhost", name_service.ip
                end

                it "returns the name service IP and port if given" do
                    name_service.ip = "localhost:54343"
                    assert_equal "localhost:54343", name_service.ip
                end
            end

            describe "#port" do
                it "returns an empty port by default" do
                    assert_equal "", name_service.port
                end
            end

            describe "#register" do
                it "registers a task on the name service" do
                    task = new_ruby_task_context "runkitrb_test"
                    name_service.deregister(task.name)
                    name_service.register(task)
                    assert_equal task, name_service.get(task.name)
                end
            end

            describe "#deregister" do
                it "deregisters a name from the name service" do
                    task = new_ruby_task_context "runkitrb_test"
                    name_service.deregister(task.name)
                    assert_raises(Runkit::NotFound) { name_service.get(task.name) }
                end
            end

            describe "#each_task" do
                it "iterates over existing tasks" do
                    task = new_ruby_task_context "runkitrb_test"
                    name_service.register(task)
                    assert_includes name_service.each_task.to_a, task
                end
            end

            describe "#bind" do
                it "registers an existing task under an arbitrary name" do
                    task = new_ruby_task_context "test"
                    name_service.register(task, name: "alias")
                    assert_equal task, name_service.get("alias")
                end
            end

            def spawn_omninames
                tcp = TCPServer.new(0)
                port = tcp.addr[1]
                tcp.close
                datadir = make_tmpdir
                @pid = spawn(
                    "omniNames", "-always", "-start", port.to_s, "-datadir", datadir,
                    out: "/dev/null", err: "/dev/null"
                )

                name_service = CORBA.new
                name_service.ip = "localhost:#{port}"

                deadline = Time.now + 5
                while Time.now < deadline

                    begin
                        name_service.names
                        return name_service
                    rescue ComError # rubocop:disable Lint/SuppressedException
                    end
                end

                flunk("could not get a valid omniNames running on port #{port}")
            end
        end
    end
end
