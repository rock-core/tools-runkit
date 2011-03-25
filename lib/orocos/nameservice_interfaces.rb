require 'singleton'

module Nameservice 
    class NoAccess < Exception
    end

    class NoServiceFound < Exception
    end

    class NotImplemented < Exception
    end

    class NameserviceInstance
        include Singleton

        attr_reader :options

        def initialize
            @options = {}
        end

    end
end
