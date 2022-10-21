# frozen_string_literal: true

Types = Typelib::RegistryExport::Namespace.new

module Runkit
    class << self
        # The set of typekits whose shared libraries have been loaded in this
        # process
        attr_reader :loaded_typekit_plugins

        # List of already loaded plugins, as a set of full paths to the shared
        # library
        attr_reader :loaded_plugins
    end
    @loaded_typekit_plugins = []
    @loaded_plugins = Set.new
    @failed_plugins = Set.new

    @enforce_typekit_threading = nil
    def self.enforce_typekit_threading?
        @enforce_typekit_threading = (ENV["OROCOS_ENFORCE_TYPEKIT_THREADING"] == "1") if @enforce_typekit_threading.nil?

        @enforce_typekit_threading
    end

    @typekit_main_thread = nil
    def self.update_typekit_main_thread(thread = Thread.current)
        @typekit_main_thread = (thread if enforce_typekit_threading?)
    end

    def self.in_typekit_main_thread?
        !@typekit_main_thread || (Thread.current == @main_thread)
    end

    def self.require_in_typekit_main_thread(message = nil)
        return if in_typekit_main_thread?

        raise ThreadError,
              "#{caller(1).first} must be called from the typekit's main thread "\
              "(#{@typekit_main_thread}): #{message}"
    end

    # @deprecated use {default_loader}.type_export_namespace instead
    def self.type_export_namespace
        default_loader.type_export_namespace
    end

    # @deprecated use {default_loader}.type_export_namespace= instead
    def self.type_export_namespace=(namespace)
        default_loader.type_export_namespace = namespace
    end

    # @deprecated use {default_loader}.export_types? instead
    def self.export_types?
        default_loader.export_types?
    end

    # @deprecated use {default_loader}.export_types= instead
    def self.export_types=(value)
        default_loader.export_types = value
    end

    # Given a pkg-config file and a base name for a shared library, finds the
    # full path to the library
    def self.find_plugin_library(pkg, libname)
        libs = pkg.expand_field("Libs", pkg.raw_fields["Libs"])
        libs = libs.grep(/^-L/).map { |s| s[2..-1] }
        libs.find do |dir|
            full_path = File.join(dir, "lib#{libname}.#{Runkit.shared_library_suffix}")
            return full_path, libs if File.file?(full_path)
        end
    end

    # Generic loading of a RTT plugin
    def self.load_plugin_library(libpath) # :nodoc:
        Runkit.require_in_typekit_main_thread

        return if @loaded_plugins.include?(libpath)

        if @failed_plugins.include?(libpath)
            raise "the RTT plugin system already refused to load #{libpath}, "\
                  "not trying again"
        end

        begin
            Runkit.info "loading plugin library #{libpath}"
            raise "the RTT plugin system refused to load #{libpath}" unless Runkit.load_rtt_plugin(libpath)

            @loaded_plugins << libpath
        rescue Exception
            @failed_plugins << libpath
            raise
        end
        true
    end

    # The set of transports that should be automatically loaded. The associated
    # boolean is true if an exception should be raised if the typekit fails to
    # load, and false otherwise
    AUTOLOADED_TRANSPORTS = {
        "typelib" => true,
        "corba" => true,
        "mqueue" => false,
        "ros" => false
    }.freeze

    @lock = Mutex.new

    # Load the typekit whose name is given
    #
    # Typekits are shared libraries that include marshalling/demarshalling
    # code. It gets automatically loaded in runkit.rb whenever you start
    # processes.
    def self.load_typekit(name)
        @lock.synchronize do
            typekit = default_pkgconfig_loader.typekit_model_from_name(name)
            load_typekit_plugins(name)
        end
    end

    def self.find_typekit_pkg(name)
        Utilrb::PkgConfig.get("#{name}-typekit-#{Runkit.runkit_target}", minimal: true)
    rescue Utilrb::PkgConfig::NotFound
        raise TypekitNotFound, "the '#{name}' typekit is not available to pkgconfig"
    end

    def self.load_typekit_plugins(name, typekit_pkg = nil)
        return if @loaded_typekit_plugins.include?(name)

        Runkit.require_in_typekit_main_thread

        find_typekit_plugin_paths(name, typekit_pkg).each do |path, required|
            load_plugin_library(path)
        rescue Exception => e
            raise if required

            Runkit.warn "plugin #{p}, which is registered as an optional transport "\
                        "for the #{name} typekit, cannot be loaded"
            Runkit.log_pp(:warn, e)
        end
        @loaded_typekit_plugins << name
    end

    # Loads all typekits that are available on this system
    def self.load_all_typekits
        default_pkgconfig_loader.each_available_typekit_name do |typekit_name|
            load_typekit(typekit_name)
        end
        default_pkgconfig_loader.available_typekits.keys
    end

    def self.typekit_library_name(typekit_name, target)
        "#{typekit_name}-typekit-#{target}"
    end

    def self.transport_library_name(typekit_name, transport_name, target)
        "#{typekit_name}-transport-#{transport_name}-#{target}"
    end

    # For backward compatibility only. Use #find_typekit_plugin_paths instead
    def self.plugin_libs_for_name(name)
        find_typekit_plugin_paths(name).map(&:first)
    end

    # Returns the full path of all the plugin libraries that should be loaded
    # for the given typekit
    #
    # If given, +typekit_pkg+ is the PkgConfig file for the requested typekit
    #
    # @return [Array<(String,Boolean)>] set of found libraries. The string is
    #   the path to the library and the boolean flag indicates whether loading
    #   this library is optional (from runkit.rb's point of view), or required
    #   to use the typekit-defined types on transports
    def self.find_typekit_plugin_paths(name, typekit_pkg = nil)
        plugins = {}
        libs = []

        plugin_name = typekit_library_name(name, Runkit.runkit_target)
        plugins[plugin_name] = [typekit_pkg || find_typekit_pkg(name), true]
        if OroGen::VERSION >= "0.8"
            AUTOLOADED_TRANSPORTS.each do |transport_name, required|
                plugin_name = transport_library_name(name, transport_name, Runkit.runkit_target)
                begin
                    pkg = Utilrb::PkgConfig.get(plugin_name, minimal: true)
                    if pkg.disabled != "true"
                        plugins[plugin_name] = [pkg, required]
                    elsif required
                        raise NotFound, "the '#{name}' typekit has a #{transport_name} transport installed, but it is disabled"
                    end
                rescue Utilrb::PkgConfig::NotFound => e
                    raise NotFound, "the '#{name}' typekit has no #{transport_name} transport: could not find pkg-config package #{e.name} in #{ENV['PKG_CONFIG_PATH']}" if required
                end
            end
        end

        plugins.each_pair do |file, (pkg, required)|
            lib, lib_dirs = find_plugin_library(pkg, file)
            if !lib
                if required
                    raise NotFound, "cannot find shared library #{file} for #{name} (searched in #{lib_dirs})"
                else
                    Runkit.warn "plugin #{file} is registered through pkg-config, but the library cannot be found in #{lib_dirs}"
                end
            else
                libs << [lib, required]
            end
        end
        libs
    end

    # Looks for and loads the typekit that handles the specified type
    #
    # If +exported+ is true (the default), the type needs to be both defined and
    # exported by the typekit.
    #
    # Raises ArgumentError if this type is registered nowhere, or if +exported+
    # is true and the type is not exported.
    def self.load_typekit_for(typename, exported = true)
        typekit = default_loader.typekit_for(typename, exported)
        load_typekit(typekit.name) unless typekit.virtual?
        typekit
    end

    # Returns the type that is used to manipulate +t+ in Typelib
    #
    # For simple types, it is +t+ itself. For opaque types, it will be the
    # corresponding marshalling type. The returned value is a subclass of
    # Typelib::Type
    #
    # Raises Typelib::NotFound if this type is not registered anywhere.
    def self.typelib_type_for(t)
        if t.respond_to?(:name)
            return t unless t.contains_opaques?

            t = t.name
        end

        begin
            if typelib_type = do_typelib_type_for(t)
                return registry.get(typelib_type)
            end
        rescue ArgumentError
        end

        if registry.include?(t)
            type = registry.get(t)
            if type.contains_opaques?
                default_loader.intermediate_type_for(type)
            elsif type.null?
                # 't' is an opaque type and there are no typelib marshallers
                # to convert it to something we can manipulate, raise
                raise Typelib::NotFound, "#{t} is a null type and there are no typelib marshallers registered in RTT to convert it to a typelib-compatible type"
            else type
            end
        else
            raise Typelib::NotFound, "#{t} cannot be found in the currently loaded registries"
        end
    end

    def self.create_or_get_null_type(type_name)
        if registry.include?(type_name)
            type = registry.get type_name
            return create_or_get_null_type("/runkit#{type_name}") unless type.null?

            type
        else
            registry.create_null(type_name)
        end
    end

    # Finds the C++ type that maps to the given typelib type name
    #
    # @param [Typelib::Type,String] typelib_type
    def self.runkit_type_for(typelib_type)
        default_loader.opaque_type_for(typelib_type)
    end

    # Finds the typelib type that maps to the given runkit type name
    #
    # @param [String] runkit_type_name
    # @option options [Boolean] :fallback_to_null_type (false) if true, a new
    #   null type with the given runkit type name will be added to the registry and
    #   returned if the type cannot be found
    #
    # @raise [Runkit::TypekitTypeNotFound] if the type cannot be found and no
    #   typekit registers it
    # @return [Model<Typelib::Type>] a subclass of Typelib::Type that
    #   represents the requested type
    def self.find_type_by_runkit_type_name(runkit_type_name, fallback_to_null_type: false)
        unless registered_type?(runkit_type_name)
            begin
                load_typekit_for(runkit_type_name)
            rescue OroGen::AlreadyRegistered
            end
        end

        typelib_type_for(runkit_type_name)
    rescue Runkit::TypekitTypeNotFound, Typelib::NotFound
        # Create an opaque type as a placeholder for the unknown
        # type name
        raise unless fallback_to_null_type

        type_name = "/" + runkit_type_name.gsub(/[^\w]/, "_")
        create_or_get_null_type(type_name)
    end

    def self.find_runkit_type_name_by_type(type)
        type = type.name if type.respond_to?(:name)
        type = default_loader.resolve_type(type)
        type = default_loader.opaque_type_for(type)
        type = default_loader.resolve_interface_type(type)
        load_typekit_for(type.name) unless registered_type?(type.name)
        type.name
    end

    # Gets or update known maximum size for variable-sized containers in types
    #
    # This method can only be called after Runkit.load
    #
    # Size specification is path.to.field => size, where [] is used to get
    # elements of an array or variable-size container.
    #
    # If type is a container itself, the second form is used,
    # where the first argument is the container size and the rest
    # specifies its element sizes (and must start with [])
    #
    # For instance, with the types
    #
    #   struct A
    #   {
    #       std::vector<int> values;
    #   };
    #   struct B
    #   {
    #       std::vector<A> field;
    #   };
    #
    # Then sizes of type B would be given with
    #
    #   max_sizes('/B', 'field' => 10, 'field[].values' => 20)
    #
    # while the sizes of /std/vector</A> would be given with
    #
    #   max_sizes('/std/vector</A>', 10, '[].values' => 20)
    #
    # Finally, for /std/vector</std/vector</A>>, one would use
    #
    #   max_sizes('/std/vector</std/vector</A>>, 10, '[]' => 20, '[][].values' => 30)
    #
    #
    # @overload max_sizes => Hash
    #   Gets all known maximum sizes
    #
    #   @return [Hash<String,Hash>] a mapping from type names to the size
    #     specification for this type. See above for the hash format
    #
    # @overload max_sizes('/namespace/Compound', 'to[].field' => 10, 'other' => 20)
    #   Updates the known maximum sizes for the given type. When updating, any
    #   new field value will erase old ones, unless a block is given in which
    #   case the block is given the old and new values and should return the
    #   value that should be stored
    #
    def self.max_sizes(typename = nil, *sizes, &block)
        raise ArgumentError, "cannot call Runkit.max_sizes before Runkit.load" unless @max_sizes

        return @max_sizes if !typename && sizes.empty?

        type = default_loader.resolve_type(typename)
        type = default_loader.intermediate_type_for(type)
        sizes = OroGen::Spec::Port.validate_max_sizes_spec(type, sizes)
        @max_sizes[type.name].merge!(sizes, &block)
    end

    # Returns the max size specification for the given type
    #
    # @param [String,Typelib::Type] the type or type name
    # @return [Hash] the maximum size specification, see {Runkit.max_sizes} for
    #   details
    def self.max_sizes_for(type)
        type = type.name if type.respond_to?(:name)
        @max_sizes.fetch(type, {})
    end
    @max_sizes = {}

    def self.normalize_typename(typename)
        load_typekit_for(typename)
        registry.get(typename).name
    end
end
