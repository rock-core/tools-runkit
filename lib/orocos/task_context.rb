require 'utilrb/object/attribute'

module Orocos
    class Attribute
        attr_reader :name
        attr_reader :typename

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{typename})"
        end
    end

    class TaskContext
        # The name of this task context
        attr_reader :name

        def initialize
            @ports ||= Hash.new
        end

        def port(name)
            name = name.to_str
            if @ports[name]
                if has_port?(name) # Check that this port is still valid
                    @ports[name]
                else
                    @ports.delete(name)
                    raise NotFound, "no port named '#{name}' on task '#{self.name}'"
                end
            else
                @ports[name] = do_port(name)
            end
        end

        def pretty_print(pp)
            states_description = TaskContext.constants.grep(/^STATE_/).
                inject([]) do |map, name|
                    map[TaskContext.const_get(name)] = name.gsub /^STATE_/, ''
                    map
                end

            pp.text "Component #{name}"
            pp.breakable
            pp.text "  state: #{states_description[state]}"
            pp.breakable

            pp.nest(2) do
                pp.text "  "
                each_attribute do |attribute|
                    attribute.pretty_print(pp)
                    pp.breakable
                end
            end

            pp.nest(2) do
                pp.text "  "
                each_port do |port|
                    port.pretty_print(pp)
                    pp.breakable
                end
            end
        end
    end
end

