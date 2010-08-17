module Orocos
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
        # The subclass of Typelib::Type that represents the type of the return value
        attr_reader :return_type
        # An array describing the arguments. Each element is a <tt>[name, doc,
        # type_name]</tt> tuple
        attr_reader :arguments_spec
        # The typelib types for the arguments. This is an array of subclasses of
        # Typelib::Type, with each element being the type of the corresponding
        # element in #arguments_spec
        attr_reader :arguments_types

        def initialize(task, name, return_spec, arguments_spec)
            @task, @name, @return_spec, @arguments_spec =
                task, name, return_spec, arguments_spec

            @return_type = Orocos.registry.get(return_spec)
            @arguments_types = []
            arguments_spec.each do |_, _, type_name|
		type_name.gsub! /\s+.*$/, ''
                arg_type = Orocos.registry.get(type_name)
                arguments_types << arg_type
            end
            @args_type_names = arguments_spec.map { |name, doc, type| type }
        end

        # Helper method for RTTMethod and Command
        def common_call(args) # :nodoc:
            if args.size() != arguments_spec.size()
                raise ArgumentError, "not enough arguments"
            end

            filtered = []
            args.each_with_index do |v, i|
                if arguments_types[i].name == "/std/string"
                    filtered << v.to_str
                else
                    filtered << Typelib.from_ruby(v, arguments_types[i])
                end
            end
            CORBA.refine_exceptions(self) do
                yield(filtered)
            end
        end

        # Calls the method with the provided arguments, and returns the value
        # returned by the remote method.
        def call(*args)
            result = if return_type.null?
                     elsif return_type.name == "string" || return_type.name == "/std/string"
                         ""
                     elsif return_type.opaque?
                         raise ArgumentError, "I don't know how to handle #{return_type.name}"
                     else
                         return_type.new
                     end

            common_call(args) do |filtered|
                result = task.do_operation_call(name, return_spec, @args_type_names, filtered, result)
            end
            Typelib.to_ruby(result)
        end
    end
end

