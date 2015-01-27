module Orocos
    class DefaultLoader < OroGen::Loaders::Aggregate
        # @return [Boolean] whether the types that get registered on {registry}
        #   should be exported as Ruby constants
        attr_predicate :export_types?

        # The namespace in which the types should be exported if
        # {export_types?} returns true. It defaults to Types
        #
        # @return [Module]
        attr_reader :type_export_namespace

        def initialize
            @export_types = true
            @type_export_namespace = ::Types
            # We need recursive access lock
            @load_access_lock = Monitor.new
            super
        end

        def export_types=(flag)
            if !export_types? && flag
                export_registry_to_ruby
                @export_types = true
            elsif export_types? && !flag
                clear_export_namespace
                @export_types = false
            end
        end

        def clear
            if export_types? && registry
                clear_export_namespace
            end
            super
            OroGen::Loaders::RTT.setup_loader(self)
        end

        def register_project_model(project)
            super
            project.self_tasks.each_value do |task|
                task.each_extension do |ext|
                    Orocos.load_extension_runtime_library(ext.name)
                end
            end
        end

        def register_typekit_model(typekit)
            super
            if export_types?
                export_registry_to_ruby
            end
        end

        def clear_export_namespace
            registry.clear_exports(type_export_namespace)
        end

        def export_registry_to_ruby
            registry.export_to_ruby(type_export_namespace) do |type_name, base_type, mod, basename, exported_type|
                if type_name =~ /orogen_typekits/ # just ignore those
                elsif base_type <= Typelib::NumericType # using numeric is transparent in Typelib/Ruby
                elsif base_type.contains_opaques? # register the intermediate instead
                    intermediate_type_for(base_type)
                elsif m_type?(base_type) # just ignore, they are registered as the opaque
                else exported_type
                end
            end
        end

        def task_model_from_name(name)
            @load_access_lock.synchronize do
                super
            end
        end
    end
end
    

