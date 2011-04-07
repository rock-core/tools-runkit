require 'orocos/nameservice_interfaces.rb'

module Nameservice

    class AVAHI < Provider

        def initialize(options)
            super
            enable(options)
        end

        def self.options
            @@options[:searchdomains] = "Search domains as hash of 'label' => 'domain, where a plain domainname will by default be expaned to _domain._tcp"

            @@options
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
        # Throws Orocos::NotFound if the service could not be found
        # due to an uninitialized nameserver
        def get_ior(name)
            ior = nil
            if @avahi_nameserver
                ior = @avahi_nameserver.get_ior(name)
                if not ior 
                    raise Orocos::NotFound, "AVAHI nameservice could not retrieve an ior for task #{name}"
                end
    
                return ior
            end
    
            raise NoAccess
        end
    
        # Retrieve a list of services that provide a certain type
        # returns the list of services 
        # throws Orocos::NotFound if no service of given type 
        # has been found
        def resolve_by_type(type)
            tasks={}
            if @avahi_nameserver
                services = @avahi_nameserver.get_service_by_type(type)
                if services.empty?
                    raise Orocos::NotFound
                end
                services.each do |name, description|
                    task = resolve(name)
                    tasks[name] = task
                end
            end
            tasks
        end
    
        # Enable the avahi based nameserver
        # option :searchdomains is available and expects a hash { "label" => "domain-0", ...}
        def enable(options)
            if enabled?
                warn "Nameservice: ignoring request to enable, because nameservice is already running"
                return
            end
               
            ## Introduce alternative avahi based nameserver if corba does not work
            begin 
                require 'avahi_nameserver'
                if not @avahi_nameserver
                    # Test required options
                    # Provide a list of searchdomains
                    # { :searchdomains => { "label" => "domain", "label-1" => "domain-1" }
                    @avahi_nameserver = ::Avahi::Manager.instance( options )
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
                raise LoadError, "Nameservice: 'distributed_nameserver' needs to be installed for AVAHI nameservice support"
            end
        end

        # Resolve a service based on its name
        # return TaskContext
        # throws Exception if the service cannot be resolved
        def resolve(name)
            ior = get_ior(name)
            result=nil
            if ior
                result = ::Orocos::CORBA.refine_exceptions("naming service") do
                     ::Orocos::TaskContext::do_get_from_ior(ior)
                end
            else 
                raise Orocos::NotFound
            end
            result
        end

    end # class AVAHI

end # Module Nameservice
