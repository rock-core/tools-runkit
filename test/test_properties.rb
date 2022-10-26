# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe Property do
        describe "#==" do
            attr_reader :task, :prop
            before do
                @task = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
                @prop = task.property("prop1")
            end

            it "returns true if comparing the same property object" do
                assert_equal prop, prop
            end
            it "returns false for two different properties from the same task" do
                refute_equal prop, task.property("prop2")
            end
            it "returns false for two different properties from two different tasks" do
                task = start_and_get(
                    { "orogen_runkit_tests::Properties" => "other" }, "other"
                )
                refute_equal prop, task.property("prop1")
            end
            it "returns false if compared with an arbitrary object" do
                refute_equal flexmock, prop
            end
            it "returns true for the same property represented from two different objects" do
                task = TaskContext.new(@task.ior, name: "test")
                assert_equal prop, task.property("prop1")
            end
        end

        it "enumerates its properties" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal %w{dynamic_prop dynamic_prop_setter_called prop1 prop2 prop3},
                        t.property_names.sort
            assert_equal %w{dynamic_prop dynamic_prop_setter_called prop1 prop2 prop3},
                        t.each_property.map(&:name).sort
            %w{dynamic_prop prop1 prop2 prop3}.each do |name|
                t.property?(name)
            end
        end

        it "reads string property values" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal("42", t.property("prop3").read)
        end

        it "reads property values from a simple type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal 84, t.property("prop2").read
        end

        it "reads property values from a complex type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal 21, t.property("prop1").read.tv_sec
        end

        it "writes a property of a simple type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            prop = t.property("prop2")
            prop.write(80)
            assert_equal(80, prop.read)
        end

        it "writes string property values" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            prop = t.property("prop3")
            prop.write("80")
            assert_equal("80", prop.read)
        end

        it "writes a property of a complex type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            prop = t.property("prop1")
            prop.write(Time.at(80))
            assert_equal(80, prop.read.tv_sec)
        end

        it "does not call the setter operation of a dynamic property if the task is not configured" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            t.property("dynamic_prop").write("12345")
            refute t.dynamic_prop_setter_called
        end

        it "calls the setter operation of a dynamic property if the task is configured" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            t.configure
            prop = t.property("dynamic_prop")
            prop.write("12345")
            assert t.dynamic_prop_setter_called
            assert_equal "12345", prop.read
        end

        it "should raise PropertyChangeRejected if the setter operation returned false" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            t.configure
            prop = t.property("dynamic_prop")
            assert_raises(Runkit::PropertyChangeRejected) do
                prop.write("")
            end
            assert_equal "", t.dynamic_prop
            assert t.dynamic_prop_setter_called
        end
    end

    describe Attribute do
        describe "#==" do
            attr_reader :task, :att
            before do
                @task = start_and_get(
                    { "orogen_runkit_tests::Properties" => "test" }, "test"
                )
                @att = task.attribute("att1")
            end

            it "returns true if comparing the same attribute object" do
                assert_equal att, att
            end
            it "returns false for two different attributes from the same task" do
                refute_equal att, task.attribute("att2")
            end
            it "returns false for two different attributes from two different tasks" do
                task = start_and_get(
                    { "orogen_runkit_tests::Properties" => "other" }, "other"
                )
                refute_equal att, task.attribute("att1")
            end
            it "returns false if compared with an arbitrary object" do
                refute_equal flexmock, att
            end
            it "returns true for the same attribute represented from two different objects" do
                task = TaskContext.new(@task.ior, name: "test")
                assert_equal att, task.attribute("att1")
            end
        end

        it "enumerates its attributes" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            usual_attributes =
                %w[CycleCounter IOCounter TimeOutCounter TriggerCounter TriggerOnStart
                   metadata]
            task_attributes = %w[att1 att2 att3]
            expectation = (usual_attributes + task_attributes).sort
            assert_equal expectation, t.attribute_names.sort
            expectation.each do |name|
                assert t.attribute?(name)
            end
        end

        it "reads string attribute values" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal("42", t.attribute("att3").read)
        end

        it "reads attribute values from a simple type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            assert_equal(84, t.attribute("att2").read)
        end

        it "reads attribute values from a complex type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            att1 = t.attribute("att1")
            assert_equal(21, att1.read.tv_sec)
        end

        it "writes a attribute of a simple type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            att = t.attribute("att2")
            att.write(80)
            assert_equal(80, att.read)
        end

        it "writes string attribute values" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            att = t.attribute("att3")
            att.write("84")
            assert_equal("84", att.read)
        end

        it "writes a attribute of a complex type" do
            t = start_and_get({ "orogen_runkit_tests::Properties" => "test" }, "test")
            att = t.attribute("att1")

            att.write(Time.at(22))
            assert_equal(22, att.read.tv_sec)
        end
    end
end
