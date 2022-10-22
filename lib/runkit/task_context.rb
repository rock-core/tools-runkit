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
    class TaskContext
        # @api private
        #
        # Automated wrapper to handle CORBA exceptions coming from the C
        # extension
        def self.corba_wrap(m, *args) # :nodoc:
            class_eval <<~DEF_END, __FILE__, __LINE__ + 1
                def #{m}(#{args.join('. ')})
                    CORBA.refine_exceptions(self) { do_#{m}(#{args.join(', ')}) }
                end
            DEF_END
        end

        # Create a TaskContext instance representing the remote task context
        # with the given IOR
        #
        # @param [String] ior The IOR of the remote task.
        # @param [String] name the task name, if not known
        # @option options [String] :name Overwrites the real name of remote task
        def initialize(ior, name:, model:)
            # Note: TaskContext.new is implemented in C++
            super(name, model: model)
            @ior = ior
            @ports = {}
        end

        def ping
            rtt_state
            nil
        end

        # Specialization of the OutputReader to read the task'ss state port. Its
        # read method will return a state in the form of a symbol. For instance, the
        # RUNTIME_ERROR state is returned as :RUNTIME_ERROR
        #
        # StateReader objects are created by TaskContext#state_reader
        module StateReader
            attr_accessor :state_symbols

            def read(sample = nil)
                if value = super(sample)
                    @state_symbols[value]
                end
            end

            def read_new(sample = nil)
                if value = super(sample)
                    @state_symbols[value]
                end
            end

            def read_with_result(sample = nil, copy_old_data = false)
                result, value = super
                if value
                    [result, @state_symbols[value]]
                else
                    result
                end
            end
        end

        # Returns a StateReader object that allows to flexibly monitor the
        # task's state
        def state_reader(**policy)
            policy = Port.prepare_policy(
                **{ init: true, type: :buffer, size: 10 }.merge(policy)
            )

            reader = port("state").reader(**policy)
            reader.extend StateReader
            reader.state_symbols = @state_symbols
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
        def rtt_state
            value = CORBA.refine_exceptions(self) { do_state }
            @state_symbols[value]
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
            type_name = CORBA.refine_exceptions(self) do
                do_attribute_type_name(name)
            rescue ArgumentError => e
                raise InterfaceObjectNotFound.new(self, name),
                      "task #{self.name} does not have an attribute named #{name}"
            end

            Attribute.new(self, name, type_name)
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
            type_name = CORBA.refine_exceptions(self) do
                do_property_type_name(name)
            rescue ArgumentError => e
                raise Runkit::InterfaceObjectNotFound.new(self, name),
                      "task #{self.name} does not have a property named #{name}"
            end

            Property.new(self, name, type_name)
        end

        # @api private
        #
        # Resolve a Port object for the given port name
        def raw_port(name)
            port_model = model.find_port(name)
            do_port(name, port_model)
        rescue Runkit::NotFound => e
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
        def port(name, verify = true)
            name = name.to_str
            CORBA.refine_exceptions(self) do
                if @ports[name]
                    if !verify || port?(name) # Check that this port is still valid
                        @ports[name]
                    else
                        @ports.delete(name)
                        raise NotFound, "no port named '#{name}' on task '#{self.name}'"
                    end
                else
                    @ports[name] = raw_port(name)
                end
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
            raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have an operation named #{name}", e.backtrace
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
    end
end
