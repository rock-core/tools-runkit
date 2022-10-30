# frozen_string_literal: true

module Runkit
    # OperationHandle instances represent asynchronous operation calls. They are
    # returned by Operation#sendop and TaskContext#sendop
    class SendHandle
        attr_reader :orocos_return_types
        attr_reader :return_values

        # Waits for the operation to finish and returns both its completion
        # status and, if applicable, its return value(s)
        #
        # Existing completion status are
        #
        #   Runkit::SEND_SUCCESS
        #   Runkit::SEND_NOT_READY
        #   Runkit::SEND_FAILURE
        def collect
            status = CORBA.refine_exceptions(self) do
                do_operation_collect(orocos_return_types, return_values)
            end
            format_return_values(status, return_values)
        end

        # Returns the current status for the operation
        #
        # If the operation is finished, and if it has a return value, then it
        # returns
        #
        #    Runkit::SEND_SUCCESS, return_value1, return_value2, ...
        #
        # Otherwise, returns either Runkit::SEND_NOT_READY (not yet processed)
        # or Runkit::SEND_FAILURE (operation failed to be processed on the
        # remote task)
        def collect_if_done
            status = CORBA.refine_exceptions(self) do
                do_operation_collect_if_done(orocos_return_types, return_values)
            end
            format_return_values(status, return_values)
        end

        # @api private
        #
        # Helper for {#collect} and {#collect_if_done} to format the return value
        # differently, depending on how many values are to be returned
        def format_return_values(status, return_values)
            return status if return_values.empty?

            return_values = return_values.map { |v| Typelib.to_ruby(v) }
            if return_values.size == 1
                [status, return_values.first]
            else
                [status, return_values]
            end
        end
    end

    # Base class for RTTMethod and Command
    class Operation
        # The task this method is part of
        attr_reader :task

        # The method name
        attr_reader :name
        # The method description
        attr_reader :description
        # The type name of the return value
        attr_reader :return_spec
        # The subclass of Typelib::Type that represents the type of the return value, as declared by the Runkit
        attr_reader :orocos_return_typenames
        # The subclass of Typelib::Type that will be manipulated by the Ruby
        # code
        attr_reader :return_types
        # An array describing the arguments. Each element is a <tt>[name, doc,
        # type_name]</tt> tuple
        attr_reader :arguments_spec
        # The typelib types for the arguments. This is an array of subclasses of
        # Typelib::Type, with each element being the type of the corresponding
        # element in #arguments_spec. It describes the types that the C++ side
        # manipulates (i.e. declared in the Runkit component)
        attr_reader :orocos_arguments_typenames
        # The typelib types for the arguments. This is an array of subclasses of
        # Typelib::Type, with each element being the type of the corresponding
        # element in #arguments_spec. It describes the types that the Ruby side
        # will manipulate
        attr_reader :arguments_types

        attr_reader :inout_arguments

        def initialize(task, name, return_spec, arguments_spec)
            @task = task
            @name = name
            @return_spec = return_spec
            @arguments_spec = arguments_spec

            @orocos_return_typenames = return_spec.map do |type_name|
                OroGen.unqualified_cxx_type(type_name)
            end
            @orocos_arguments_typenames = arguments_spec.map do |_, _, type_name|
                OroGen.unqualified_cxx_type(type_name)
            end
            @inout_arguments = arguments_spec.each_with_index.map do |(_, _, type_name), i|
                i if type_name =~ /&/ && type_name !~ /(^|[^\w])const($|[^\w])/
            end.compact

            # Remove a void return type
            if orocos_return_typenames.first == "void"
                @void_return = true
                orocos_return_typenames.shift
            else
                @void_return = false
            end

            @return_types    = typelib_types_for(orocos_return_typenames)
            @arguments_types = typelib_types_for(orocos_arguments_typenames)
        end

        # Replaces in +types+ the opaque types by the types that should be used
        # on the Ruby side
        def typelib_types_for(types)
            types.map do |t|
                Runkit.typelib_type_for(t)
            end
        end

        # Returns a new Typelib value for the Nth argument
        def new_argument(index)
            arguments_types[index].new
        end

        # Helper method for RTTMethod and Command
        def common_call(args) # :nodoc:
            if args.size != arguments_spec.size
                raise ArgumentError,
                      "expected #{arguments_spec.size} arguments but got #{args.size}"
            end

            filtered = []
            args.each_with_index do |v, i|
                filtered << Typelib.from_ruby(v, arguments_types[i])
            end
            CORBA.refine_exceptions(self) do
                yield(filtered)
            end
        end

        def result_value_for(type)
            raise ArgumentError, "I don't know how to handle #{type.name}" if type.opaque?

            type.new
        end

        # Returns a Typelib value that can store the result of this operation
        def new_result
            return_types.map do |type|
                result_value_for(type)
            end
        end

        # Requests the operation to be started. It does not wait for it to
        # finish, returning instead an OperationHandle object that can be used
        # to query the operation status and return value
        def sendop(*args)
            common_call(args) do |filtered|
                handle = task.do_operation_send(name, orocos_arguments_typenames, filtered)
                handle.instance_variable_set :@operation, self
                handle.instance_variable_set :@orocos_return_types, @orocos_return_typenames.dup
                handle.instance_variable_set :@return_values, new_result
                handle
            end
        end

        # Calls the method with the provided arguments, waiting for the method
        # to finish. It returns the value returned by the remote method.
        def callop(*args)
            raw_result = common_call(args) do |filtered|
                return_typename, return_value = nil
                unless @void_return
                    return_typename = orocos_return_typenames[0]
                    return_value = result_value_for(return_types.first)
                end

                task.do_operation_call(name, return_typename, return_value,
                                       orocos_arguments_typenames, filtered)

                result = []
                result << return_value if return_value
                inout_arguments.each do |index|
                    result << filtered[index]
                end
                result
            end

            result = []
            raw_result.each_with_index do |v, i|
                result << Typelib.to_ruby(v, return_types[i])
            end

            if result.empty?
                nil
            elsif result.size == 1
                result.first
            else
                result
            end
        end
    end
end
