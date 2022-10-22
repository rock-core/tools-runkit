# frozen_string_literal: true

require "runkit/test"

describe Runkit::Local::NameService do
    before do
        @task = Runkit::TaskContextBase.new("Local/dummy")
        @service = Runkit::Local::NameService.new [@task]
    end

    after do
        Runkit.clear
    end

    describe "when asked for task names" do
        it "must return all registered task names" do
            assert(@service.names.include?("Local/dummy"))
        end
    end

    describe "when asked for task" do
        it "must return the task" do
            assert_equal(@task, @service.get("dummy"))
        end
    end

    describe "when asked for a wrong task" do
        it "must raise Runkit::NotFound" do
            assert_raises(Runkit::NotFound) do
                @service.get("foo")
            end
        end
    end

    describe "when wrong name space is used" do
        it "must raise an ArgumentError" do
            assert_raises(ArgumentError) do
                Runkit::CORBA.name_service.get("foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do
            assert_raises(ArgumentError) do
                Runkit::CORBA.name_service.deregister("foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do
            assert_raises(ArgumentError) do
                Runkit::CORBA.name_service.register(nil, "foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "when new tasks is bound" do
        it "it must return them the next time when asked for task names" do
            task = Runkit::TaskContextBase.new("Local/dummy2")
            @service.register task
            assert(@service.names.include?("Local/dummy2"))
            assert_equal(task, @service.get(@service.map_to_namespace("dummy2")))
            assert_equal(task, @service.get("dummy2"))
            @service.deregister "dummy2"
            assert(!@service.names.include?("dummy2"))
        end
    end
end

describe Runkit::CORBA::NameService do
    attr_reader :name_service
    before do
        @name_service = Runkit::CORBA::NameService.new
    end

    describe "the global CORBA name service" do
        it "is registered as a global name service" do
            assert(Runkit::CORBA.name_service.is_a?(Runkit::CORBA::NameService))
        end
    end

    it "raises ComError if the name service host does not exist" do
        assert_raises(Runkit::CORBA::ComError) do
            service = Runkit::CORBA::NameService.new("UNREACHABLE_HOST_NAME.does.not.exist")
            service.names
        end
    end

    it "returns the list of all registered task context names" do
        new_ruby_task_context "runkitrb-test"
        assert name_service.names.include?("/runkitrb-test")
    end

    describe "#get" do
        it "resolves an existing task" do
            task = new_ruby_task_context "runkitrb-test"
            assert_equal task, name_service.get("runkitrb-test")
        end

        it "raises NotFound for an unreachable IOR" do
            task = new_ruby_task_context "runkitrb-test"
            ior = task.ior
            task.dispose
            assert_raises(Runkit::NotFound) do
                name_service.get(ior: ior)
            end
        end

        it "registers the task under its own namespace if its name does not provide one" do
            new_ruby_task_context "runkitrb-test"
            name_service = Runkit::CORBA::NameService.new("localhost")
            task = name_service.get("runkitrb-test")
            assert_equal "localhost", task.namespace
            assert_equal "localhost/runkitrb-test", task.name
        end

        it "resolves a task whose namespace matches its own" do
            new_ruby_task_context "runkitrb-test"
            name_service = Runkit::CORBA::NameService.new("localhost")
            task = name_service.get("localhost/runkitrb-test")
            assert_equal "localhost", task.namespace
            assert_equal "localhost/runkitrb-test", task.name
        end

        it "does not add its own namespace if the task name refers to root namespace" do
            task = new_ruby_task_context "runkitrb-test"
            task = name_service.get("/runkitrb-test")
            assert_equal "", task.namespace
            assert_equal "/runkitrb-test", task.name
        end

        it "raises an ArgumentError if the namespace does not match the name service's" do
            task = new_ruby_task_context "runkitrb-test"
            assert_raises(ArgumentError) do
                name_service.get("foo/runkitrb-test")
            end
        end
    end

    describe "#ior" do
        it "returns the task's IOR" do
            task = new_ruby_task_context "runkitrb-test"
            assert_equal task.ior, name_service.ior("runkitrb-test")
        end

        it "raises Runkit::NotFound for an unknown task" do
            assert_raises(Runkit::NotFound) do
                name_service.ior("invalid_ior")
            end
        end
        it "raises ArgumentError if the namespace does not match" do
            assert_raises(ArgumentError) do
                name_service.ior("foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#ip" do
        it "returns an empty string by default" do
            assert_equal "", name_service.ip
        end

        it "returns the name service IP" do
            name_service.ip = "localhost"
            assert_equal "localhost", name_service.ip
        end
    end

    describe "#port" do
        it "returns an empty port" do
            assert_equal "", name_service.port
        end
    end

    describe "#register" do
        it "registers a task on the name service" do
            task = new_ruby_task_context "runkitrb-test"
            name_service.deregister(task.name)
            name_service.register(task)
            assert_equal task, name_service.get(task.name)
        end

        it "raises ArgumentError if the namespace does not match" do
            assert_raises(ArgumentError) do
                name_service.register(nil, "foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#deregister" do
        it "deregisters a name from the name service" do
            task = new_ruby_task_context "runkitrb-test"
            name_service.deregister(task.name)
            assert_raises(Runkit::NotFound) { name_service.get(task.name) }
        end
        it "raises ArgumentError if the namespace does not match" do
            assert_raises(ArgumentError) do
                name_service.deregister("foo#{Runkit::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#each_task" do
        it "iterates over existing tasks" do
            task = new_ruby_task_context "runkitrb-test"
            Runkit::CORBA.name_service.enum_for(:each_task).to_a
                         .include?(task)
        end
    end

    describe "#find_one_running" do
        attr_reader :task
        before do
            @task = new_ruby_task_context "runkitrb-test"
        end
        it "returns a existing running task" do
            task.configure
            task.start
            assert_equal task, name_service.find_one_running("runkitrb-test")
        end
        it "ignores non-existing tasks if others exist and are running" do
            task.configure
            task.start
            assert_equal task,
                         name_service.find_one_running("runkitrb-test", "does_not_exist_either")
        end
        it "raises NotFound if all tasks do not exist" do
            error = assert_raises(Runkit::NotFound) do
                name_service.find_one_running("does_not_exist", "does_not_exist_either")
            end
            assert_equal "cannot find any tasks matching does_not_exist, does_not_exist_either",
                         error.message
        end
        it "raises NotFound if all tasks are not running" do
            other_task = new_ruby_task_context "runkitrb-test-other"
            error = assert_raises(Runkit::NotFound) do
                name_service.find_one_running("runkitrb-test", "runkitrb-test-other")
            end
            assert_equal "none of runkitrb-test, runkitrb-test-other are running",
                         error.message

            task.configure
            assert_raises(Runkit::NotFound) { name_service.find_one_running("runkitrb-test") }
        end
    end

    describe "get_provides" do
        attr_reader :model
        before do
            project = OroGen::Spec::Project.new(Runkit.default_loader)
            @model = OroGen::Spec::TaskContext.new(project, "runkitrb::Test")
        end
        it "raises if more than one task provides the requested model" do
            new_ruby_task_context "runkitrb-test-first", model: model
            new_ruby_task_context "runkitrb-test-second", model: model
            assert_raises(Runkit::NotFound) do
                name_service.get_provides "runkitrb::Test"
            end
        end
        it "returns a matching task" do
            task = new_ruby_task_context "runkitrb-test", model: model
            assert_equal task, name_service.get_provides("runkitrb::Test")
        end
        it "raises NotFound if no tasks match the requested model" do
            assert_raises(Runkit::NotFound) do
                name_service.get_provides "runkitrb::Test"
            end
        end
        it "matches purely on name" do
            assert_raises(Runkit::NotFound) do
                name_service.get_provides "does_not_exist"
            end
        end
        it "is used by TaskContext.get(provides: ...)" do
            flexmock(Runkit.name_service).should_receive(:get_provides)
                                         .with("model::Name").and_return(task = flexmock)
            assert_equal task, Runkit::TaskContext.get(provides: "model::Name")
        end
    end

    describe "#bind" do
        it "registers an existing task under an arbitrary name" do
            task = new_ruby_task_context "test"
            name_service.bind(task, "alias")
            assert_equal task, name_service.get("alias")
        end
    end
end

describe Runkit::Avahi::NameService do
    before do
        begin
            require "servicediscovery"
        rescue LoadError
            skip "avahi support not available, install the tools/service_discovery package"
        end
        @service = Runkit::Avahi::NameService.new("_runkitrb._tcp")
    end

    def wait_for_publication(name, expected_ior, timeout: 10)
        start = Time.now
        while Time.now - start < timeout
            ior = nil
            begin
                capture_subprocess_io { ior = @service.ior(name) }
            rescue Runkit::NotFound
            end

            return if ior == expected_ior

            sleep 0.1
        end

        if ior
            flunk("resolved #{name}, but it does not match the expected IOR")
        else
            flunk("cannot resolve #{name}")
        end
    end

    it "allows registering a task explicitely and updates it" do
        task = new_ruby_task_context "runkitrb-test"
        @service.register(task)
        wait_for_publication("runkitrb-test", task.ior)
        assert @service.names.include?(task.name)
        capture_subprocess_io do
            assert_equal task, @service.get(task.name)
        end

        task.dispose

        # This would be better split into two tests, but the avahi name service
        # as it is does not accept de-registering anything ... avahi then
        # refuses to re-register an existing service (which is a good behaviour)

        task = new_ruby_task_context "runkitrb-test"
        @service.register(task)
        wait_for_publication("runkitrb-test", task.ior)
        assert @service.names.include?(task.name)
        capture_subprocess_io do
            assert_equal task, @service.get(task.name)
        end
    end
end

describe Runkit::NameService do
    describe "when runkit is intitialized" do
        it "the corba name service should be available" do
            assert Runkit.name_service.initialized?
            assert Runkit.name_service.find(Runkit::CORBA::NameService)
            assert Runkit.name_service.include?(Runkit::CORBA::NameService)
        end
    end

    describe "when a task is running" do
        it "it must return its name and interface" do
            Runkit.run("simple_source") do
                assert Runkit.name_service.names.include?("/simple_source_source")
                task = Runkit.name_service.get(::Runkit::Namespace::DELIMATOR + "simple_source_source")
                ior = Runkit::CORBA.name_service.ior(::Runkit::Namespace::DELIMATOR + "simple_source_source")
                assert_equal ior, task.ior
            end
        end
    end
end
