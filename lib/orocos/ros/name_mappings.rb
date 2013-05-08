module Orocos
    module ROS
        # Implementation of the ROS name mappings rules
        class NameMappings
            attr_reader :mappings

            def initialize(mappings = Hash.new)
                @mappings = mappings
            end

            def apply(string)
                mappings[string] || string
            end
        end
    end
end

