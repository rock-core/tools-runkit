# frozen_string_literal: true

module Runkit
    # Property of a remote task context
    class Property < TaskContextAttributeBase
        def log_metadata
            super.merge("rock_stream_type" => "property")
        end

        def do_write(type_name, value, direct: false)
            if !direct && dynamic?
                do_write_dynamic(value)
            else
                task.do_property_write(name, type_name, value)
            end
        end

        def do_read(type_name, value)
            task.do_property_read(name, type_name, value)
        end
    end
end
