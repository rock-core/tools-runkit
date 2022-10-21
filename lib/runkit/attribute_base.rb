# frozen_string_literal: true

module Runkit
    # Common implementation for {Property} and {Attribute}
    class AttributeBase
        # The underlying TaskContext instance
        attr_reader :task
        # The property/attribute name
        attr_reader :name
        # The attribute type, as a subclass of Typelib::Type
        attr_reader :type
        # If set, this is a Pocolog::DataStream object in which new values set
        # from within Ruby are set
        attr_accessor :log_stream
        # If set, this is an input port object in which new values set from
        # within Ruby are sent
        attr_accessor :log_port
        # The type name as registered in the runkit type system
        attr_reader :runkit_type_name

        def initialize(task, name, runkit_type_name)
            @task = task
            @name = name
            @runkit_type_name = runkit_type_name
        end

        def full_name
            "#{task.name}.#{name}"
        end

        # @deprecated
        # Returns the name of the typelib type. Use #type.name instead.
        def type_name
            type.name
        end

        def ==(other)
            name == other.name && task == other.task
        end

        def log_metadata
            Hash[
                "rock_task_model" => (task.model.name || ""),
                "rock_task_name" => task.name,
                "rock_task_object_name" => name,
                "rock_runkit_type_name" => runkit_type_name,
                "rock_cxx_type_name" => runkit_type_name
            ]
        end

        def raw_read
            value = type.new
            do_read(@runkit_type_name, value)
            value
        end

        # Read the current value of the property/attribute
        def read
            Typelib.to_ruby(raw_read)
        end

        # Sets a new value for the property/attribute
        def write(value, timestamp = Time.now, direct: false)
            ensure_type_available
            value = Typelib.from_ruby(value, type)
            do_write(@runkit_type_name, value, direct: direct)
            log_value(value, timestamp)
            value
        end

        # Write the current value of the property or attribute to #log_stream
        def log_current_value(timestamp = Time.now)
            log_value(read)
        end

        def log_value(value, timestamp = Time.now)
            log_stream&.write(timestamp, timestamp, value)
            log_port&.write(value)
        end

        def new_sample
            ensure_type_available
            type.zero
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type.name})"
        end
    end
end
