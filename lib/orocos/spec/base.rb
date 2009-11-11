module Orocos
    module Spec
        class ConfigError < RuntimeError; end
        class SpecError < RuntimeError; end
        class AmbiguousConnections < SpecError; end
    end
end

