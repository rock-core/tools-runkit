# frozen_string_literal: true

module Runkit
    module PortBase
        # The task this port is part of
        attr_reader :task
        # The port name
        attr_reader :name
        # The port full name. It is task_name.port_name
        def full_name
            "#{task.name}.#{name}"
        end
        # The port's type name as used by the RTT
        attr_reader :runkit_type_name
        # The port's type as a Typelib::Type object
        attr_reader :type
        # The port's model
        # @return [OroGen::Spec::Port,nil] the port model
        attr_reader :model

        def initialize(task, name, runkit_type_name, model)
            @task = task
            @name = name
            @runkit_type_name = runkit_type_name
            @model = model

            @max_sizes =
                if model
                    model.max_sizes.dup
                else
                    {}
                end

            @max_sizes.merge!(Runkit.max_sizes_for(type))

            super() if defined? super
        end

        D_UNKNOWN      = 0
        D_SAME_PROCESS = 1
        D_SAME_HOST    = 2
        D_DIFFERENT_HOSTS = 3

        # How "far" from the given input port this port is
        #
        # @return one of the D_ constants
        def distance_to(input_port)
            if !task.process || !input_port.task.process
                D_UNKNOWN
            elsif task.process == input_port.task.process
                D_SAME_PROCESS
            elsif task.process.host_id == input_port.task.process.host_id
                D_SAME_HOST
            else D_DIFFERENT_HOSTS
            end
        end

        def to_s
            full_name.to_s
        end

        # True if +self+ and +other+ represent the same port
        def ==(other)
            return false unless other.kind_of?(PortBase)

            other.task == task && other.name == name
        end

        # Returns a new object of this port's type
        def new_sample
            @type.zero
        end

        def log_metadata
            Hash["rock_task_model" => (task.model.name || ""),
                 "rock_task_name" => task.name,
                 "rock_task_object_name" => name,
                 "rock_stream_type" => "port",
                 "rock_runkit_type_name" => runkit_type_name,
                 "rock_cxx_type_name" => runkit_type_name]
        end

        # @overload max_sizes('name.to[].field' => value, 'name.other' => value) => self
        #   Sets the maximum allowed size for the variable-size containers in
        #   +type+. If the type is a compound, the mapping is given as
        #   path.to.field => size. If it is a container, the size of the
        #   container itself is given as first argument, and the sizes for the
        #   contained values as a second map argument.
        #
        #   For instance, with the types
        #
        #     struct A
        #     {
        #         std::vector<int> values;
        #     };
        #     struct B
        #     {
        #         std::vector<A> field;
        #     };
        #
        #   Then sizes on a port of type B would be given with
        #
        #     port.max_sizes('field' => 10, 'field[].values' => 20)
        #
        #   while the sizes on a port of type std::vector<A> would be given
        #   with
        #
        #     port.max_sizes(10, 'values' => 20)
        #
        # @overload max_sizes => current size specification
        #
        dsl_attribute :max_sizes do |*values|
            # Validate that all values are integers and all names map to
            # known types
            value = OroGen::Spec::OutputPort.validate_max_sizes_spec(type, values)
            max_sizes.merge(value)
        end

        # Returns the maximum marshalled size of a sample from this port, as
        # marshalled by typelib
        #
        # If the type contains variable-size containers, the result is dependent
        # on the values given to #max_sizes. If not enough is known, this method
        # will return nil.
        def max_marshalling_size
            OroGen::Spec::OutputPort.compute_max_marshalling_size(type, max_sizes)
        end
    end
end
