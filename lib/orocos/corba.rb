require 'rorocos_ext'
require 'typelib'
module Orocos
    class << self
        attr_reader :registry
    end
    @registry = Typelib::Registry.new

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

            attr_reader :loaded_toolkits
            def loaded_toolkit?(name)
                loaded_toolkits.include?(name)
            end
        end
        @loaded_toolkits = []

        if !init
            raise "cannot initialize the CORBA layer"
        end

        call_timeout    = 1000
        connect_timeout = 1000

        def self.load_toolkit(name)
            return if loaded_toolkit?(name)

            pkg = begin
                      Utilrb::PkgConfig.new("#{name}-toolkit-gnulinux")
                  rescue Utilrb::PkgConfig::NotFound
                      raise NotFound, "the '#{name}' toolkit is not available to pkgconfig"
                  end

            libname = "lib#{name}-toolkit-gnulinux.so"
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

            @loaded_toolkits << name

            # Now, if this is an orogen toolkit, then load the corresponding
            # data types. orogen defines a type_registry field in the pkg-config
            # file for that purpose.
            tlb = pkg.type_registry
            if tlb
                Orocos.registry.import(tlb)
            end

            nil
        end
    end
end

