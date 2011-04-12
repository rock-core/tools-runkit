require 'orocos/task_context'
require 'orocos/nameservice_avahi'
require 'orocos/nameservice_corba'

module Nameservice
        
    # TODO: Allow this module to abstract all nameservice queries
    # CORBA, AVAHI and alike
    #
    class << self
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
            @@nameservices.each do |type, ns|
                   begin
                       task = ns.resolve(name) 
                   rescue Orocos::NotFound
                        next
                   end
                        
                   if task and task.kind_of?(::Orocos::TaskContext)
                       return task
                   end
            end
            raise Orocos::NotFound, "The service #{name} could not be resolved using following nameservices (in priority order): #{@@nameservices.keys.join(',')}"
        end

        # Retrieve a list of services that provide a certain type
        # returns the list of services as hash name => task
        # and task object as value
        # throws Orocos::NotFound if no service of given type 
        # has been found
        def resolve_by_type(type)
            #Resolve services by type
            tasks = {}
            @@nameservices.each do |type, ns|
                begin
                    resolved_tasks = ns.resolve_by_type(name)
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
        end

    end # class << self

end # module Nameservice

