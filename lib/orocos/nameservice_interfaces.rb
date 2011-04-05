require 'singleton'

module Nameservice 
    # NoAccess Exception to be thrown when the nameservice provider is
    # not accessible
    class NoAccess < Exception
    end
    
    # NoServiceFound to be thrown when 
    # a service cannot be found via the 
    # active nameservices
    class NoServiceFound < Exception
    end
    
    # NotImplemented Exception
    class NotImplemented < Exception
    end
 

    # Superclass for all Nameservice implementations
    class NameserviceProvider
        include Singleton

        attr_reader :options

        def initialize
            @options = {}
        end

    end
end
