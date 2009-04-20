require 'rorocos_ext'
module Orocos
    module CORBA
        extend Logger::Forward
        extend Logger::Hierarchy

        def self.cleanup
            names = Orocos.task_names.dup
            names.each do |n|
                begin
                    CORBA.info "trying task context #{n}"
                    TaskContext.get(n)
                rescue Orocos::NotFound
                    CORBA.warn "unregistered dangling CORBA name #{n}"
                end
            end
        end

        class << self
            attr_reader :call_timeout
            def call_timeout=(value)
                do_call_timeout(value)
                @call_timeout = value
            end
            attr_reader :connect_timeout
            def connect_timeout=(value)
                do_connect_timeout(value)
                @connect_timeout = value
            end
        end

        if !init
            raise "cannot initialize the CORBA layer"
        end

        call_timeout    = 1000
        connect_timeout = 1000
    end
end

