require 'orocos/nameservice_corba.rb'

module Nameservice
    class CORBA < Provider

    def initialize(options)
        super
        ::Orocos::CORBA::name_service=options[:host]
    end

    def resolve(name)
        result = ::Orocos::CORBA.refine_exceptions("naming service") do
            ::Orocos::TaskContext.do_get(name)
        end
    end

    def self.options
        @@options[:host] = "Hostname where the corba nameservice is running"
        @@options
    end

    end # end CORBA
end #end Nameservice

