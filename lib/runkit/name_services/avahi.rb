# frozen_string_literal: true

begin
    require "servicediscovery"
rescue LoadError
    raise LoadError,
          "NameService: 'distributed_nameserver' needs to be installed "\
          "for Avahi nameservice support"
end


module Runkit
    module NameServices
        # Name service to access Runkit Tasks which are publishing their IOR via
        # Avahi
        class Avahi < Base
            # A new instance of NameService which is listening on the given
            # search domain.  The serach domain must have a ._tcp or ._udp at
            # the end for a protocol type.
            #
            # @param [String] searchdomain The search domain the name service is
            #   listening to (_myrobot._tcp / _myrobot._udp)
            def initialize(searchdomain)
                @registered_tasks = {}
                @searchdomain = searchdomain

                @avahi_nameserver = ::Avahi::ServiceDiscovery.new

                # Start listening on the given domains (this does refer to the
                # _myservice._tcp service domain and not(!) the .local domain)
                begin
                    @avahi_nameserver.listen_on(Array(@searchdomain))
                rescue RuntimeError
                    raise ArgumentError,
                          "given search domain #{searchdomain} is invalid. "\
                          "Use '_myservice._tcp'."
                end
            end

            # (see NameServiceBase#names)
            def names
                @avahi_nameserver.get_all_services.uniq
            end

            # Registers the IOR of the given {Runkit::TaskContext} on the Avahi name service
            #
            # @param [Runkit::TaskContext] task The task.
            # @param [String] name The name which is used to register the task.
            def register(task, name: task.name)
                if @registered_tasks.key?(name)
                    update(name, task.ior)
                else
                    publish(name, task.ior)
                end
            end

            # Update an existing service registration
            def update(name, ior)
                service = @registered_tasks.fetch(name)
                service.set_description("IOR", ior)
                service.update
                service
            end

            # Publish a new service
            def publish(name, ior)
                service = ::Avahi::ServiceDiscovery.new
                service.set_description("IOR", ior)
                @registered_tasks[name] = service
                service.publish(name, @searchdomain)
                service
            end

            # Deregisters the given name or task from the name service.
            #
            # @param [String,TaskContext] task The name or task
            # @note This only works for tasks which were registered by the same ruby instance.
            def deregister(name)
                @registered_tasks.delete(name)
            end

            # (see Base#ior)
            def ior(name)
                services = @avahi_nameserver.find_services(name)
                if services.empty?
                    raise Runkit::NotFound,
                          "Avahi nameservice could not find a task named '#{name}'"
                elsif services.size > 1
                    Runkit.warn(
                        "Avahi: '#{name}' found multiple times. Possibly due to "\
                        "publishing on IPv4 and IPv6, or on multiple interfaces "\
                        "-- picking first one in list"
                    )
                end

                ior = services.first.get_description("IOR")
                if !ior || ior.empty?
                    raise NotFound,
                          "Avahi nameservice could not retrieve an ior for task #{name}"
                end

                ior
            end
        end
    end
end