$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'orocos'
require 'minitest/spec'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')
ENV['PKG_CONFIG_PATH'] += ":#{File.join(WORK_DIR, "prefix", 'lib', 'pkgconfig')}"

avahi_options = { :searchdomains => [ "_orocosrbtest._tcp" ] }

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
                Orocos::CORBA::name_service.get("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.deregister("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.register(nil,"foo#{Orocos::Namespace::DELIMATOR}foo")
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
    before do 
        describe "when accessed before CORBA layer is initialized" do
            it "must raise Orocos::NotInitialized" do 
                service = Orocos::CORBA::NameService.new
                assert_raises(Orocos::NotInitialized) do
                    service.names
                end
                assert_raises(Orocos::NotInitialized) do
                    service.ior("bla")
                end
                assert_raises(Orocos::NotInitialized) do
                    service.deregister("bla")
                end
            end
        end
        Orocos.initialize
    end

    after do
        Orocos.clear
    end

    describe "when orocos is initialized" do
        it "must be registered as global CORBA name service" do 
            assert(Orocos::CORBA::name_service.is_a?(Orocos::CORBA::NameService))
        end
    end

    describe "when unreachable namservice is accessed" do
        it "must raise ComError" do 
            assert_raises(Orocos::CORBA::ComError) do
                service = Orocos::CORBA::NameService.new("UNREACHABLE_HOST_NAME.does.not.exist")
                service.names
            end
        end
        it "must raise ComError" do 
            assert_raises(Orocos::CORBA::ComError) do
                service = Orocos::CORBA::NameService.new("UNREACHABLE_HOST_NAME.does.not.exist")
                service.validate
            end
        end
    end

    describe "when asked for task context names" do
        it "must return all registered task context names" do 
            assert(Orocos::CORBA::name_service.names.size >= 0)
        end
    end

    describe "when asked for ior" do
        it "must return the ior" do 
            Orocos::CORBA::name_service.do_task_context_names.each do |name|
                assert(Orocos::CORBA::name_service.ior(name))
            end
        end
    end

    describe "when asked for an old task" do
        it "must raise an Orocos::NotFound" do
            assert_raises(Orocos::NotFound) do
                Orocos::CORBA::name_service.get("IOR:010000001f00000049444c3a5254542f636f7262612f435461736b436f6e746578743a312e300000010000000000000064000000010102000d00000031302e3235302e332e3136300000868a0e000000feb302845000007b18000000000000000200000000000000080000000100000000545441010000001c00000001000000010001000100000001000105090101000100000009010100")
            end
        end
    end

    describe "when asked for a wrong ior" do
        it "must raise an Orocos::NotFound" do 
            assert_raises(Orocos::NotFound) do
                Orocos::CORBA::name_service.ior("foo")
            end
        end
    end

    describe "when asked for the ip" do
        it "must return the ip" do 
            assert(Orocos::CORBA::name_service.ip)
        end
    end

    describe "when asked for the port" do
        it "must return the port" do
            assert(Orocos::CORBA::name_service.port)
        end
    end

    describe "when wrong name space is used" do
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.get("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.deregister("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.ior("foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
        it "must raise an ArgumentError" do 
            assert_raises(ArgumentError) do
                Orocos::CORBA::name_service.register(nil,"foo#{Orocos::Namespace::DELIMATOR}foo")
            end
        end
    end

    describe "when remote task is reachable" do
        it "must return its name" do
            Orocos.run('simple_source') do
                assert(Orocos::CORBA::name_service.names.include?("/simple_source_source"))
            end
        end
        it "must return its ior" do
            Orocos.run('simple_source') do
                assert(Orocos::CORBA::name_service.ior("simple_source_source"))
            end
        end
        it "must return its interface" do
            Orocos.run('simple_source') do
                assert(Orocos::CORBA::name_service.get("simple_source_source"))
            end
        end
        it "must be able to scope with name spaces" do
            service = Orocos::CORBA::NameService.new
            service.ip = "127.0.0.1"
            Orocos.run('simple_source') do
                task = service.get("127.0.0.1#{Orocos::Namespace::DELIMATOR}simple_source_source")
                assert(task)
                assert_equal("127.0.0.1",task.namespace)
                assert_equal("127.0.0.1/simple_source_source",task.name)

                task = Orocos::CORBA::name_service.get("#{Orocos::Namespace::DELIMATOR}simple_source_source")
                assert task
                assert_equal "",task.namespace
                assert_equal("/simple_source_source",task.name)
            end
        end
        it "must be able to deregister and reregister it to the name service" do
            Orocos.run('simple_source') do
                task = Orocos::CORBA.name_service.get("simple_source_source")
                assert(Orocos::CORBA::name_service.names.include?("/simple_source_source"))
                Orocos::CORBA::name_service.deregister("/simple_source_source")
                assert(!Orocos::CORBA::name_service.names.include?("/simple_source_source"))
                Orocos::CORBA::name_service.register(task)
                assert(Orocos::CORBA::name_service.names.include?("/simple_source_source"))
                #check if register does not produce an error if task is already bound 
                Orocos::CORBA::name_service.register(task)
            end
        end
        it "must iterate over it" do
            Orocos.run('simple_source') do
                tasks = []
                Orocos::CORBA.name_service.each_task do |task|
                    tasks << task
                end
                assert tasks.map(&:name).include?("/simple_source_source")
            end
        end
        it "must iterate over running tasks" do
            Orocos.run('simple_source') do
                task = Orocos::CORBA.name_service.get "simple_source_source"
                task.configure
                task.start
                task = Orocos.name_service.find_one_running("simple_source_source")
                assert task
            end
        end
        it "must raise if more than one tasks provides the given model" do
            Orocos.run('simple_source') do
                assert_raises(Orocos::NotFound) do
                    assert Orocos::CORBA.name_service.get_provides "simple_source::source"
                end
            end
        end
        it "must return the right task which provides the given model" do
            Orocos.run('simple_source') do
                task = Orocos::CORBA.name_service.get "simple_source_source"
                task2 = Orocos::CORBA.name_service.get "fast_source"
                Orocos::CORBA.name_service.deregister task
                assert_equal task2.name, Orocos.name_service.get_provides("simple_source::source").name
                Orocos::CORBA.name_service.register task
            end
        end
    end

    describe Orocos::Avahi::NameService do
        avahi = begin
                     require 'servicediscovery'
                     true
                 rescue LoadError
                     Orocos.warn "NameService: 'distributed_nameserver' needs to be installed for Avahi nameservice test"
                 end
        if avahi
            before do
                Orocos.initialize
                @service = Orocos::Avahi::NameService.new("_orocosrb._tcp")
            end

            describe "when a task is running" do 
                it "it must be possible to register the task to the Avahi name service" do 
                    Orocos.run('simple_source') do
                        task = Orocos::CORBA::name_service.get("simple_source_source")
                        @service.register(task)
                        sleep 1.0
                        assert @service.names.include?(task.name)
                        assert_equal task.ior,@service.ior(task.name)
                        assert @service.get task.name
                    end
                end
            end
        end
    end

    describe Orocos::NameService do
        before do
            Orocos.initialize
        end

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
end
