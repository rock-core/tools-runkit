module Nameservice 
    # NoAccess Exception to be thrown when the nameservice provider is
    # not accessible
    class NoAccess < Exception
    end
    
    # UnsupportedFeature Exception for optional
    # functionality
    class UnsupportedFeature < Exception
    end

    # Superclass for nameservice implementations
    class Provider

        @@options = {}

        def initialize(options)
            # using option_description due to disambiguation
        end
    
        # Overload method to allow retrieval of options
        def self.options
            # return here the option the nameservice provider requires, including a description
        end

        # Overload method to allow disabling of the name service 
        def enabled?
            true
        end
        
        # Retrieve an instance of a certain nameservice type
        # Provide options as Hash
        def self.get_instance_of(type, options)
            instance=nil
            begin 
                nameserviceKlass = Nameservice.const_get(type)
                instance = nameserviceKlass.new(options)
                if not instance.is_a?(Provider)
                    raise NameError, "#{type} is not a valid name service type"
                end
            rescue NameError
                raise NameError, "#{type} is not a known ruby type"
            end
            instance
        end
        
        # Resolve a nameservice and return a TaskContext
        # requires 
        def resolve(name)
            raise NotImplementedError
        end

        # Resolve a nameservice 
        def resolve_by_type(name)
            raise UnsupportedFeature
        end

    end
end
