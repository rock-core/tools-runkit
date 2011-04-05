require 'orocos/nameservice_interfaces.rb'

module Nameservice

    class AVAHI < NameserviceProvider

        def initialize
            super
            @avahi_nameserver = nil

            @options[:label] = "Search domain label"
            @options[:searchdomain] = "Search domain set to 'rimres' maps to _rimres._tcp" 
        end
    
        # Check is the nameserver is enabled
        def enabled?
            if @avahi_nameserver
                return true
            end
                
            return false
        end

        # Return the IOR 
        # Throws Nameservice::NoAccess if the IOR cannot be retrieved
        # due to an uninitialized nameserver
        # Throws NoServiceFound if the service could not be found
        # due to an uninitialized nameserver
        def getIOR(name)
            ior = nil
            if @avahi_nameserver
                ior = @avahi_nameserver.getIOR(name)
                if not ior 
                    raise NoServiceFound
                end
    
                return ior
            end
    
            raise NoAccess
        end
    
        # Retrieve a list of services that provide a certain type
        # returns the list of services 
        # throws Nameserver::NoServiceFound if no service of given type 
        # has been found
        def getByType(type)
            if @avahi_nameserver
                services = @avahi_nameserver.getByType(type)
                if services.empty?
                    raise NoServiceFound
                end
    
                return services
            end
        
            raise NoServiceFound    
        end
    
        # Enable the avahi based nameserver
        # 'searchdomain' maps to _searchdomain._tcp in Avahi
        def enable(options)
            if enabled?
                warn "Nameservice: ignoring request to enable, because nameservice is already running"
                return
            end
               
            ## Introduce alternative avahi based nameserver if corba does not work
            begin 
                require 'avahi_nameserver'
    
                if not @avahi_nameserver
                    # Requires a hash to specify a searchdomain use: 
                    # {'label of searchdomain' => 'searchdomain'}
                    @avahi_nameserver = ::Avahi::Manager.new( { options[:label], options[:searchdomain] } )
                end
                # We need to wait till nameserver communicates with DBus
                # wait maximum of 6 second for initialization
                for i in 0..20
                    sleep 0.3
                    if @avahi_nameserver.initialized?
                        return true
                    end
                end
                warn "Nameservice: avahi nameserver could not be initialized" 
            rescue LoadError
                warn "Nameservice: 'distributed_nameserver' needs to be installed for AVAHI nameservice support"
            rescue => exception
                # ignore errors and return false eventually
                warn "Nameservice: error in AVAHI nameservice"
                print exception.backtrace.join("\n")
            end
    
            return false
        end

    end # class AVAHI

end # Module Nameservice
