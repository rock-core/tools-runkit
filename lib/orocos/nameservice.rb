require 'orocos/task_context'
require 'orocos/nameservice_avahi'
require 'orocos/nameservice_corba'
require 'orocos/nameservice_local'

module Nameservice
        
    # TODO: Allow this module to abstract all nameservice queries
    # CORBA, AVAHI and alike 
    #
    # Example: 
    #
    # require 'orocos'
    # include Orocos
    # 
    # # The order of activation is used as priority order for the search of modules 
    # Nameservice::enable(:AVAHI, :searchdomains => [ "_rimres._tcp" ])
    # # Corba is the default, if you have not enabled any nameservice upon calling resolve
    # # Nameservice::enable(:CORBA, :host => "127.0.0.1")
    #
    # Orocos.initialize
    #
    # task = TaskContext.get 'your_module'
    #
    class << self
        # Priority order depends on insertion sequence (to make sure it works in ruby 1.8.x)
        @@priority_order = []
        # List of all available nameservice provider
        @@nameservices = {}

        # Enable a nameservice
        # Options are provided as a hash, i.e.
        # { :option_0 => 'value_0', :option_1 => 'value_1, ... }
        # Request a list of available options via call to options(type)
        def enable(type, options = {} )

            if @@nameservices[type]
                # already enabled
                return
            end

            # To embed a new nameserver we require a 
            # NameserviceInstance of that type
            ns = Provider.get_instance_of(type, options)
            @@nameservices[type] = ns
            @@priority_order << type
            ns
        end

        # Check if nameservice of a given type is enabled
        # return true, if nameservice of given type is enable otherwise false
        def enabled?(type)
            enabled = false
            if @@nameservices[type]
                enabled = @@nameservices[type].enabled?
            end

            enabled
        end
        
        # Retrieve a nameservice by type
        # If type is unknown, returns +nil+
        def get(type)
            instance = nil
            if @@nameservices.has_key?(type)
                instance = @@nameservices[type]
            end

            instance
        end
        
        # Resolve a name by type
        # return TaskContext or +nil+
        def resolve(name)
            # Resolves the name using existing nameservices 
            if @@nameservices.empty?
                raise Orocos::NotFound, "No nameservice has been enabled"
            end

            types=[]
            @@priority_order.each do |type|
                   types << type
                   begin
                       task = @@nameservices[type].resolve(name) 
                   rescue Orocos::NotFound
                        next
                   end
                        
                   if task and task.kind_of?(::Orocos::TaskContext)
                       return task
                   end
            end
            raise Orocos::NotFound, "The service #{name} could not be resolved using following nameservices (in priority order): #{@@priority_order.join(', ')}"
        end

        # Retrieve a list of services that provide a certain type
        # returns the list of services as hash name => task
        # and task object as value
        # throws Orocos::NotFound if no service of given type 
        # has been found
        def resolve_by_type(typename)
            #Resolve services by type
            tasks = {}
            @@priority_order.each do |type|
                begin
                    resolved_tasks = @@nameservices[type].resolve_by_type(typename)
                    # Add only new tasks
                    resolved_tasks.each do |name, task|
                        if not tasks[name]
                            tasks[name] = task
                        end
                    end
                rescue UnsupportedFeature
                    warn "Nameservice: #{type} does not support resolution of TaskContexts by type"
                end
            end
        end

        # Retrieve available options for a nameservice type
        # returns a hash with optionname => description
        # 
        def options(type)
            nameserviceKlass = Nameservice.const_get(type)
            nameserviceKlass.options
        end

        # Resets the nameservice by removing all known 
        # nameservices
        def reset
            @@nameservices.clear
            @@priority_order.clear
        end

        # Validate nameservice before starting the corba layer
        # Otherwise the default of CORBA nameservice cannot be applied
        def available?
            not @@nameservices.empty?
        end

    end # class << self

end # module Nameservice

