# frozen_string_literal: true

module Runkit
    # Aggregation of other name services
    #
    # @see NameServices
    class NameService < NameServices::Base
        # Returns a new instance of NameService
        #
        # @param [Array<NameServices::Base>] name_services The
        #   initial underlying name services
        def initialize(*name_services)
            @name_services = name_services
        end

        # Enumerates the name services registered on this global name service
        #
        # @yield [NameServices::Base]
        def each(&block)
            @name_services.each(&block)
        end

        # Adds a name service.
        #
        # @param [NameServiceBase] name_service The name service.
        def <<(name_service)
            add(name_service)
        end

        # Adds a name service to the top of {#name_services}
        #
        # @param [NameServiceBase] name_service The name service.
        def add_front(name_service)
            return if @name_services.include? name_service

            @name_services.insert(0, name_service)
        end

        # (see #<<)
        def add(name_service)
            return if @name_services.include? name_service

            @name_services << name_service
        end

        # Checks if there is at least one underlying name service
        #
        # @return [Boolean]
        def initialized?
            !@name_services.empty?
        end

        # (see NameServices::Base#get)
        def get(name, **)
            @name_services.each do |service|
                return service.get(name, **options)
            rescue Runkit::NotFound # rubocop:disable Lint/SuppressedException
            end

            raise Runkit::NotFound, error_message(name)
        end

        # (see NameServices::Base#ior)
        def ior(name)
            @name_services.each do |service|
                next unless service.respond_to?(:ior)

                begin
                    return service.ior(name)
                rescue Runkit::NotFound # rubocop:disable Lint/SuppressedException
                end
            end
            raise Runkit::NotFound, error_message(name)
        end

        # (see NameServices::Base#names)
        def names
            @name_services.flat_map(&:names).uniq
        end

        # Calls cleanup on all underlying name services which support cleanup
        def cleanup
            @name_services.each(&:cleanup)
        end

        # remove the service from the list of services
        def delete(service)
            @name_services.delete(service)
        end

        # Removes all underlying name services
        def clear
            @name_services.clear
        end

        private

        # Generates an error message if a {TaskContext} of the given name cannot be found
        #
        # @param [String] name The name of the task
        def error_message(name)
            if @name_services.empty?
                "the remote task context #{name} could not be resolved, because "\
                    "no name services are registered"
            else
                "the remote task context #{name} could not be resolved using "\
                    "following name services (in priority order): "\
                    "#{@name_services.join(', ')}"
            end
        end
    end
end
