# frozen_string_literal: true

require "utilrb/object/attribute"

module Runkit
    # Exception raised when an operation requires the CORBA layer to be
    # initialized by Runkit.initialize has not yet been called
    class NotInitialized < RuntimeError; end

    class TaskContextAttribute < AttributeBase
        # Returns the operation that has to be called if this is an
        # dynamic propery. Nil otherwise
        attr_reader :dynamic_operation

        def dynamic?
            !!@dynamic_operation
        end

        def initialize(task, name, runkit_type_name)
            super
            if task.operation?(opname = "__orogen_set#{name.capitalize}")
                @dynamic_operation = task.operation(opname)
            end
        end

        def do_write_dynamic(value)
            raise PropertyChangeRejected, "the change of property #{name} was rejected by the remote task" unless @dynamic_operation.callop(value)
        end
    end

    class Property < TaskContextAttribute
        def log_metadata
            super.merge("rock_stream_type" => "property")
        end

        def do_write(type_name, value, direct: false)
            if !direct && dynamic?
                do_write_dynamic(value)
            else
                task.do_property_write(name, type_name, value)
            end
        end

        def do_read(type_name, value)
            task.do_property_read(name, type_name, value)
        end
    end

    class Attribute < TaskContextAttribute
        def log_metadata
            super.merge("rock_stream_type" => "attribute")
        end

        def do_write(type_name, value, direct: false)
            if !direct && dynamic?
                do_write_dynamic(value)
            else
                task.do_attribute_write(name, type_name, value)
            end
        end

        def do_read(type_name, value)
            task.do_attribute_read(name, type_name, value)
        end
    end

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
        # Automated wrapper to handle CORBA exceptions coming from the C
        # extension
        def self.corba_wrap(m, *args) # :nodoc:
            class_eval <<-EOD
            def #{m}(#{args.join('. ')})
                CORBA.refine_exceptions(self) { do_#{m}(#{args.join(', ')}) }
            end
            EOD
        end

        def self.state_transition_call(m, expected_state, target_state)
            class_eval <<-EOD, __FILE__, (__LINE__ + 1)
            def #{m}(wait_for_completion = true, polling = 0.05)
                if wait_for_completion
                    current_state = peek_current_state
                end
                CORBA.refine_exceptions(self) do
                    begin
                        do_#{m}
                    rescue Runkit::StateTransitionFailed => e
                        current_state = rtt_state
                        reason =
                            if current_state == :EXCEPTION
                                ". The task is in an exception state. You must call #reset_exception before trying again"
                            elsif current_state == :PRE_OPERATIONAL && '#{m}' == 'start'
                                ". The Task must be configured before it could started. Did you forgot to call configure on the task?"
                            elsif current_state != :#{expected_state}
                                ". Tasks must be in #{expected_state} state before calling #{m}, but was in \#{current_state}"
                            end

                        raise e, "\#{e.message} the '\#{self.name}' task\#{ " of type \#{self.model.name}" if self.model}\#{reason}", e.backtrace
                    end
                end
                if wait_for_completion
                    while current_state == peek_current_state#{" && current_state != :#{target_state}" if target_state}
                        sleep polling
                    end
                end
            end
            EOD
        end

        # The logger task that should be used to log data that concerns this
        # task
        #
        # @return [#log]
        attr_accessor :logger

        # A new TaskContext instance representing the
        # remote task context with the given IOR
        #
        # If a remote task is only known by its name use {Runkit.name_service}
        # to create an handle to the remote task.
        #
        # @param [String] ior The IOR of the remote task.
        # @param [Hash] options The options.
        # @option options [String] :name Overwrites the real name of remote task
        # @option options [Runkit::Process] :process The process supporting the task
        # @option options [String] :namespace The namespace of the task
        def initialize(ior, name: do_real_name, model: nil, **other_options)
            super(name, model: model, **other_options)
            @ior = ior

            self.logger = process.default_logger if process && (process.default_logger_name != name)
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

        # Reads all state transitions that have been announced by the task and
        # pushes them to @state_queue
        #
        # The following call to #state will first look at @state_queue before
        # accessing the task context
        def peek_state
            if model&.extended_state_support?
                if !@state_reader || !@state_reader.connected?
                    @state_reader = state_reader
                    @state_queue << rtt_state
                end

                while new_state = @state_reader.read_new
                    @state_queue << new_state
                end
            else
                super
            end
            @state_queue
        end

        # Returns the PID of the thread this task runs on
        #
        # This is available only on oroGen task, for which oroGen adds an
        # orogen_getPID operation that returns this information
        def tid
            unless @tid
                if operation?("__orogen_getTID")
                    @tid = operation("__orogen_getTID").callop
                else
                    raise ArgumentError, "#tid is available only on oroGen tasks, not #{self}"
                end
            end
            @tid
        end

        # Reads the state announced by the task's getState() operation
        def rtt_state
            value = CORBA.refine_exceptions(self) { do_state }
            @state_symbols[value]
        end

        # Connects all ports of the task with the logger of the deployment
        # @param [Hash] options option hash to exclude specific ports
        # @option options [String,Array<String>] :exclude_ports The name of the excluded ports
        # @return [Set<String,String>] Sets of task and port names
        #
        # @example logging all ports beside a port called frame
        # task.log_all_ports(:exclude_ports => "frame")
        def log_all_ports(options = {})
            # Right now, the only allowed option is :exclude_ports
            options, logger_options = Kernel.filter_options options, exclude_ports: nil
            exclude_ports = Array(options[:exclude_ports])

            logger_options[:tasks] = Regexp.new(basename)
            ports = Runkit.log_all_process_ports(process, logger_options) do |port|
                !exclude_ports.include? port.name
            end
            raise "#{name}: no ports were selected for logging" if ports.empty?

            ports
        end

        def create_property_log_stream(p)
            stream_name = "#{name}.#{p.name}"
            p.log_stream = if !configuration_log.stream?(stream_name)
                               configuration_log.create_stream(stream_name, p.type, p.log_metadata)
                           else
                               configuration_log.stream(stream_name)
                           end
        end

        # Tell the task to use the given Pocolog::Logfile object to log all
        # changes to its properties
        def log_all_configuration(logfile)
            @configuration_log = logfile
            each_property do |p|
                create_property_log_stream(p)
                p.log_current_value
            end
        end

        # Waits for the task to be in state +state_name+ for the specified
        # amount of time
        #
        # Raises RuntimeError on timeout
        def wait_for_state(state_name, timeout = nil, polling = 0.1)
            state_name = state_name.to_sym

            start = Time.now
            peek_state
            until @state_queue.include?(state_name)
                raise "timing out while waiting for #{self} to be in state #{state_name}. It currently is in state #{current_state}" if timeout && (Time.now - start) > timeout

                sleep polling
                peek_state
            end
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

        ##
        # :method: configure
        #
        # Configures the component, i.e. do the transition from STATE_PRE_OPERATIONAL into
        # STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in
        # STATE_PRE_OPERATIONAL state before the call, or if the component
        # refused to do the transition (startHook() returned false)
        state_transition_call :configure, "PRE_OPERATIONAL", "STOPPED"

        ##
        # :method: start
        #
        # Starts the component, i.e. do the transition from STATE_STOPPED into
        # STATE_RUNNING.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call, or if the component refused to do the
        # transition (startHook() returned false)
        state_transition_call :start, "STOPPED", "RUNNING"

        ##
        # :method: reset_exception
        #
        # Recover from the exception state. It does the transition from
        # STATE_EXCEPTION to either STATE_STOPPED if the component does not
        # need any configuration or STATE_PRE_OPERATIONAL otherwise
        #
        # Raises StateTransitionFailed if the component was not in a proper
        # state before the call.
        state_transition_call :reset_exception, "EXCEPTION", nil

        ##
        # :method: stop
        #
        # Stops the component, i.e. do the transition from STATE_RUNNING into
        # STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in STATE_RUNNING
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        state_transition_call :stop, "RUNNING", "STOPPED"

        ##
        # :method: cleanup
        #
        # Cleans the component, i.e. do the transition from STATE_STOPPED into
        # STATE_PRE_OPERATIONAL.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        state_transition_call :cleanup, "STOPPED", "PRE_OPERATIONAL"

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

        # Returns an Attribute object representing the given attribute
        #
        # Raises NotFound if no such attribute exists.
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
        def attribute(name)
            name = name.to_s
            if a = attributes[name]
                if attribute?(name)
                    return a
                else
                    attributes.delete(name)
                    raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have an attribute named #{name}", e.backtrace
                end
            end

            type_name = CORBA.refine_exceptions(self) do
                do_attribute_type_name(name)
            rescue ArgumentError => e
                raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have an attribute named #{name}", e.backtrace
            end

            a = Attribute.new(self, name, type_name)
            if configuration_log
                create_property_log_stream(a)
                a.log_current_value
            end
            attributes[name] = a
        end

        # Return the property object without caching nor validation
        def raw_property(name)
            type_name = CORBA.refine_exceptions(self) do
                do_property_type_name(name)
            rescue ArgumentError => e
                raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have a property named #{name}", e.backtrace
            end
            Property.new(self, name, type_name)
        end

        # Returns a Property object representing the given property
        #
        # Raises NotFound if no such property exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.property("myProperty").read
        #   task.property("myProperty").write(value)
        #
        # is equivalent to
        #
        #   task.myProperty
        #   task.myProperty = value
        #
        def property(name)
            name = name.to_s
            if p = properties[name]
                if property?(name)
                    return p
                else
                    properties.delete(name)
                    raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have a property named #{name}", e.backtrace
                end
            end

            p = raw_property(name)
            if configuration_log
                create_property_log_stream(p)
                p.log_current_value
            end
            properties[name] = p
        end

        # @api private
        #
        # Resolve a Port object for the given port name
        def raw_port(name)
            port_model = model.find_port(name)
            do_port(name, port_model)
        rescue Runkit::NotFound => e
            raise Runkit::InterfaceObjectNotFound.new(self, name), "task #{self.name} does not have a port named #{name}", e.backtrace
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

        # Returns the Orogen specification object for this task's model. It will
        # return a default model if the remote task does not respond to getModelName
        # or the description file cannot be found.
        #
        # See also #info
        def model
            model = super
            return model if model

            model_name = begin
                             getModelName
                         rescue NoMethodError
                             nil
                         end

            self.model =
                if !model_name
                    Runkit.warn "#{name} is a task context not generated by orogen, using default task model" if name !~ /.*runkitrb_(\d+)$/
                    Runkit.create_orogen_task_context_model(name)
                elsif model_name.empty?
                    Runkit.create_orogen_task_context_model
                else
                    begin
                        Runkit.default_loader.task_model_from_name(model_name)
                    rescue OroGen::NotFound
                        Runkit.warn "#{name} is a task context of class #{model_name}, but I cannot find the description for it, falling back"
                        Runkit.create_orogen_task_context_model(model_name)
                    end
                end
        end

        def connect_to(sink, policy = {})
            port = find_output_port(sink.type, nil)
            raise ArgumentError, "port #{sink.name} does not match any output port of #{name}" unless port

            port.connect_to(sink, policy)
        end

        def disconnect_from(sink, policy = {})
            each_output_port do |out_port|
                out_port.disconnect_from(sink) if out_port.type == sink.type
            end
            nil
        end

        def resolve_connection_from(source, policy = {})
            port = find_input_port(source.type, nil)
            raise ArgumentError, "port #{source.name} does not match any input port of #{name}." unless port

            source.connect_to(port, policy)
        end

        def resolve_disconnection_from(source)
            each_input_port do |in_port|
                source.disconnect_from(in_port) if in_port.type == source.type
            end
            nil
        end
    end
end
