# frozen_string_literal: true

require "orocos/test"

describe Orocos::Operation do
    attr_reader :task
    attr_reader :process

    def setup
        super
        @process, _ = Orocos.run "operations_test"
        @task = Orocos::TaskContext.get "operations"
        @task.start
    end

    def teardown
        @process&.kill
        super
    end

    def assert_operation_signature(returns, arguments, opname)
        op = task.operation(opname)

        assert_equal returns, op.orocos_return_typenames, "wrong return types for #{opname}"
        assert_equal arguments, op.orocos_arguments_typenames, "wrong argument types for #{opname}"
    end

    def assert_call_returns(value, opname, *args)
        op = task.operation opname
        return_value = op.callop(*args)
        assert_equal(value, op.callop(*args))
    end

    def assert_send_returns(value, opname, *args)
        op = task.operation opname

        # First will collect()
        handle = op.sendop(*args)
        assert_kind_of Orocos::SendHandle, handle
        status, *result = handle.collect
        assert_equal(Orocos::SendHandle::SEND_SUCCESS, status)
        assert_equal([*value].compact, result)

        # Then with collect_if_done
        handle = op.sendop(*args)
        assert_kind_of Orocos::SendHandle, handle
        status, result = nil
        50.times do
            status, *result = handle.collect_if_done
            break if status == Orocos::SendHandle::SEND_SUCCESS

            sleep 0.01
        end
        assert_equal Orocos::SendHandle::SEND_SUCCESS, status
        assert_equal([*value].compact, result)
    end

    def find_type(type_name)
        Orocos::CORBA.load_typekit "operations"
        Orocos.registry.get(type_name)
    end

    it "should be able to get the operation signatures" do
        assert_operation_signature [], [], "empty"
        assert_operation_signature ["/int32_t"], ["/Test/Parameters"], "simple"
        assert_operation_signature ["/Test/Parameters"], ["/Test/Parameters"], "simple_with_return"
        assert_operation_signature ["/Test/Opaque"], ["/Test/Parameters"], "with_returned_opaque"
        assert_operation_signature ["/Test/Parameters"], ["/Test/Opaque"], "with_opaque_argument"
        assert_operation_signature ["/Test/Parameters", "/Test/Parameters"], ["/Test/Parameters", "/Test/Opaque"], "with_returned_parameter"
    end

    it "synchronous call on an empty operation" do
        assert_call_returns nil, "empty"
    end

    it "synchronous call with a string return value" do
        assert_call_returns "testret", "string_handling", "test"
    end

    it "synchronous call with a structure argument" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        assert_call_returns 10, "simple", arg
    end

    it "synchronous call with a structure return value" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_call_returns arg, "simple_with_return", arg
    end

    it "synchronous call with a returned opaque" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_call_returns arg, "with_returned_opaque", arg
    end

    it "synchronous call with an opaque argument" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_call_returns arg, "with_opaque_argument", arg
    end

    it "synchronous call with a parameter used as return value" do
        arg_t = find_type("/Test/Parameters")
        arg = arg_t.new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_call_returns [arg, arg], "with_returned_parameter", arg, arg
    end

    it "asynchronous call on an empty operation" do
        assert_send_returns nil, "empty"
    end

    it "asynchronous call with a structure argument" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        assert_send_returns 10, "simple", arg
    end

    it "asynchronous call with a structure return value" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_send_returns arg, "simple_with_return", arg
    end

    it "asynchronous call with a returned opaque" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_send_returns arg, "with_returned_opaque", arg
    end

    it "asynchronous call with an opaque argument" do
        arg = find_type("/Test/Parameters").new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_send_returns arg, "with_opaque_argument", arg
    end

    it "asynchronous call with a parameter used as return value" do
        arg_t = find_type("/Test/Parameters")
        arg = arg_t.new
        arg.set_point = 10
        arg.threshold = 0.1
        assert_send_returns [arg, arg], "with_returned_parameter", arg, arg
    end

    # it "should be possible to asynchronously call an operation with arguments" do
    #    Orocos.run 'echo' do |echo|
    #        echo = echo.task 'Echo'
    #        echo.start

    #        port_reader = echo.port('output').reader

    #        m = echo.operation 'write'
    #        handle = m.sendop(10)
    #        assert_kind_of Orocos::SendHandle, handle
    #        sleep 0.2
    #        assert_equal Orocos::SendHandle::SEND_SUCCESS, handle.check_status
    #        assert_equal(10, handle.returned_value)
    #    end
    # end

    # it "should be possible to use a shortcut" do
    #    Orocos.run 'echo' do |echo|
    #        echo = echo.task 'Echo'
    #        echo.start
    #        assert_equal(10, echo.write(10))
    #    end
    # end

    # it "should be possible to have multiple Operation instances referring to the same remote method" do
    #    Orocos.run 'echo' do |echo|
    #        echo = echo.task 'Echo'
    #        echo.start

    #        port_reader = echo.port('output').reader

    #        m = echo.operation 'write'
    #        m.callop(10)
    #        assert(10, port_reader.read)
    #        m2 = echo.operation 'write'
    #        m2.callop(11)
    #        assert(11, port_reader.read)
    #        m.callop(10)
    #        assert(10, port_reader.read)
    #    end
    # end
end
