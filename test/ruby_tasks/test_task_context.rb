# frozen_string_literal: true

require "runkit/test"

module Runkit
    module RubyTasks
        describe TaskContext do
            before do
                Runkit.load_typekit "base"
                @loader = OroGen::Loaders::RTT.new(Runkit.orocos_target)
                @loader.typekit_model_from_name("std")
                @loader.typekit_model_from_name("base")

                @int32_t = @loader.resolve_type "/int32_t"
                @spline_t = @loader.resolve_type "/base/geometry/Spline<3>"
            end

            it "refers to a LocalTaskContext object that refers to it back" do
                task = new_ruby_task_context("task")
                assert_same task, task.instance_variable_get(:@local_task).remote_task
            end


            describe "with a supporting oroGen model" do
                before do
                    project = OroGen::Spec::Project.new(@loader)
                    @task_m = project.task_context "task" do
                        property "p", "/float"
                        attribute "a", "/float"
                        input_port "in", "/double"
                        output_port "out", "/base/geometry/Spline<3>"
                    end
                    @task = new_ruby_task_context("task", model: @task_m)
                end

                it "makes #model returns the oroGen model if given" do
                    project = OroGen::Spec::Project.new(@loader)
                    model = OroGen::Spec::TaskContext.new(project)
                    task = new_ruby_task_context("task", model: model)
                    assert_same model, task.model
                end

                it "passes the port model when creating input ports" do
                    in_p = @task.port("in")
                    assert_kind_of Runkit::InputPort, in_p
                    assert_same @task, in_p.task
                    assert_equal "in", in_p.name
                    assert_same @task_m.find_port("in"), in_p.model
                end


                it "passes the port model when creating output ports" do
                    out_p = @task.port("out")
                    assert_kind_of Runkit::OutputPort, out_p
                    assert_same @task, out_p.task
                    assert_equal "out", out_p.name
                    assert_same @task_m.find_port("out"), out_p.model
                end

                it "passes the property models when creating the properties" do
                    p = @task.property("p")
                    assert_kind_of Runkit::Property, p
                    assert_equal "p", p.name
                    assert_same @task_m.find_property("p"), p.model
                end

                it "passes the attribute models when creating the attributes" do
                    a = @task.attribute("a")
                    assert_kind_of Runkit::Attribute, a
                    assert_equal "a", a.name
                    assert_same @task_m.find_attribute("a"), a.model
                end
            end

            describe "without a supporting oroGen model" do
                describe "port handling" do
                    it "creates an output port and returns it" do
                        task = new_ruby_task_context
                        port = task.create_output_port("p", @int32_t)
                        assert_kind_of Runkit::OutputPort, port
                        assert_equal task, port.task
                        assert_equal "p", port.name

                        assert task.port?("p")
                        assert_same port, task.port("p")
                    end

                    it "creates input ports" do
                        task = new_ruby_task_context("producer")
                        port = task.create_input_port("p", @int32_t)
                        assert_kind_of Runkit::InputPort, port
                        assert_equal task, port.task
                        assert_equal "p", port.name

                        assert task.port?("p")
                        assert_same port, task.port("p")
                    end

                    it "writes and reads on ports" do
                        producer = new_ruby_task_context("producer")
                        out_p = producer.create_output_port("p", @int32_t)
                        consumer = new_ruby_task_context("consumer")
                        in_p = consumer.create_input_port("p", @int32_t)

                        out_p.connect_to in_p
                        out_p.write 10
                        assert_equal 10, in_p.read
                    end

                    it "gets an exception if the typelib value cannot be converted to the intermediate opaque type" do
                        task = new_ruby_task_context "task"
                        port = task.create_output_port "out", @spline_t
                        sample = port.new_sample
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

                describe "properties" do
                    it "creates them" do
                        task = new_ruby_task_context("task")
                        property = task.create_property("prop", @int32_t)
                        assert_kind_of Runkit::Property, property
                        assert_equal property, task.property("prop")
                        assert task.property?("prop")
                    end

                    it "initializes them with a sample by default" do
                        intermediate_t = @loader.typelib_type_for(@spline_t)
                        initial_sample = intermediate_t.zero
                        initial_sample.geometric_resolution = 0
                        initial_sample.curve_order = 1
                        initial_sample.dimension = 1

                        flexmock(@loader)
                            .should_receive(:typelib_type_for)
                            .with("/wrappers/geometry/Spline").and_return(intermediate_t)
                        flexmock(intermediate_t)
                            .should_receive(:zero).and_return(initial_sample)
                        task = new_ruby_task_context("task", loader: @loader)
                        task.create_property "p", @spline_t
                        assert_equal initial_sample, task.property("p").raw_read
                    end

                    it "reads and writes them" do
                        task = new_ruby_task_context("task")
                        property = task.create_property("prop", @int32_t)
                        property.write(10)
                        assert_equal 10, property.read
                        property.write(20)
                        assert_equal 20, property.read
                    end

                    it "raises a Ruby exception on initialization if the opaque conversion fails" do
                        task = new_ruby_task_context("task")
                        # create_property initializes the property, which fails in this case
                        e = assert_raises(Runkit::CORBAError) do
                            task.create_property "out", @spline_t
                        end
                        assert_match(
                            /failed to marshal.*dimension must be strictly/,
                            e.message
                        )
                    end

                    it "raises a Ruby exception on write the opaque conversion fails" do
                        task = new_ruby_task_context("task")
                        prop = task.create_property "out", @spline_t, init: false
                        e = assert_raises(Runkit::CORBAError) do
                            sample = prop.new_sample
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
                        attribute = task.create_attribute("prop", @int32_t)
                        assert_kind_of Runkit::Attribute, attribute
                        assert_equal attribute, task.attribute("prop")
                        assert task.attribute?("prop")
                    end

                    it "initializes the attribute with a sample" do
                        intermediate_t = Runkit.typelib_type_for(@spline_t)
                        initial_sample = intermediate_t.zero
                        initial_sample.geometric_resolution = 0
                        initial_sample.curve_order = 1
                        initial_sample.dimension = 1
                        flexmock(intermediate_t)
                            .should_receive(:zero).and_return(initial_sample)
                        task = new_ruby_task_context("task")
                        task.create_attribute "p", @spline_t
                        assert_equal initial_sample, task.attribute("p").raw_read
                    end

                    it "reads and writes attributes" do
                        task = new_ruby_task_context("task")
                        attribute = task.create_attribute("prop", @int32_t)
                        attribute.write(10)
                        assert_equal 10, attribute.read
                        attribute.write(20)
                        assert_equal 20, attribute.read
                    end

                    it "raises a Ruby exception on initialization if the opaque conversion fails" do
                        task = new_ruby_task_context("task")
                        # create_attribute initializes the attribute, which fails in this case
                        e = assert_raises(Runkit::CORBAError) do
                            task.create_attribute "out", @spline_t
                        end
                        assert_match(
                            /failed to marshal.*dimension must be strictly/,
                            e.message
                        )
                    end

                    it "raises a Ruby exception on write if the opaque conversion fails" do
                        task = new_ruby_task_context("task")
                        prop = task.create_attribute(
                            "out", @spline_t, init: false
                        )
                        e = assert_raises(Runkit::CORBAError) do
                            sample = prop.new_sample
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
            end

            it "handles the normal state changes" do
                task = new_ruby_task_context("task")
                assert_equal :PRE_OPERATIONAL, task.rtt_state
                task.configure
                assert_equal :STOPPED, task.rtt_state
                task.start
                assert_equal :RUNNING, task.rtt_state
                task.stop
                assert_equal :STOPPED, task.rtt_state
                task.cleanup
                assert_equal :PRE_OPERATIONAL, task.rtt_state
            end
        end
    end
end
