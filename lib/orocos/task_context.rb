module Orocos
    class TaskContext
        # The name of this task context
        attr_reader :name

        def pretty_print(pp)
            pp.text "Component #{name}"
            pp.text "  state: #{state}"
        end
    end
end

