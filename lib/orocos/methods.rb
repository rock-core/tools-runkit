module Orocos
    class RTTMethod
        # The method name
        attr_reader :name
        # The method description
        attr_reader :description
        # The type name of the return value
        attr_reader :return_spec
        # An array describing the arguments. Each element is <tt>[name, doc,
        # type_name]</tt>
        attr_reader :arguments_spec
        # The typelib types for the return value and the arguments. The array is
        # [return_type, arg1_type, ...]
        attr_reader :types

        class << self
            private :new
        end

        def initialize
            @types = []
            types << Orocos.registry.get(return_spec)
            arguments_spec.each do |_, _, type_name|
                types << Orocos.registry.get(type_name)
            end
            @args_type_names = arguments_spec.map { |name, doc, type| type }
        end

        # Calls the method with the last used arguments. This is much faster
        # than using #call because the arguments have already been marshalled
        # and sent to the other side
        #
        # Raises NeverCalled if the method has never been called before
        def recall
            CORBA.refine_exceptions(self) do
                result = types.first.new
                do_recall(result)
            end
        end

        # Calls the method with the provided arguments
        def call(*args)
            if args.size() != arguments_spec.size()
                raise ArgumentError, "not enough arguments"
            end

            result = types.first.new
            filtered = []
            args.each_with_index do |v, i|
                filtered << Typelib.from_ruby(v, types[i + 1])
            end

            CORBA.refine_exceptions(self) do
                do_call(@args_type_names, filtered, result)
            end
        end
    end
end

