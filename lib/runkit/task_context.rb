# frozen_string_literal: true

module Runkit
    # A proxy for a remote task context. The communication between Ruby and the
    # RTT component is done through the CORBA transport.
    #
    # See README.txt for information on how you can manipulate a task context
    # through this class.
    #
    # The available information about this task context can be displayed using
    # Ruby's pretty print library:
    #
    #   require 'pp'
    #   pp task_object
    #
    class TaskContext < TaskContextBase
        # @api private
        #
        # Automated wrapper to handle CORBA exceptions coming from the C
        # extension
        def self.corba_wrap(name, *args) # :nodoc:
            class_eval <<~DEF_END, __FILE__, __LINE__ + 1
                def #{name}(#{args.join('. ')})
                    CORBA.refine_exceptions(self) { do_#{name}(#{args.join(', ')}) }
                end
            DEF_END
        end

        # Create a TaskContext instance representing the remote task context
        # with the given IOR
        #
        # @param [String] ior The IOR of the remote task.
        # @param [String] name the task name, if not known
        # @option options [String] :name Overwrites the real name of remote task
        def initialize(
            ior,
            name:, loader: nil,
            model: self.class.empty_orogen_model(name, loader: loader)
        )
            # Note: TaskContext.new is implemented in C++
            super(name, model: model)
            @ior = ior
        end

        def ping
            read_toplevel_state
            nil
        end

        # Specialization of the OutputReader to read the task'ss state port. Its
        # read method will return a state in the form of a symbol. For instance, the
        # RUNTIME_ERROR state is returned as :RUNTIME_ERROR
        #
        # StateReader objects are created by TaskContext#state_reader
        module StateReader
            def read(sample = nil)
                return unless (value = super(sample))

                port.task.map_state_value_to_symbol(value)
            end

            def read_new(sample = nil)
                return unless (value = super(sample))

                port.task.map_state_value_to_symbol(value)
            end

            def read_with_result(sample = nil, copy_old_data = false)
                result, value = super
                if value
                    symbol = port.task.map_state_value_to_symbol(value)
                    [result, symbol]
                else
                    result
                end
            end
        end

        # Maps a state value (as received from the state port) into the
        # corresponding symbol
        #
        # @param [Integer] value
        # @return [Symbol]
        def map_state_value_to_symbol(value)
            @state_symbols.fetch(value)
        end

        # Returns a StateReader object that allows to flexibly monitor the
        # task's state
        def state_reader(distance: PortBase::D_UNKNOWN, **policy)
            policy = Port.prepare_policy(
                **{ init: true, type: :buffer, size: 10 }.merge(policy)
            )

            reader = port("state").reader(distance: distance, **policy)
            reader.extend StateReader
            reader
        end

        # Returns the PID of the thread this task runs on
        #
        # This is available only on oroGen task, for which oroGen adds an
        # orogen_getPID operation that returns this information
        def tid
            @tid ||= operation("__orogen_getTID").callop
        end

        # Reads the state announced by the task's getState() operation
        def read_toplevel_state
            value = CORBA.refine_exceptions(self) { do_state }
            @state_symbols[value]
        end

        def rtt_state
            warn "TaskContext#rtt_state is deprecated, use read_toplevel_state instead"
            read_toplevel_state
        end

        # Loads the configuration for the TaskContext from a file,
        # into the main configuration manager and applies it to the TaskContext
        #
        # See also #apply_conf and #Runkit.load_config_dir
        def apply_conf_file(file, section_names = [], override = false)
            Runkit.conf.load_file(file, model.name)
            apply_conf(section_names, override)
        end

        def to_s
            "#<TaskContext: #{self.class.name}/#{name}>"
        end

        # Applies the TaskContext configuration stored by the main
        # configuration manager to the TaskContext
        #
        # See also #load_conf and #Runkit.load_config_dir
        def apply_conf(section_names = [], override = false)
            Runkit.conf.apply(self, section_names, override)
        end

        # Saves the current configuration into a file
        def save_conf(file, section_names = nil)
            Runkit.conf.save(self, file, section_names)
        end

        # @!method configure
        #   Configures the component, i.e. do the transition from
        #   STATE_PRE_OPERATIONAL into STATE_STOPPED.
        #
        #   Raises StateTransitionFailed if the component was not in
        #   STATE_PRE_OPERATIONAL state before the call, or if the component
        #   refused to do the transition (configureHook() returned false)
        corba_wrap :configure

        # @!method start
        #   Starts the component, i.e. do the transition from STATE_STOPPED into
        #   STATE_RUNNING.
        #
        #   Raises StateTransitionFailed if the component was not in STATE_STOPPED
        #   state before the call, or if the component refused to do the
        #   transition (startHook() returned false)
        corba_wrap :start

        # @!method reset_exception
        #   Recover from the exception state. It does the transition from
        #   STATE_EXCEPTION to either STATE_STOPPED if the component does not
        #   need any configuration or STATE_PRE_OPERATIONAL otherwise
        #
        #   Raises StateTransitionFailed if the component was not in a proper
        #   state before the call.
        corba_wrap :reset_exception

        # @!method stop
        #   Stops the component, i.e. do the transition from STATE_RUNNING into
        #   STATE_STOPPED.
        #
        #   Raises StateTransitionFailed if the component was not in STATE_RUNNING
        #   state before the call. The component cannot refuse to perform the
        #   transition (but can take an arbitrarily long time to do it).
        corba_wrap :stop

        # @!method cleanup
        #   Cleans the component, i.e. do the transition from STATE_STOPPED into
        #   STATE_PRE_OPERATIONAL.
        #
        #   Raises StateTransitionFailed if the component was not in STATE_STOPPED
        #   state before the call. The component cannot refuse to perform the
        #   transition (but can take an arbitrarily long time to do it).
        corba_wrap :cleanup

        # Returns true if this task context has a command with the given name
        def operation?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_operation?(name)
            rescue Runkit::NotFound
                false
            end
        end

        # Returns true if this task context has a port with the given name
        def port?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_port?(name)
            rescue Runkit::NotFound
                false
            end
        end

        # @deprecated use {#port?} instead
        def has_port?(name) # rubocop:disable Naming/PredicateName
            warn "TaskContext#has_port? is deprecated, use port? instead"
            port?(name)
        end

        # Returns the array of the names of available operations on this task
        # context
        def operation_names
            CORBA.refine_exceptions(self) do
                do_operation_names.each do |str|
                    str.force_encoding("ASCII") if str.respond_to?(:force_encoding)
                end
            end
        end

        # Returns the array of the names of available properties on this task
        # context
        def property_names
            CORBA.refine_exceptions(self) do
                do_property_names.each do |str|
                    str.force_encoding("ASCII") if str.respond_to?(:force_encoding)
                end
            end
        end

        # Returns the array of the names of available attributes on this task
        # context
        def attribute_names
            CORBA.refine_exceptions(self) do
                do_attribute_names
            end
        end

        # @api private
        #
        # Access the remote component API to read information about the given attribute
        def read_attribute_info(name)
            CORBA.refine_exceptions(self) do
                do_attribute_type_name(name)
            rescue ArgumentError
                raise InterfaceObjectNotFound.new(self, name),
                      "task #{self.name} does not have an attribute named #{name}"
            end
        end

        # Get an accessor for the given attribute
        #
        # Attributes can also be read and written by calling directly the
        # relevant method on the task context:
        #
        #   task.attribute("myProperty").read
        #   task.attribute("myProperty").write(value)
        #
        # is equivalent to
        #
        #   task.myProperty
        #   task.myProperty = value
        #
        # @return [Attribute]
        # @raises [InterfaceObjectNotFound]
        def attribute(name)
            unless (attribute_model = model.find_attribute(name))
                type_name = read_attribute_info(name)
                attribute_model = self.class.create_attribute_model(
                    self, name, type_name, loader: model.loader
                )
            end

            Attribute.new(self, name, attribute_model)
        end

        # @api private
        #
        # Access the remote interface to determine information about the given property
        def read_property_info(name)
            CORBA.refine_exceptions(self) do
                do_property_type_name(name)
            rescue ArgumentError
                raise Runkit::InterfaceObjectNotFound.new(self, name),
                      "task #{self.name} does not have a property named #{name}"
            end
        end

        # Get an accessor for the given property
        #
        # Properties can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.property("my_property").read
        #   task.property("my_property").write(value)
        #
        # is equivalent to
        #
        #   task.my_property
        #   task.my_property = value
        #
        # @return [Property]
        # @raises [InterfaceObjectNotFound]
        def property(name)
            unless (property_model = model.find_property(name))
                type_name = read_property_info(name)
                property_model = self.class.create_property_model(
                    self, name, type_name, loader: model.loader
                )
            end

            Property.new(self, name, property_model)
        end

        # @api private
        #
        # Resolve a Port object for the given port name
        def raw_port(name)
            unless (port_model = model.find_port(name))
                is_output, type_name = read_port_info(name)
                port_model = self.class.create_port_model(
                    self, is_output, name, type_name, loader: model.loader
                )
            end

            port_class =
                if port_model.input?
                    InputPort
                else
                    OutputPort
                end

            port_class.new(self, name, port_model)
        rescue Runkit::NotFound
            raise Runkit::InterfaceObjectNotFound.new(self, name),
                  "task #{self.name} does not have a port named #{name}"
        end

        # Returns an object that represents the given port on the remote task
        # context. The returned object is either an InputPort or an OutputPort
        #
        # Raises NotFound if no such port exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.port("myPort")
        #
        # is equivalent to
        #
        #   task.myPort
        #
        def port(name)
            CORBA.refine_exceptions(self) do
                raw_port(name.to_str)
            end
        end

        # Returns the names of all the ports defined on this task context
        def port_names
            CORBA.refine_exceptions(self) do
                do_port_names.each do |str|
                    str.force_encoding("ASCII") if str.respond_to?(:force_encoding)
                end
            end
        end

        # Returns an Operation object that represents the given method on the
        # remote component.
        #
        # Raises NotFound if no such operation exists.
        def operation(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                return_types = operation_return_types(name)
                arguments = operation_argument_types(name)
                Operation.new(self, name, return_types, arguments)
            end
        rescue Runkit::NotFound => e
            raise Runkit::InterfaceObjectNotFound.new(self, name),
                  "task #{self.name} does not have an operation named #{name}",
                  e.backtrace
        end

        # Calls the required operation with the given argument
        #
        # This is a shortcut for operation(name).calldop(*arguments)
        def callop(name, *args)
            operation(name).callop(*args)
        end

        # Sends the required operation with the given argument
        #
        # This is a shortcut for operation(name).sendop(*arguments)
        def sendop(name, *args)
            operation(name).sendop(*args)
        end

        # Create a null model for a dynamically discovered port
        def self.create_port_model(task, is_output, name, type, loader:)
            port_class =
                if is_output
                    OroGen::Spec::OutputPort
                else
                    OroGen::Spec::InputPort
                end

            if type.respond_to?(:to_str)
                type = loader.resolve_type(type, define_dummy_type: true)
            end

            port_class.new(task.model, name, type)
        end

        # Create a null model for a dynamically discovered property
        def self.create_property_model(task, name, type, loader:)
            if type.respond_to?(:to_str)
                type = loader.resolve_type(type, define_dummy_type: true)
            end
            OroGen::Spec::Property.new(task.model, name, type, nil)
        end

        # Create a null model for a dynamically discovered attribute
        def self.create_attribute_model(task, name, type, loader:)
            if type.respond_to?(:to_str)
                type = loader.resolve_type(type, define_dummy_type: true)
            end
            OroGen::Spec::Attribute.new(task.model, name, type, nil)
        end
    end
end
