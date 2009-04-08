
module Orocos
    class Port
        def ==(other)
            other.class == self.class &&
                other.task == self.task &&
                other.name == self.name
        end
    end
end

