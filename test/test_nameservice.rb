require 'orocos/test'

describe Orocos::Local::NameService do
    before do 
        @task = Orocos::TaskContextBase.new("Local/dummy")
        @service = Orocos::Local::NameService.new [@task]
    end

    after do
        Orocos.clear
    end

    describe "when asked for task names" do
        it "must return all registered task names" do 
            assert(@service.names.include?("Local/dummy"))
        end
    end

    describe "when asked for task" do
        it "must return the task" do 
            assert_equal(@task,@service.get("dummy"))
        end
    end

    describe "when asked for a wrong task" do
        it "must raise Orocos::NotFound" do 
            assert_raises(Orocos::NotFound) do
                @service.get("foo")
            end
        end
    end

    describe "when wrong name space is used" do
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA.name_service.get("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA.name_service.deregister("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA.name_service.register(nil,"foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "when new tasks is bound" do
        it "it must return them the next time when asked for task names" do 
            task = Orocos::TaskContextBase.new("Local/dummy2")
            @service.register task
            assert(@service.names.include?("Local/dummy2"))
            assert_equal(task,@service.get(@service.map_to_namespace("dummy2")))
            assert_equal(task,@service.get("dummy2"))
            @service.deregister "dummy2"
            assert(!@service.names.include?("dummy2"))
        end
    end
end

describe Orocos::CORBA::NameService do
    attr_reader :name_service
    before do
        @name_service = Orocos::CORBA::NameService.new
    end

    describe "the global CORBA name service" do
        it "is registered as a global name service" do 
            assert(Orocos::CORBA.name_service.is_a?(Orocos::CORBA::NameService))
        end
    end

    it "raises ComError if the name service host does not exist" do 
        assert_raises(Orocos::CORBA::ComError) do
            service = Orocos::CORBA::NameService.new("UNREACHABLE_HOST_NAME.does.not.exist")
            service.names
        end
    end

    it "returns the list of all registered task context names" do
        new_ruby_task_context 'orocosrb-test'
        assert name_service.names.include?('/orocosrb-test')
    end

    describe "#get" do
        it "resolves an existing task" do
            task = new_ruby_task_context 'orocosrb-test'
            assert_equal task, name_service.get('orocosrb-test')
        end

        it "raises NotFound for an unreachable IOR" do
            task = new_ruby_task_context 'orocosrb-test'
            ior = task.ior
            task.dispose
            assert_raises(Orocos::NotFound) do
                name_service.get(ior: ior)
            end
        end

        it "registers the task under its own namespace if its name does not provide one" do
            new_ruby_task_context 'orocosrb-test'
            name_service = Orocos::CORBA::NameService.new('localhost')
            task = name_service.get("orocosrb-test")
            assert_equal "localhost", task.namespace
            assert_equal "localhost/orocosrb-test", task.name
        end

        it "resolves a task whose namespace matches its own" do
            new_ruby_task_context 'orocosrb-test'
            name_service = Orocos::CORBA::NameService.new('localhost')
            task = name_service.get("localhost/orocosrb-test")
            assert_equal "localhost", task.namespace
            assert_equal "localhost/orocosrb-test", task.name
        end

        it "does not add its own namespace if the task name refers to root namespace" do
            task = new_ruby_task_context 'orocosrb-test'
            task = name_service.get("/orocosrb-test")
            assert_equal "", task.namespace
            assert_equal "/orocosrb-test", task.name
        end

        it "raises an ArgumentError if the namespace does not match the name service's" do 
            task = new_ruby_task_context 'orocosrb-test'
            assert_raises(ArgumentError) do
                name_service.get("foo/orocosrb-test")
            end
        end
    end

    describe "#ior" do
        it "returns the task's IOR" do 
            task = new_ruby_task_context 'orocosrb-test'
            assert_equal task.ior, name_service.ior('orocosrb-test')
        end

        it "raises Orocos::NotFound for an unknown task" do 
            assert_raises(Orocos::NotFound) do
                name_service.ior("invalid_ior")
            end
        end
        it "raises ArgumentError if the namespace does not match" do 
            assert_raises(ArgumentError) do
                name_service.ior("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#ip" do
        it "returns an empty string by default" do
            assert_equal "", name_service.ip
        end

        it "returns the name service IP" do
            name_service.ip = 'localhost'
            assert_equal 'localhost', name_service.ip
        end
    end

    describe "#port" do
        it "returns an empty port" do
            assert_equal "", name_service.port
        end
    end

    describe "#register" do
        it "registers a task on the name service" do
            task = new_ruby_task_context 'orocosrb-test'
            name_service.deregister(task.name)
            name_service.register(task)
            assert_equal task, name_service.get(task.name)
        end

        it "raises ArgumentError if the namespace does not match" do 
            assert_raises(ArgumentError) do
                name_service.register(nil,"foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#deregister" do
        it "deregisters a name from the name service" do
            task = new_ruby_task_context 'orocosrb-test'
            name_service.deregister(task.name)
            assert_raises(Orocos::NotFound) { name_service.get(task.name) }
        end
        it "raises ArgumentError if the namespace does not match" do 
            assert_raises(ArgumentError) do
                name_service.deregister("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "#each_task" do
        it "iterates over existing tasks" do
            task = new_ruby_task_context 'orocosrb-test'
            Orocos::CORBA.name_service.enum_for(:each_task).to_a.
                include?(task)
        end
    end

    describe "#find_one_running" do
        attr_reader :task
        before do
            @task = new_ruby_task_context 'orocosrb-test'
        end
        it "returns a existing running task" do
            task.configure
            task.start
            assert_equal task, name_service.find_one_running('orocosrb-test')
        end
        it "ignores non-existing tasks if others exist and are running" do
            task.configure
            task.start
            assert_equal task,
                name_service.find_one_running('orocosrb-test', 'does_not_exist_either')
        end
        it "raises NotFound if all tasks do not exist" do
            error = assert_raises(Orocos::NotFound) do
                name_service.find_one_running('does_not_exist', 'does_not_exist_either')
            end
            assert_equal "cannot find any tasks matching does_not_exist, does_not_exist_either",
                error.message
        end
        it "raises NotFound if all tasks are not running" do
            other_task = new_ruby_task_context 'orocosrb-test-other'
            error = assert_raises(Orocos::NotFound) do
                name_service.find_one_running('orocosrb-test', 'orocosrb-test-other')
            end
            assert_equal "none of orocosrb-test, orocosrb-test-other are running",
                error.message

            task.configure
            assert_raises(Orocos::NotFound) { name_service.find_one_running('orocosrb-test') }
        end
    end

    describe "get_provides" do
        attr_reader :model
        before do
            project = OroGen::Spec::Project.new(Orocos.default_loader)
            @model = OroGen::Spec::TaskContext.new(project, 'orocosrb::Test')
        end
        it "raises if more than one task provides the requested model" do
            new_ruby_task_context 'orocosrb-test-first', model: model
            new_ruby_task_context 'orocosrb-test-second', model: model
            assert_raises(Orocos::NotFound) do
                name_service.get_provides 'orocosrb::Test'
            end
        end
        it "returns a matching task" do
            task = new_ruby_task_context 'orocosrb-test', model: model
            assert_equal task, name_service.get_provides('orocosrb::Test')
        end
        it "raises NotFound if no tasks match the requested model" do
            assert_raises(Orocos::NotFound) do
                name_service.get_provides 'orocosrb::Test'
            end
        end
        it "matches purely on name" do
            assert_raises(Orocos::NotFound) do
                name_service.get_provides 'does_not_exist'
            end
        end
        it "is used by TaskContext.get(provides: ...)" do
            flexmock(Orocos.name_service).should_receive(:get_provides).
                with('model::Name').and_return(task = flexmock)
            assert_equal task, Orocos::TaskContext.get(provides: 'model::Name')
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

describe Orocos::Avahi::NameService do
    before do
        begin
            require 'servicediscovery'
        rescue LoadError
            skip "avahi support not available, install the tools/service_discovery package"
        end
        @service = Orocos::Avahi::NameService.new("_orocosrb._tcp")
    end

    it "allows registering a task explicitely" do
        task = new_ruby_task_context 'orocosrb-test'
        @service.register(task)
        while !@service.names.include?(task.name)
            sleep 0.01
        end
        assert @service.names.include?(task.name)
        assert_equal task, @service.get(task.name)
        assert_equal task.ior, @service.ior(task.name)
    end
end

describe Orocos::NameService do
    describe "when orocos is intitialized" do 
        it "the corba name service should be available" do 
            assert Orocos.name_service.initialized?
            assert Orocos.name_service.find(Orocos::CORBA::NameService)
            assert Orocos.name_service.include?(Orocos::CORBA::NameService)
        end
    end

    describe "when a task is running" do 
        it "it must return its name and interface" do 
            Orocos.run('simple_source') do
                assert Orocos.name_service.names.include?("/simple_source_source")
                task = Orocos.name_service.get(::Orocos::Namespace::DELIMATOR+"simple_source_source")
                ior = Orocos::CORBA.name_service.ior(::Orocos::Namespace::DELIMATOR+"simple_source_source")
                assert_equal ior, task.ior
            end
        end
    end
end
