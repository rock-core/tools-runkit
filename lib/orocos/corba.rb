require 'rorocos_ext'
require 'typelib'
module Orocos

    module CORBA
        extend Logger::Forward
        extend Logger::Hierarchy

        class << self
            # The address at which to contact the CORBA naming service
            attr_accessor :name_service
        end
        @name_service = "127.0.0.1"

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

            attr_reader :loaded_toolkits
            def loaded_toolkit?(name)
                loaded_toolkits.include?(name)
            end
        end
        @loaded_toolkits = []

	def self.init
	    ENV['ORBInitRef'] ||= "NameService=corbaname::#{CORBA.name_service}"
            do_init
	end

        call_timeout    = 1000
        connect_timeout = 1000

        def self.load_plugin_library(pkg, name, libname)
            libpath = pkg.library_dirs.find do |dir|
                full_path = File.join(dir, libname)
                break(full_path) if File.file?(full_path)
            end

            if !libpath
                raise NotFound, "cannot find toolkit shared library for #{name} (searched for #{libname} in #{pkg.libdirs.join(", ")})"
            end

            lib = Typelib::Library.open(libpath, nil, false)
            factory = lib.find('loadRTTPlugin').
                with_arguments('void*')
            factory[nil]
            true
        end

        def self.load_toolkit(name)
            return if loaded_toolkit?(name)

            toolkit_pkg =
                begin
                    Utilrb::PkgConfig.new("#{name}-toolkit-#{Orocos.orocos_target}")
                rescue Utilrb::PkgConfig::NotFound
                    raise NotFound, "the '#{name}' toolkit is not available to pkgconfig"
                end
            load_plugin_library(toolkit_pkg, name, "lib#{name}-toolkit-#{Orocos.orocos_target}.so")

            if Orocos::Generation::VERSION >= "0.8"
                corba_transport_pkg =
                    begin
                        Utilrb::PkgConfig.new("#{name}-transport-corba-#{Orocos.orocos_target}")
                    rescue Utilrb::PkgConfig::NotFound
                        raise NotFound, "the '#{name}' CORBA transport is not available to pkgconfig"
                    end
                load_plugin_library(corba_transport_pkg, name, "lib#{name}-transport-corba-#{Orocos.orocos_target}.so")
            end

            @loaded_toolkits << name

            # Now, if this is an orogen toolkit, then load the corresponding
            # data types. orogen defines a type_registry field in the pkg-config
            # file for that purpose.
            tlb = toolkit_pkg.type_registry
            if tlb
                Orocos.registry.import(tlb)
            end

            nil
        end

        def self.refine_exceptions(obj0, obj1 = nil)
            yield

        rescue ComError
            if !obj1
                raise ComError, "communication failed with #{obj0}"
            else
                raise ComError, "communication failed with either #{obj0} or #{obj1}"
            end
        end
    end
end

