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
        # The type name as registered in the runkit type system
        attr_reader :runkit_type_name

        def initialize(task, name, model)
            @task = task
            @name = name
            @runkit_type_name = model.type.name
            @type = Runkit.typelib_type_for(model.type, loader: model.task.loader)
        end

        def full_name
            "#{task.name}.#{name}"
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
            value = Typelib.from_ruby(value, type)
            do_write(@runkit_type_name, value, direct: direct)
            value
        end

        def new_sample
            type.zero
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type.name})"
        end
    end
end
