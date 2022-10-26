# frozen_string_literal: true

require "runkit/test"

module Runkit
    describe Operation do
        attr_reader :task

        before do
            Runkit.load_typekit "base"
            @task = start_and_get(
                { "orogen_runkit_tests::Operations" => "operations" },
                "operations"
            )
            @task.configure
            @task.start
        end

        it "resolves the operation signatures" do
            assert_operation_signature [], [], "empty"
            assert_operation_signature ["/int32_t"], ["/base/Time"], "simple"
            assert_operation_signature(
                ["/base/Time"], ["/base/Time"],
                "simple_with_return"
            )
            assert_operation_signature(
                ["/base/Vector3d"], ["/base/Time"],
                "with_returned_opaque"
            )
            assert_operation_signature(
                ["/base/Time"], ["/base/Vector3d"],
                "with_opaque_argument"
            )
            assert_operation_signature(
                ["/base/Time", "/base/Time"],
                ["/base/Time", "/base/Vector3d"], "with_returned_parameter"
            )
        end

        it "synchronous call on an empty operation" do
            assert_call_returns nil, "empty"
        end

        it "synchronous call with a string return value" do
            assert_call_returns "testret", "string_handling", "test"
        end

        it "synchronous call with a structure argument" do
            assert_call_returns 10, "simple", { microseconds: 10 }
        end

        it "synchronous call with a structure return value" do
            assert_call_returns Time.at(20), "simple_with_return", Time.at(10)
        end

        it "synchronous call with a returned opaque" do
            expected = Eigen::Vector3.new(10, 0, 0)
            assert_call_returns expected, "with_returned_opaque", Time.at(10)
        end

        it "synchronous call with an opaque argument" do
            arg = Eigen::Vector3.new(10, 0, 0)
            assert_call_returns Time.at(10), "with_opaque_argument", arg
        end

        it "synchronous call with a parameter used as return value" do
            skip "KNOWN BUG"

            arg = [Time.at(10), Eigen::Vector3.new(2, 3, 0)]
            expected = [Time.at(3), Time.at(20)]

            assert_call_returns expected, "with_returned_parameter", *arg
        end

        it "asynchronous call on an empty operation" do
            assert_send_returns nil, "empty"
        end

        it "asynchronous call with a string return value" do
            assert_send_returns "testret", "string_handling", "test"
        end

        it "asynchronous call with a structure argument" do
            assert_send_returns 10, "simple", { microseconds: 10 }
        end

        it "asynchronous call with a structure return value" do
            assert_send_returns Time.at(20), "simple_with_return", Time.at(10)
        end

        it "asynchronous call with a returned opaque" do
            expected = Eigen::Vector3.new(10, 0, 0)
            assert_send_returns expected, "with_returned_opaque", Time.at(10)
        end

        it "asynchronous call with an opaque argument" do
            arg = Eigen::Vector3.new(10, 0, 0)
            assert_send_returns Time.at(10), "with_opaque_argument", arg
        end

        it "asynchronous call with a parameter used as return value" do
            arg = [Time.at(10), Eigen::Vector3.new(2, 3, 0)]
            expected = [Time.at(3), Time.at(20)]

            assert_send_returns expected, "with_returned_parameter", *arg
        end

        it "raises CORBA::ComError when the process crashes during a operation call" do
            process = start({ "orogen_runkit_tests::Kill" => "kill" }).first
            task = process.task("kill")
            assert_raises(CORBA::ComError) do
                task.operation(:kill).callop
            end

            process.join # to avoid a warning during teardown
        end

        def assert_operation_signature(returns, arguments, opname)
            op = task.operation(opname)

            assert_equal returns, op.orocos_return_typenames, "wrong return types for #{opname}"
            assert_equal arguments, op.orocos_arguments_typenames, "wrong argument types for #{opname}"
        end

        def assert_call_returns(expected_value, opname, *args)
            op = task.operation opname
            return_value = op.callop(*args)
            if expected_value.nil?
                assert_nil return_value
            else
                assert_equal(expected_value, return_value)
            end
        end

        def assert_send_returns(expected_values, opname, *args)
            op = task.operation opname

            # First will collect()
            handle = op.sendop(*args)
            assert_kind_of Runkit::SendHandle, handle
            status, result = handle.collect
            assert_equal(Runkit::SendHandle::SEND_SUCCESS, status)
            if expected_values.nil?
                assert_nil result, "collect failed"
            else
                assert_equal(expected_values, result, "collect failed")
            end

            # Then with collect_if_done
            handle = op.sendop(*args)
            assert_kind_of Runkit::SendHandle, handle
            status, result = nil
            50.times do
                status, result = handle.collect_if_done
                break if status == Runkit::SendHandle::SEND_SUCCESS

                sleep 0.01
            end
            assert_equal Runkit::SendHandle::SEND_SUCCESS, status

            if expected_values.nil?
                assert_nil(result, "collect_if_done failed")
            else
                assert_equal(expected_values, result, "collect_if_done failed")
            end
        end
    end
end
