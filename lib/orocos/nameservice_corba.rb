module Nameservice
    class CORBA < Provider
        def initialize(options)
            super
            ::Orocos::CORBA::name_service=options[:host]
        end

        def resolve(name)
	    Orocos::CORBA.get(:do_get, name)
        end

        def self.options
            @@options[:host] = "Hostname where the corba nameservice is running"
            @@options
        end
    end # end CORBA
end #end Nameservice

