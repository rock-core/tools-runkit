# frozen_string_literal: true

module Runkit
    module RubyTasks
        # A TaskContext that lives inside this Ruby process
        #
        # For now, it has very limited functionality: mainly managing ports
        class TaskContext < Runkit::TaskContext
            # Internal handler used to represent the local RTT::TaskContext object
            #
            # It is created from Ruby as it handles the RTT::TaskContext pointer
            class LocalTaskContext
                # [Runkit::TaskContext] the remote task
                attr_reader :remote_task
                # [String] the task name
                attr_reader :name

                def initialize(name)
                    @name = name
                end
            end

            # Creates a new local task context that fits the given oroGen model
            #
            # @return [TaskContext]
            def self.from_orogen_model(name, orogen_model, register_on_name_server: true)
                new(name, model: orogen_model,
                          register_on_name_server: register_on_name_server)
            end

            def self.empty_orogen_model(name, loader: nil)
                project = OroGen::Spec::Project.new(loader || Runkit.default_loader)
                project.task_context name do
                    extended_state_support
                end
            end

            # Creates a new ruby task context with the given name
            #
            # @param [String] name the task name
            # @return [TaskContext]
            def self.new(
                name,
                loader: nil, model: empty_orogen_model(name, loader: loader),
                register_on_name_server: true
            )
                local_task = LocalTaskContext.new(
                    name, register_on_name_server: register_on_name_server
                )
                local_task.model_name = model.name if model&.name

                remote_task = super(local_task.ior, name: name, model: model)
                local_task.instance_variable_set :@remote_task, remote_task
                remote_task.instance_variable_set :@local_task, local_task
                remote_task.setup_from_orogen_model(model)
                remote_task
            rescue StandardError
                local_task&.dispose
                raise
            end

            def initialize(ior, name: self.name, **other_options)
                @local_ports = {}
                @local_properties = {}
                @local_attributes = {}
                super(ior, name: name, **other_options)
            end

            # Create a new input port on this task context
            #
            # @param [String] name the port name. It must be unique among all port
            #   types
            # @param [String] runkit_type_name the name of the port's type, as
            #   recognized by Runkit. In most cases, it is the same than the
            #   typelib type name
            # @option options [Boolean] :permanent if true (the default), the port
            #   will be stored permanently on the task. Otherwise, it will be
            #   removed as soon as the port object gets garbage collected by Ruby
            # @option options [Class] :class the class that should be used to
            #   represent the port on the Ruby side. Do not change unless you know
            #   what you are doing
            def create_input_port(name, runkit_type_name, **options)
                klass = options.delete(:class) || LocalInputPort
                create_port(false, klass, name, runkit_type_name, **options)
            end

            # Create a new output port on this task context
            #
            # @param [String] name the port name. It must be unique among all port
            #   types
            # @param [String] runkit_type_name the name of the port's type, as
            #   recognized by Runkit. In most cases, it is the same than the
            #   typelib type name
            # @option options [Boolean] :permanent if true (the default), the port
            #   will be stored permanently on the task. Otherwise, it will be
            #   removed as soon as the port object gets garbage collected by Ruby
            # @option options [Class] :class the class that should be used to
            #   represent the port on the Ruby side. Do not change unless you know
            #   what you are doing
            def create_output_port(name, type, **options)
                klass = options.delete(:class) || LocalOutputPort
                create_port(true, klass, name, type, **options)
            end

            # Remove the given port from this task's interface
            #
            # @param [LocalInputPort,LocalOutputPort] port the port to be removed
            # @return [void]
            def remove_port(port)
                @local_ports.delete(port.name)
                port.disconnect_all # don't wait for the port to be garbage collected by Ruby
                @local_task.do_remove_port(port.name)
            end

            # Deregisters this task context.
            #
            # This is done automatically when the object is garbage collected.
            # However, it is sometimes better to do this explicitely, for instance
            # to avoid the name clash warning.
            def dispose
                @local_task.dispose
            end

            # Transition to an exception state
            def exception
                @local_task.exception
            end

            # Creates a new attribute on this task context
            #
            # @param [String] name the attribute name
            # @param [Model<Typelib::Type>,String] type the type or type name
            # @option options [Boolean] :init (true) if true, the new attribute will
            #   be initialized with a fresh sample. Otherwise, it is left alone. This
            #   is mostly to avoid crashes / misbehaviours in case smart pointers are
            #   used
            # @return [Property] the attribute object
            def create_attribute(name, type, model: nil, init: true)
                model ||= TaskContext.create_attribute_model(
                    self, name, type, loader: self.model.loader
                )
                local_attribute = @local_task.do_create_attribute(
                    Attribute, name, model.type.name, model
                )
                @local_attributes[local_attribute.name] = local_attribute
                local_attribute.write(local_attribute.new_sample) if init
                local_attribute
            end

            # Creates a new property on this task context
            #
            # @param [String] name the property name
            # @param [Model<Typelib::Type>,String] type the type or type name
            # @option options [Boolean] :init (true) if true, the new property will
            #   be initialized with a fresh sample. Otherwise, it is left alone. This
            #   is mostly to avoid crashes / misbehaviours in case smart pointers are
            #   used
            # @return [Property] the property object
            def create_property(name, type, model: nil, init: true)
                model ||= TaskContext.create_property_model(
                    self, name, type, loader: self.model.loader
                )
                local_property = @local_task.do_create_property(
                    Property, name, model.type.name, model
                )
                @local_properties[local_property.name] = local_property
                local_property.write(local_property.new_sample) if init
                local_property
            end

            # Sets up the interface of this task context so that it matches the
            # given oroGen model
            #
            # @param [OroGen::Spec::TaskContext] orogen_model the oroGen model
            # @return [void]
            def setup_from_orogen_model(orogen_model)
                existing_properties, new_properties =
                    orogen_model.each_property.partition { |p| property?(p.name) }
                existing_properties.each do |p|
                    if property(p.name).runkit_type_name != p.runkit_type_name
                        raise IncompatibleInterface,
                              "cannot adapt the interface of #{self} to match the model "\
                              "in #{orogen_model}: #{self} already has a property "\
                              "called #{p.name}, but with a different type"
                    end
                end

                new_inputs = []
                remove_inputs = []
                orogen_model.each_input_port do |p|
                    if port?(p.name)
                        existing_port = port(p.name)
                        if existing_port.runkit_type_name != p.runkit_type_name
                            remove_inputs << existing_port
                            new_inputs << p
                        end
                    else new_inputs << p
                    end
                end

                new_outputs = []
                remove_outputs = []
                orogen_model.each_output_port do |p|
                    if port?(p.name)
                        existing_port = port(p.name)
                        if existing_port.runkit_type_name != p.type.name
                            remove_outputs << existing_port
                            new_outputs << p
                        end
                    else new_outputs << p
                    end
                end

                remove_inputs.each { |p| remove_port p }
                remove_outputs.each { |p| remove_port p }
                new_properties.each { |p| create_property(p.name, p.type, model: p) }
                new_inputs.each { |p| create_input_port(p.name, p.type, model: p) }
                new_outputs.each { |p| create_output_port(p.name, p.type, model: p) }
                @model = orogen_model
                nil
            end

            def port?(name)
                @local_ports.key?(name) || super
            end

            def raw_port(name)
                @local_ports[name] || super
            end

            private

            # Helper method for create_input_port and create_output_port
            def create_port(is_output, klass, name, type, model: nil, permanent: true)
                model ||= TaskContext.create_port_model(
                    self, is_output, name, type, loader: self.model.loader
                )
                local_port = @local_task.do_create_port(
                    is_output, klass, name, model.type.name, model
                )
                @local_ports[local_port.name] = local_port if permanent
                local_port
            end

            def type_name_from_type_arg(type)
                if type.respond_to?(:name)
                    type.name
                else
                    type
                end
            end
        end
    end
end
