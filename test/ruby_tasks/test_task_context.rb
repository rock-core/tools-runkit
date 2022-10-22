# frozen_string_literal: true

require "runkit/test"

describe Runkit::RubyTasks::TaskContext do
    before do
        Runkit.load_typekit "base"
    end

    it "should be registered on the name server" do
        task = new_ruby_task_context("task")
        assert Runkit.name_service.get("task")
    end

    it "should refer to a LocalTaskContext object that refers to it back" do
        task = new_ruby_task_context("task")
        assert_same task, task.instance_variable_get(:@local_task).remote_task
    end

    it "can create output ports" do
        task = new_ruby_task_context("producer")
        port = task.create_output_port("p", "/int32_t")
        assert_kind_of Runkit::OutputPort, port
        assert_equal task, port.task
        assert_equal "p", port.name

        assert task.has_port?("p")
        assert_kind_of Runkit::OutputPort, task.port("p")
        assert_equal "/int32_t", task.port("p").runkit_type_name
    end

    it "can create input ports" do
        task = new_ruby_task_context("producer")
        port = task.create_input_port("p", "/int32_t")

        assert_kind_of Runkit::InputPort, port
        assert task.has_port?("p")
        assert_kind_of Runkit::InputPort, task.port("p")
        assert_equal "/int32_t", task.port("p").runkit_type_name
    end

    it "can write and read on ports" do
        producer = new_ruby_task_context("producer")
        out_p = producer.create_output_port("p", "/int32_t")
        consumer = new_ruby_task_context("consumer")
        in_p = consumer.create_input_port("p", "/int32_t")

        out_p.connect_to in_p
        out_p.write 10
        assert_equal 10, in_p.read
    end

    describe "properties" do
        it "creates them" do
            task = new_ruby_task_context("task")
            property = task.create_property("prop", "int")
            assert_kind_of Runkit::Property, property
            assert_same property, task.property("prop")
            assert task.has_property?("prop")
        end
        it "initializes them with a sample by default" do
            Runkit.load_typekit "echo"
            opaque_t       = Runkit.registry.get "/OpaquePoint"
            intermediate_t = Runkit.registry.get "/echo/Point"
            initial_sample = intermediate_t.new
            initial_sample.x = 1
            initial_sample.y = 0
            flexmock(intermediate_t).should_receive(:new).and_return(initial_sample)
            task = new_ruby_task_context("task")
            task.create_property "p", "/OpaquePoint"
            assert_equal initial_sample, task.p
        end

        it "reads and writes them" do
            task = new_ruby_task_context("task")
            property = task.create_property("prop", "int")
            property.write(10)
            assert_equal 10, property.read
            property.write(20)
            assert_equal 20, property.read
        end

        it "raises a Ruby exception on initialization if the opaque conversion fails" do
            task = new_ruby_task_context("task")
            # create_property initializes the property, which fails in this case
            e = assert_raises(Runkit::CORBAError) do
                task.create_property "out", "/base/geometry/Spline3"
            end
            assert_match(
                /failed to marshal.*dimension must be strictly/,
                e.message
            )
        end

        it "raises a Ruby exception on write the opaque conversion fails" do
            task = new_ruby_task_context("task")
            prop = task.create_property "out", "/base/geometry/Spline3", init: false
            e = assert_raises(Runkit::CORBAError) do
                sample = Runkit.registry.get("/wrappers/geometry/Spline").new
                sample.dimension = 0
                prop.write(sample)
            end
            assert_match(
                /failed to marshal.*dimension must be strictly/,
                e.message
            )
        end
    end

    describe "attributes" do
        it "can create a attribute" do
            task = new_ruby_task_context("task")
            attribute = task.create_attribute("prop", "int")
            assert_kind_of Runkit::Attribute, attribute
            assert_same attribute, task.attribute("prop")
            assert task.has_attribute?("prop")
        end
        it "initializes the attribute with a sample" do
            Runkit.load_typekit "echo"
            opaque_t       = Runkit.registry.get "/OpaquePoint"
            intermediate_t = Runkit.registry.get "/echo/Point"
            initial_sample = intermediate_t.new
            initial_sample.x = 1
            initial_sample.y = 0
            flexmock(intermediate_t).should_receive(:new).and_return(initial_sample)
            task = new_ruby_task_context("task")
            task.create_attribute "p", "/OpaquePoint"
            assert_equal initial_sample, task.p
        end

        it "reads and writes attributes" do
            task = new_ruby_task_context("task")
            attribute = task.create_attribute("prop", "int")
            attribute.write(10)
            assert_equal 10, attribute.read
            attribute.write(20)
            assert_equal 20, attribute.read
        end

        it "raises a Ruby exception on initialization if the opaque conversion fails" do
            task = new_ruby_task_context("task")
            # create_attribute initializes the attribute, which fails in this case
            e = assert_raises(Runkit::CORBAError) do
                task.create_attribute "out", "/base/geometry/Spline3"
            end
            assert_match(
                /failed to marshal.*dimension must be strictly/,
                e.message
            )
        end

        it "raises a Ruby exception on write the opaque conversion fails" do
            task = new_ruby_task_context("task")
            prop = task.create_attribute "out", "/base/geometry/Spline3", init: false
            e = assert_raises(Runkit::CORBAError) do
                sample = Runkit.registry.get("/wrappers/geometry/Spline").new
                sample.dimension = 0
                prop.write(sample)
            end
            assert_match(
                /failed to marshal.*dimension must be strictly/,
                e.message
            )
        end
    end

    it "allows to get access to the model name if one is given" do
        project = OroGen::Spec::Project.new(Runkit.default_loader)
        model = OroGen::Spec::TaskContext.new(project, "myModel")
        task = new_ruby_task_context("task", model: model)
        assert_equal "myModel", task.getModelName
    end

    it "makes #model returns the oroGen model if given" do
        project = OroGen::Spec::Project.new(Runkit.default_loader)
        model = Runkit::Spec::TaskContext.new(project)
        task = new_ruby_task_context("task", model: model)
        assert_same model, task.model
    end

    it "allows to handle the normal state changes" do
        task = new_ruby_task_context("task")
        assert_equal :PRE_OPERATIONAL, task.rtt_state
        task.configure
        assert_equal :STOPPED, task.rtt_state
        task.start
        assert_equal :RUNNING, task.rtt_state
        task.stop
        assert_equal :STOPPED, task.rtt_state
    end

    describe "local output ports" do
        it "gets an exception if the typelib value cannot be converted to the intermediate opaque type" do
            task = new_ruby_task_context "task"
            task.create_output_port "out", "/base/geometry/Spline3"
            sample = Runkit.registry.get("/wrappers/geometry/Spline").new
            sample.dimension = 0
            e = assert_raises(Runkit::CORBAError) do
                task.out.write sample
            end
            assert_match(
                /failed to marshal.*dimension must be strictly/,
                e.message
            )
        end
    end
end
