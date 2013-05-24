$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe "reading and writing properties on TaskContext" do
    include Orocos::Spec

    it "should be able to enumerate its properties" do
        Orocos.run('process') do |process|
            t = process.task('Test')
            assert_equal %w{dynamic_prop prop1 prop2 prop3}, t.property_names.sort
            assert_equal %w{dynamic_prop prop1 prop2 prop3}, t.each_property.map(&:name).sort
            %w{dynamic_prop prop1 prop2 prop3}.each do |name|
                t.has_property?(name)
            end
        end
    end

    it "should be able to read string property values" do
        Orocos.run('process') do |process|
            prop = process.task('Test').property('prop3')
            assert_equal('42', prop.read)
        end
    end

    it "should be able to read property values from a simple type" do
        Orocos.run('process') do |process|
            prop = process.task('Test').property('prop2')
            assert_equal(84, prop.read)
        end
    end

    it "should be able to read property values from a complex type" do
        Orocos.run('process') do |process|
            prop1 = process.task('Test').property('prop1')

            value = prop1.read
            assert_equal(21, value.a)
            assert_equal(42, value.b)
        end
    end

    it "should be able to write a property of a simple type" do
        Orocos.run('process') do |process|
            prop = process.task('Test').property('prop2')
            prop.write(80)
            assert_equal(80, prop.read)
        end
    end

    it "should be able to write string property values" do
        Orocos.run('process') do |process|
            prop = process.task('Test').property('prop3')
            prop.write('84')
            assert_equal('84', prop.read)
        end
    end

    it "should be able to write a property of a complex type" do
        Orocos.run('process') do |process|
            prop = Orocos::TaskContext.get('process_Test').property('prop1')

            value = prop.type.new
            value.a = 22
            value.b = 43
            prop.write(value)

            value = prop.read
            assert_equal(22, value.a)
            assert_equal(43, value.b)
        end
    end

    it "should call the setter operation in the case of dynamic properties" do
        Orocos.run('process') do |process|
            prop = process.task('Test').property('dynamic_prop')
            prop.write("12345")
            assert_equal('12345dyn', prop.read)
        end
    end
end

describe "reading and writing attributes on TaskContext" do
    include Orocos::Spec

    it "should be able to enumerate its attributes" do
        Orocos.run('process') do |process|
            t = process.task('Test')
            assert_equal %w{att1 att2 att3}, t.attribute_names.sort
            assert_equal %w{att1 att2 att3}, t.each_attribute.map(&:name).sort
            %w{att1 att2 att3}.each do |name|
                t.has_attribute?(name)
            end
        end
    end

    it "should be able to read string attribute values" do
        Orocos.run('process') do |process|
            att = process.task('Test').attribute('att3')
            assert_equal('42', att.read)
        end
    end

    it "should be able to read attribute values from a simple type" do
        Orocos.run('process') do |process|
            att = process.task('Test').attribute('att2')
            assert_equal(84, att.read)
        end
    end

    it "should be able to read attribute values from a complex type" do
        Orocos.run('process') do |process|
            att1 = process.task('Test').attribute('att1')

            value = att1.read
            assert_equal(21, value.a)
            assert_equal(42, value.b)
        end
    end

    it "should be able to write a attribute of a simple type" do
        Orocos.run('process') do |process|
            att = process.task('Test').attribute('att2')
            att.write(80)
            assert_equal(80, att.read)
        end
    end

    it "should be able to write string attribute values" do
        Orocos.run('process') do |process|
            att = process.task('Test').attribute('att3')
            att.write('84')
            assert_equal('84', att.read)
        end
    end

    it "should be able to write a attribute of a complex type" do
        Orocos.run('process') do |process|
            att = Orocos::TaskContext.get('process_Test').attribute('att1')

            value = att.type.new
            value.a = 22
            value.b = 43
            att.write(value)

            value = att.read
            assert_equal(22, value.a)
            assert_equal(43, value.b)
        end
    end
end


