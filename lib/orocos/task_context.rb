module Orocos
    class Port
        attr_reader :task
        attr_reader :name
        attr_reader :typename

        def connect(other)
            # Check port compatibility
            if self.class != other.class
                raise "#{name} and #{other.name} do not have the same connection model"
            elsif self.typename != other.typename
                raise "#{name} and #{other.name} do not hold the same data type"
            end

            if write? && other.read?
                other.do_connect(self)
            elsif other.write? && read?
                do_connect(other)
            else
                raise "cannot create a connection because there is not one reader and one writer"
            end
        end

        def pretty_print(pp) # :nodoc:
            pp.text "#{self.class.name} #{name}"

            if read? then pp.text "[R]"
            elsif write? then pp.text "[W]"
            else pp.text "[RW]"
            end
        end
    end

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

