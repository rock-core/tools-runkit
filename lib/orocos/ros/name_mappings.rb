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

            def to_command_line
                result = []
                mappings.each do |from, to|
                    if from =~ /^~/
                        from = "_#{from[1..-1]}"
                    end
                    result << "#{from}:=#{to}"
                end
                result.join(" ")
            end
        end
    end
end

