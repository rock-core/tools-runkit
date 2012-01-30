$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'minitest/spec'
require 'orocos'
require 'orocos/test'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

describe Orocos::TaskConfigurations do
    include Orocos::Spec
    TaskConfigurations = Orocos::TaskConfigurations

    attr_reader :conf
    attr_reader :model

    def setup
        super
        @model = Orocos.task_model_from_name('configurations::Task')
        @conf  = TaskConfigurations.new(model)
    end

    def verify_loaded_conf(conf, name = nil, *base_path)
        if conf.respond_to?(:sections)
            assert conf.sections.has_key?(name)
            @conf_context = conf.sections[name]
        else
            @conf_context = conf
            if name
                base_path.unshift name
            end
        end

        @conf_getter = method(:get_conf_value)
        base_path.each do |p|
            @conf_context = @conf_context[p]
        end
        yield
    end

    def verify_apply_conf(task, conf, names, *base_path, &block)
        conf.apply(task, names)
        verify_applied_conf(task, *base_path, &block)
    end

    def verify_applied_conf(task, *base_path)
        if !base_path.empty?
            base_property = task.property(base_path.shift)
            value_path = base_path
        end

        @conf_getter = lambda do |*path|
            property=
                if base_property then base_property
                else
                    task.property(path.shift)
                end

            result = property.raw_read
            (base_path + path).inject(result) do |result, field|
                result.raw_get(field)
            end
        end
        yield
    end

    def get_conf_value(*path)
        path.inject(@conf_context) do |result, field|
            if !result[field]
                raise ArgumentError, "no #{field} in #{result.inspect}"
            end
            result[field]
        end
    end

    def assert_conf_value(*path)
        expected_value = path.pop
        type = path.pop
        type_name = path.pop

        value = @conf_getter[*path]
        assert_kind_of type, value
        assert_equal type_name, value.class.name

        if block_given?
            value = yield(value)
        elsif value.kind_of?(Typelib::Type)
            value = Typelib.to_ruby(value)
        end
        assert_equal expected_value, value
    end

    it "should be able to load simple configuration structures" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'base_config.yml'))
        assert_equal %w{compound default simple_container}, conf.sections.keys.sort

        verify_loaded_conf conf, 'default' do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 20
            assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test"
            assert_conf_value 'fp', '/double', Typelib::NumericType, 0.1
        end

        verify_loaded_conf conf, 'compound', 'compound' do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test2"
            assert_conf_value 'fp', '/double', Typelib::NumericType, 0.2
            assert_conf_value 'simple_array', 0, "/int32_t", Typelib::NumericType, 1
            assert_conf_value 'simple_array', 1, "/int32_t", Typelib::NumericType, 2
            assert_conf_value 'simple_array', 2, "/int32_t", Typelib::NumericType, 3
            array = get_conf_value 'simple_array'
            assert_equal 3, array.size
        end

        verify_loaded_conf conf, 'simple_container', 'simple_container' do
            assert_conf_value 0, "/int32_t", Typelib::NumericType, 10
            assert_conf_value 1, "/int32_t", Typelib::NumericType, 20
            assert_conf_value 2, "/int32_t", Typelib::NumericType, 30
            container = get_conf_value
            assert_equal 3, container.size
        end
    end

    it "should be able to load complex structures" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'complex_config.yml'))

        verify_loaded_conf conf, 'compound_in_compound', 'compound', 'compound' do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test2"
            assert_conf_value 'fp', '/double', Typelib::NumericType, 0.2
        end

        verify_loaded_conf conf, 'vector_of_compound', 'compound', 'vector_of_compound' do
            assert_conf_value 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 1, 'intg', "/int32_t", Typelib::NumericType, 20
            assert_conf_value 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 2, 'intg', "/int32_t", Typelib::NumericType, 30
        end

        verify_loaded_conf conf, 'vector_of_vector_of_compound', 'compound', 'vector_of_vector_of_compound' do
            assert_conf_value 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 0, 1, 'intg', "/int32_t", Typelib::NumericType, 20
            assert_conf_value 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 0, 2, 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 1, 0, 'intg', "/int32_t", Typelib::NumericType, 11
            assert_conf_value 1, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 1, 1, 'intg', "/int32_t", Typelib::NumericType, 21
            assert_conf_value 1, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 1, 2, 'intg', "/int32_t", Typelib::NumericType, 31
        end

        verify_loaded_conf conf, 'array_of_compound', 'compound', 'array_of_compound' do
            assert_conf_value 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 1, 'intg', "/int32_t", Typelib::NumericType, 20
            assert_conf_value 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 2, 'intg', "/int32_t", Typelib::NumericType, 30
        end

        verify_loaded_conf conf, 'array_of_vector_of_compound', 'compound', 'array_of_vector_of_compound' do
            assert_conf_value 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 0, 1, 'intg', "/int32_t", Typelib::NumericType, 20
            assert_conf_value 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 0, 2, 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 1, 0, 'intg', "/int32_t", Typelib::NumericType, 11
            assert_conf_value 1, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 1, 1, 'intg', "/int32_t", Typelib::NumericType, 21
            assert_conf_value 1, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 1, 2, 'intg', "/int32_t", Typelib::NumericType, 31
        end
    end

    it "should be able to merge configuration structures" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'merge.yml'))
        result = conf.conf(['default', 'add'], false)
        verify_loaded_conf result do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 20
        end
        verify_loaded_conf result, 'compound' do
            assert_conf_value 'compound', 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'compound', 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'vector_of_compound', 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'vector_of_compound', 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'vector_of_compound', 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'array_of_vector_of_compound', 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'intg', "/int32_t", Typelib::NumericType, 12
            assert_conf_value 'array_of_vector_of_compound', 2, 0, 'enm', "/Enumeration", Typelib::EnumType, :Second
        end
    end

    it "merge without overrides should have the same result than with if no conflicts exist" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'merge.yml'))
        result = conf.conf(['default', 'add'], false)
        result_with_override = conf.conf(['default', 'add'], true)
        assert_equal result, result_with_override
    end

    it "should be able to detect invalid overridden values" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'merge.yml'))
        # Make sure that nothing is raised if override is false
        conf.conf(['default', 'override'], true)
        assert_raises(ArgumentError) { conf.conf(['default', 'override'], false) }
    end

    it "should be able to merge with overrides" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'merge.yml'))
        result = conf.conf(['default', 'override'], true)

        verify_loaded_conf result do
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 25
        end
        verify_loaded_conf result, 'compound' do
            assert_conf_value 'compound', 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'vector_of_compound', 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'vector_of_compound', 0, 'intg', "/int32_t", Typelib::NumericType, 42
            assert_conf_value 'vector_of_compound', 1, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'vector_of_compound', 1, 'intg', "/int32_t", Typelib::NumericType, 22
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'array_of_vector_of_compound', 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'intg', "/int32_t", Typelib::NumericType, 11
            assert_conf_value 'array_of_vector_of_compound', 2, 0, 'enm', "/Enumeration", Typelib::EnumType, :Second
        end
    end

    it "should be able to apply simple configurations on the task" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'base_config.yml'))
        Orocos.run "configurations_test" do
            task = Orocos::TaskContext.get "configurations"

            assert_equal (0...10).to_a, task.simple_container.to_a
            assert_equal :First, task.compound.enm
            simple_array = task.compound.simple_array.to_a
            simple_container = task.simple_container.to_a

            conf.apply(task, 'default')

            assert_equal (0...10).to_a, task.simple_container.to_a
            assert_equal :First, task.compound.enm
            verify_applied_conf task do
                assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
                assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 20
                assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test"
                assert_conf_value 'fp', '/double', Typelib::NumericType, 0.1
            end


            conf.apply(task, ['default', 'compound'])
            verify_applied_conf task do
                assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
                assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 20
                assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test"
                assert_conf_value 'fp', '/double', Typelib::NumericType, 0.1
            end
            simple_array[0, 3] = [1, 2, 3]
            verify_applied_conf task, 'compound' do
                assert_conf_value 'enm', "Symbol", Symbol, :Second
                assert_conf_value 'intg', "Fixnum", Fixnum, 30
                assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test2"
                assert_conf_value 'fp', 'Float', Float, 0.2
                assert_conf_value 'simple_array', '/int32_t[10]', Typelib::ArrayType, simple_array do |v|
                    v.to_a
                end
            end

            conf.apply(task, ['default', 'compound', 'simple_container'])
            simple_container[0, 3] = [10, 20, 30]
            verify_applied_conf task do
                assert_conf_value 'simple_container', '/std/vector</int32_t>', Typelib::ContainerType, simple_container do |v|
                    v.to_a
                end
            end
        end
    end

    it "should be able to apply complex configuration on the task" do
        conf.load_from_yaml(File.join(DATA_DIR, 'configurations', 'complex_config.yml'))

        Orocos.run "configurations_test" do
            task = Orocos::TaskContext.get "configurations"

            verify_apply_conf task, conf, 'compound_in_compound', 'compound', 'compound' do
                assert_conf_value 'enm', "Symbol", Symbol, :Third
                assert_conf_value 'intg', "Fixnum", Fixnum, 30
                assert_conf_value 'str', "/std/string", Typelib::ContainerType, "test2"
                assert_conf_value 'fp', 'Float', Float, 0.2
            end

            verify_apply_conf task, conf, 'vector_of_compound', 'compound', 'vector_of_compound' do
                assert_conf_value 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 0, 'intg', "Fixnum", Fixnum, 10
                assert_conf_value 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 1, 'intg', "Fixnum", Fixnum, 20
                assert_conf_value 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 2, 'intg', "Fixnum", Fixnum, 30
            end

            verify_apply_conf task, conf, 'vector_of_vector_of_compound', 'compound', 'vector_of_vector_of_compound' do
                assert_conf_value 0, 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 0, 0, 'intg', "Fixnum", Fixnum, 10
                assert_conf_value 0, 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 0, 1, 'intg', "Fixnum", Fixnum, 20
                assert_conf_value 0, 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 0, 2, 'intg', "Fixnum", Fixnum, 30
                assert_conf_value 1, 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 1, 0, 'intg', "Fixnum", Fixnum, 11
                assert_conf_value 1, 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 1, 1, 'intg', "Fixnum", Fixnum, 21
                assert_conf_value 1, 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 1, 2, 'intg', "Fixnum", Fixnum, 31
            end

            verify_apply_conf task, conf, 'array_of_compound', 'compound', 'array_of_compound' do
                assert_conf_value 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 0, 'intg', "Fixnum", Fixnum, 10
                assert_conf_value 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 1, 'intg', "Fixnum", Fixnum, 20
                assert_conf_value 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 2, 'intg', "Fixnum", Fixnum, 30
            end

            verify_apply_conf task, conf, 'array_of_vector_of_compound', 'compound', 'array_of_vector_of_compound' do
                assert_conf_value 0, 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 0, 0, 'intg', "Fixnum", Fixnum, 10
                assert_conf_value 0, 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 0, 1, 'intg', "Fixnum", Fixnum, 20
                assert_conf_value 0, 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 0, 2, 'intg', "Fixnum", Fixnum, 30
                assert_conf_value 1, 0, 'enm', "Symbol", Symbol, :First
                assert_conf_value 1, 0, 'intg', "Fixnum", Fixnum, 11
                assert_conf_value 1, 1, 'enm', "Symbol", Symbol, :Second
                assert_conf_value 1, 1, 'intg', "Fixnum", Fixnum, 21
                assert_conf_value 1, 2, 'enm', "Symbol", Symbol, :Third
                assert_conf_value 1, 2, 'intg', "Fixnum", Fixnum, 31
            end
        end
    end

    it "should be able to load a configuration directory, register configurations on a per-model basis, and report what changed" do
        manager = Orocos::ConfigurationManager.new
        manager.load_dir(File.join(DATA_DIR, 'configurations', 'dir'))
        result = manager.conf['configurations::Task'].conf(['default', 'add'], false)

        verify_loaded_conf result do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 20
        end
        verify_loaded_conf result, 'compound' do
            assert_conf_value 'compound', 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'compound', 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'vector_of_compound', 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'vector_of_compound', 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'vector_of_compound', 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'array_of_vector_of_compound', 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'intg', "/int32_t", Typelib::NumericType, 12
            assert_conf_value 'array_of_vector_of_compound', 2, 0, 'enm', "/Enumeration", Typelib::EnumType, :Second
        end

        assert_equal(Hash.new, manager.load_dir(File.join(DATA_DIR, 'configurations', 'dir')))
        assert_equal({'configurations::Task' => ['default']}, manager.load_dir(File.join(DATA_DIR, 'configurations', 'dir_changed')))
        result = manager.conf['configurations::Task'].conf(['default', 'add'], false)

        verify_loaded_conf result do
            assert_conf_value 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'intg', "/int32_t", Typelib::NumericType, 0
        end
        verify_loaded_conf result, 'compound' do
            assert_conf_value 'compound', 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'compound', 'intg', "/int32_t", Typelib::NumericType, 30
            assert_conf_value 'vector_of_compound', 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'vector_of_compound', 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'vector_of_compound', 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 0, 0, 'intg', "/int32_t", Typelib::NumericType, 10
            assert_conf_value 'array_of_vector_of_compound', 0, 1, 'enm', "/Enumeration", Typelib::EnumType, :Second
            assert_conf_value 'array_of_vector_of_compound', 0, 2, 'enm', "/Enumeration", Typelib::EnumType, :Third
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'enm', "/Enumeration", Typelib::EnumType, :First
            assert_conf_value 'array_of_vector_of_compound', 1, 0, 'intg', "/int32_t", Typelib::NumericType, 12
            assert_conf_value 'array_of_vector_of_compound', 2, 0, 'enm', "/Enumeration", Typelib::EnumType, :Second
        end
    end
end

