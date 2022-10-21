# frozen_string_literal: true

module Runkit
    class Attribute < TaskContextAttributeBase
        def log_metadata
            super.merge("rock_stream_type" => "attribute")
        end

        def do_write(type_name, value, direct: false)
            if !direct && dynamic?
                do_write_dynamic(value)
            else
                task.do_attribute_write(name, type_name, value)
            end
        end

        def do_read(type_name, value)
            task.do_attribute_read(name, type_name, value)
        end
    end
end
