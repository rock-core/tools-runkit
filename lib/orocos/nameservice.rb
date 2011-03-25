require 'orocos/nameservice_avahi'

module Nameservice
        
    class << self
        @@nameservices = {}

        # Enable a nameservice
        # Options are provided as a hash, i.e.
        # { :option_0 => 'value_0', :option_1 => 'value_1, ... }
        # Request a list of available options via getOptions 
        def enable(type, options)
            enabled = false
            begin 
                nameserviceKlass = eval("#{type}")
                if nameserviceKlass
                    if nameserviceKlass.instance.enable(options)
                        @@nameservices[type] = nameserviceKlass.instance
                        enabled = true
                    end
                end
            rescue NameError 
                warn "Nameservice: enabling failed due to unknown nameservice type #{type}"
            end

            enabled
        end

        def enabled?(type)
            enabled = false
            if @@nameservices.has_key?(type)
                enabled = @@nameservices[type].enabled?
            end

            enabled
        end
        
        # Retrieve a nameservice by type
        # 
        def get(type)
            instance = nil
            if @@nameservices.has_key?(type)
                instance = @@nameservices[type]
            end

            instance
        end

        # Retrieve
        # 
        def getOptions(type)
            options = {}
            instance = get(type)
            if instance
                options = instance.getOptions
            end

            options
        end

        # Retrieve a list of services that provide a certain type
        # returns the list of services 
        # throws Nameserver::NoServiceFound if no service of given type 
        # has been found
        def getByType(type)
                raise UnsupportedFunctionality
        end

    end # class << self

end # module Nameservice

