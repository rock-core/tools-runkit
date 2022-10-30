# frozen_string_literal: true

module Runkit
    module NameServices
        # Access to the CORBA name service
        class CORBA < Base
            def initialize(host = "")
                self.ip = host
            end

            # Sets the ip address or host name where the CORBA name service is running
            #
            # @param [String] host The ip address or host name
            def ip=(host)
                reset(host)
            end

            # @return [String] The ip where the client tries to reach the CORBA name service
            def ip
                do_ip
            end

            # @return [String] The port where the client tries to reach the CORBA name service
            def port
                do_port
            end

            # Resets the CORBA name service client.
            #
            # @param [String] ip The ip address or host name where the CORBA name service is running
            # @param [String] port The port of the CORBA name service
            def reset(ip = self.ip, port = self.port)
                do_reset(ip, port)
            end

            # (see NameServiceBase#ior)
            def ior(name)
                Runkit::CORBA.refine_exceptions("corba naming service(#{ip})") do
                    do_ior(name)
                end
            end

            # (see NameServiceBase#names)
            def names
                Runkit::CORBA.refine_exceptions("corba naming service(#{ip})") do
                    do_task_context_names.find_all { |n| n !~ /^runkitrb_(\d+)$/ }
                end
            rescue NotFound
                []
            end

            # (see NameServiceBase#get)
            def get(name, **options)
                Runkit::TaskContext.new(ior(name), name: name, **options)
            end

            # Registers the IOR of the given {Runkit::TaskContext} on the CORBA name service.
            #
            # @param [Runkit::TaskContext] task The task.
            # @param [String] name The name which is used to register the task.
            def register(task, name: task.name)
                do_bind(task, name)
            end

            # Deregisters the given name from the name service.
            #
            # @param [String,TaskContext] name The name or task
            def deregister(name)
                Runkit::CORBA.refine_exceptions("corba naming service #{ip}") do
                    do_unbind(name)
                end
            end

            # (see NameServiceBase#validate)
            def validate
                Runkit::CORBA.refine_exceptions("corba naming service #{ip}") do
                    do_validate
                rescue Runkit::ComError => e
                    Runkit.warn "Name service is unreachable: #{e.message}\n"
                    Runkit.warn "You can try to fix this manually by restarting the nameserver:\n"
                    Runkit.warn "    sudo /etc/init.d/omniorb4-nameserver stop\n"
                    Runkit.warn "    sudo rm -f /var/lib/omniorb/*\n"
                    Runkit.warn "    sudo /etc/init.d/omniorb4-nameserver start\n"
                    raise
                end
            end

            # Removes dangling references from the name service
            #
            # This method removes objects that are not accessible anymore from the
            # name service
            def cleanup
                names.dup.each do |n|
                    CORBA.info "trying task context #{n}"
                    task = get(n)
                    task.ping
                rescue Runkit::ComError => e
                    deregister(n)
                    Runkit::CORBA.warn(
                        "deregistered dangling CORBA name #{n}: #{e.message}"
                    )
                end
            end
        end
    end
end
