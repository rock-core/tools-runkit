module Types
end

module Orocos
    class << self
        # The set of typekits whose shared libraries have been loaded in this
        # process
        attr_reader :loaded_typekit_plugins

        # The set of typekits whose registries have been merged in the master registry
        attr_reader :loaded_typekit_registries

        # If true, the types that get loaded are exported in the Ruby namespace.
        # For instance, a /base/Pose type included in Orocos.registry will be
        # available as Base::Pose
        #
        # The export can be done in a sub-namespace by setting
        # Orocos.type_export_namespace
        attr_predicate :export_types?, true

        # The namespace in which the types should be exported if
        # Orocos.export_types? is true. It defaults to Types
        attr_accessor :type_export_namespace
    end
    @loaded_typekit_plugins = []
    @loaded_typekit_registries = []
    @loaded_plugins = Set.new
    @export_types = true
    @type_export_namespace = Types

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

        if !Orocos.load_rtt_plugin(libpath)
            raise "the RTT plugin system refused to load #{libpath}"
        end
        @loaded_plugins << libpath
        true
    end

    REQUIRED_TRANSPORTS = %w{typelib corba}
    OPTIONAL_TRANSPORTS = %w{mqueue}

    # Load the typekit whose name is given
    #
    # Typekits are shared libraries that include marshalling/demarshalling
    # code. It gets automatically loaded in orocos.rb whenever you start
    # processes.
    def self.load_typekit(name)
        typekit_pkg = find_typekit_pkg(name)
        load_typekit_plugins(name, typekit_pkg)
        load_typekit_registry(name, typekit_pkg)
    end

    def self.find_typekit_pkg(name)
        begin
            Utilrb::PkgConfig.new("#{name}-typekit-#{Orocos.orocos_target}")
        rescue Utilrb::PkgConfig::NotFound
            raise NotFound, "the '#{name}' typekit is not available to pkgconfig"
        end
    end

    def self.load_typekit_plugins(name, typekit_pkg = nil)
        if @loaded_typekit_plugins.include?(name)
            return
        end

        typekit_pkg ||= find_typekit_pkg(name)

        load_plugin_library(typekit_pkg, name, "lib#{name}-typekit-#{Orocos.orocos_target}.so")

        if Orocos::Generation::VERSION >= "0.8"
            REQUIRED_TRANSPORTS.each do |transport_name|
                transport_pkg =
                    begin
                        Utilrb::PkgConfig.new("#{name}-transport-#{transport_name}-#{Orocos.orocos_target}")
                    rescue Utilrb::PkgConfig::NotFound
                        raise NotFound, "the '#{name}' typekit has no #{transport_name} transport"
                    end
                load_plugin_library(transport_pkg, name, "lib#{name}-transport-#{transport_name}-#{Orocos.orocos_target}.so")
            end

            OPTIONAL_TRANSPORTS.each do |transport_name|
                begin
                    transport_pkg = Utilrb::PkgConfig.new("#{name}-transport-#{transport_name}-#{Orocos.orocos_target}")
                    load_plugin_library(transport_pkg, name, "lib#{name}-transport-#{transport_name}-#{Orocos.orocos_target}.so")
                rescue Exception
                end
            end
        end

        @loaded_typekit_plugins << name
    end
    
    def self.load_typekit_registry(name, typekit_pkg = nil)
        if @loaded_typekit_registries.include?(name)
            return
        end
        typekit_pkg ||= find_typekit_pkg(name)

        # Now, if this is an orogen typekit, then load the corresponding
        # data types. orogen defines a type_registry field in the pkg-config
        # file for that purpose.
        tlb = typekit_pkg.type_registry
        if tlb # this is an orogen typekit
            begin
                Orocos.master_project.using_project(name)
                Orocos.registry.import(tlb)
            rescue RuntimeError => e
                raise e, "failed to load typekit #{name}: #{e.message}", e.backtrace
            end

            if Orocos.export_types?
                Orocos.registry.export_to_ruby(Orocos.type_export_namespace) do |type_name, base_type, mod, basename, exported_type|
                    if type_name =~ /orogen_typekits/ # just ignore those
                    elsif base_type <= Typelib::NumericType # using numeric is transparent in Typelib/Ruby
                    elsif base_type.contains_opaques? # register the intermediate instead
                        Orocos.master_project.intermediate_type_for(base_type)
                    elsif Orocos.master_project.m_type?(base_type) # just ignore, they are registered as the opaque
                    else exported_type
                    end
                end
            end
        end

        @loaded_typekit_registries << name
    end

    # Loads all typekits that are available on this system
    def self.load_all_typekits
        Orocos.available_projects.each_key do |project_name|
            if master_project.has_typekit?(project_name)
                load_typekit(project_name)
            end
        end
    end
end

