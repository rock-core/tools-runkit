module Orocos
    class << self
        # The set of typekits that are loaded in this Ruby instance, as an
        # array typekit names.
        #
        # See also load_typekit and loaded_typekit?
        attr_reader :loaded_typekits

        # True if the typekit whose name is given in argument is loaded
        #
        # See also load_typekit and loaded_typekits
        def loaded_typekit?(name)
            loaded_typekits.include?(name)
        end
    end
    @loaded_typekits = []
    @loaded_plugins = Set.new

    # Generic loading of a RTT plugin
    def self.load_plugin_library(pkg, name, libname) # :nodoc:
        libpath = pkg.library_dirs.find do |dir|
            full_path = File.join(dir, libname)
            break(full_path) if File.file?(full_path)
        end

        if !libpath
            raise NotFound, "cannot find typekit shared library for #{name} (searched for #{libname} in #{pkg.libdirs.split(" ").join(", ")})"
        end

        return if @loaded_plugins.include?(libpath)

        Orocos.load_rtt_plugin(libpath)
        @loaded_plugins << libpath
        true
    end

    # Load the typekit whose name is given
    #
    # Typekits are shared libraries that include marshalling/demarshalling
    # code. It gets automatically loaded in orocos.rb whenever you start
    # processes.
    def self.load_typekit(name, transports = ['corba', 'typelib'])
        return if loaded_typekit?(name)

        typekit_pkg =
            begin
                Utilrb::PkgConfig.new("#{name}-typekit-#{Orocos.orocos_target}")
            rescue Utilrb::PkgConfig::NotFound
                raise NotFound, "the '#{name}' typekit is not available to pkgconfig"
            end
        load_plugin_library(typekit_pkg, name, "lib#{name}-typekit-#{Orocos.orocos_target}.so")

        if Orocos::Generation::VERSION >= "0.8"
            transports.each do |transport_name|
                transport_pkg =
                    begin
                        Utilrb::PkgConfig.new("#{name}-transport-#{transport_name}-#{Orocos.orocos_target}")
                    rescue Utilrb::PkgConfig::NotFound
                        raise NotFound, "the '#{name}' typekit has no #{transport_name} transport"
                    end
                load_plugin_library(transport_pkg, name, "lib#{name}-transport-#{transport_name}-#{Orocos.orocos_target}.so")
            end
        end

        @loaded_typekits << name

        # Now, if this is an orogen typekit, then load the corresponding
        # data types. orogen defines a type_registry field in the pkg-config
        # file for that purpose.
        tlb = typekit_pkg.type_registry
        if tlb
            Orocos.registry.import(tlb)
        end

        nil
    end
end

