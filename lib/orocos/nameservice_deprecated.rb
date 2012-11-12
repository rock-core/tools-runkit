
# DEPRECATED
# compatibility code

module Nameservice
    def self.deprecation(method,message)
        Orocos.warn "[DEPRECATION] `Nameservice.#{method}` is deprecated. Please use #{message} instead."
    end

    def self.removed(method)
        raise NotImplemented,"[REMOVED] `#{method}` was removed.  #{message}"
    end

    def self.enable(type, options = {} )
        deprecation "enable(TYPE,options)" ,"Orocos.name_service << Orocos::TYPE::NameService.new(para)"
        type = (type == :AVAHI ? :Avahi : type)
        klass = Orocos.const_get(type)::NameService
        if !Orocos.name_service.include?(klass)
            if klass == Orocos::Avahi::NameService
                domain = options[:searchdomains]
                domain = if domain && domain.is_a?(Array)
                             if domain.size > 1
                                 Orocos.warn "Avahi name service does only support one domain. Add multiple name services"
                             end
                             domain.first
                         end
                Orocos.name_service << klass.new(domain)
            elsif klass == Orocos::CORBA::NameService
                Orocos::CORBA.name_service.ip = options[:host] if options.has_key?(:host)
                Orocos.name_service << Orocos::CORBA.name_service unless Orocos.name_service.include?(Orocos::CORBA::NameService)
            else
                Orocos.name_service << klass.new(options)
            end
        end
    end

    def self.enabled?(type)
        deprecation "enabled?(TYPE)" ,"Orocos.name_service.include?(Orocos::TYPE::NameService)"
        type = (type == :AVAHI ? :Avahi : type)
        klass = Orocos.const_get(type)::NameService
        Orocos.name_service.include?(klass)
    end

    def self.get(type)
        deprecation "get(TYPE)" ,"Orocos.name_service.find(Orocos::TYPE::NameService)"
        type = (type == :AVAHI ? :Avahi : type)
        klass = Orocos.const_get(type)::NameService
        Orocos.name_service.find(klass)
    end

    def self.resolve(name,options = Hash.new)
        deprecation "resolve" ,"Orocos.name_service.get"
        Orocos.name_service.get(name,options)
    end

    def self.options(type)
        removed "options"
    end

    def self.reset
        deprecation "reset" ,"Orocos.name_service.clear"
        Orocos.name_service.clear
    end

    def self.available?
        deprecation "avilable?" ,"Orocos.name_service.initialized?"
        Orocos.name_service.initialized?
    end
end

