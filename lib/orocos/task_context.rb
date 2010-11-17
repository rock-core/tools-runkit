require 'utilrb/object/attribute'

module Orocos
    # This class represents both RTT attributes and properties
    class AttributeBase
        # The underlying TaskContext instance
        attr_reader :task
        # The property/attribute name
        attr_reader :name
        # The attribute type, as a subclass of Typelib::Type
        attr_reader :type

        def initialize(task, name, orocos_type_name)
            @task, @name = task, name
            @orocos_type_name = orocos_type_name
            @type = Orocos.typelib_type_for(orocos_type_name)
            @type_name = type.name
        end

        # Read the current value of the property/attribute
        def read
            value = type.new
            do_read(@orocos_type_name, value)
            value.to_ruby
        end

        # Sets a new value for the property/attribute
        def write(value)
            value = Typelib.from_ruby(value, type)
            do_write(@orocos_type_name, value)
            value
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type.name})"
        end
    end

    class Property < AttributeBase
        def do_write_string(value)
            task.do_property_write_string(name, value)
        end
        def do_write(type_name, value)
            task.do_property_write(name, type_name, value)
        end
        def do_read_string
            task.do_property_read_string(name)
        end
        def do_read(type_name, value)
            task.do_property_read(name, type_name, value)
        end
    end

    class Attribute < AttributeBase
        def do_write_string(value)
            task.do_attribute_write_string(name, value)
        end
        def do_write(type_name, value)
            task.do_attribute_write(name, type_name, value)
        end
        def do_read_string
            task.do_attribute_read_string(name)
        end
        def do_read(type_name, value)
            task.do_attribute_read(name, type_name, value)
        end
    end

    # Specialization of the OutputReader to read the task'ss state port. Its
    # read method will return a state in the form of a symbol. For instance, the
    # RUNTIME_ERROR state is returned as :RUNTIME_ERROR
    #
    # StateReader objects are created by TaskContext#state_reader
    class StateReader < OutputReader
        class << self
            private :new
        end

        def read
            if value = super
                @state_symbols[value]
            end
        end

        def read_new
            if value = super
                @state_symbols[value]
            end
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
        # The name of this task context
        attr_reader :name
	# The process that supports it
	attr_accessor :process

        RUNNING_STATES = []
        RUNNING_STATES[STATE_PRE_OPERATIONAL] = false
        RUNNING_STATES[STATE_STOPPED]         = false
        RUNNING_STATES[STATE_RUNNING]         = true
        RUNNING_STATES[STATE_RUNTIME_ERROR]   = true
        RUNNING_STATES[STATE_FATAL_ERROR]     = false
        RUNNING_STATES[STATE_EXCEPTION]     = false

        def initialize
            @ports ||= Hash.new

            # This is important as it will make the system load the task model
            # (if needed)
            model = self.model

            if model
                @state_symbols = model.each_state.map { |name, type| name.to_sym }
                @error_states  = model.each_state.
                    map { |name, type| name.to_sym if (type == :error || type == :exception || type == :fatal) }.
                    compact.to_set
                @exception_states  = model.each_state.
                    map { |name, type| name.to_sym if type == :exception }.
                    compact.to_set
                @runtime_states = model.each_state.
                    map { |name, type| name.to_sym if (type == :error || type == :runtime) }.
                    compact.to_set
                @fatal_states = model.each_state.
                    map { |name, type| name.to_sym if type == :fatal }.
                    compact.to_set

                if model.component.typekit
                    Orocos::CORBA.load_typekit(model.component.name)
                end
                model.used_typekits.each do |tk|
                    Orocos::CORBA.load_typekit(tk.name)
                end
            else
                @state_symbols = []
                @state_symbols[STATE_PRE_OPERATIONAL] = :PRE_OPERATIONAL
                @state_symbols[STATE_STOPPED]         = :STOPPED
                @state_symbols[STATE_RUNNING]         = :RUNNING
                @state_symbols[STATE_RUNTIME_ERROR]   = :RUNTIME_ERROR
                @state_symbols[STATE_EXCEPTION]       = :EXCEPTION
                @state_symbols[STATE_FATAL_ERROR]     = :FATAL_ERROR
                @error_states     = Set.new
                @runtime_states   = Set.new
                @exception_states = Set.new
                @fatal_states     = Set.new
            end

            @error_states   << :RUNTIME_ERROR << :FATAL_ERROR << :EXCEPTION
            @runtime_states << :RUNNING << :RUNTIME_ERROR
            @exception_states << :EXCEPTION
            @fatal_states     << :FATAL_ERROR
        end

        def ping
            operation_signature('start')
            nil
        end

        # True if the given symbol is the name of an error state
        def error_state?(sym); @error_states.include?(sym) end
        # True if the given symbol is the name of an exception state
        def exception_state?(sym); @exception_states.include?(sym) end
        # True if the given symbol is the name of a fatal error state
        def fatal_error_state?(sym); @fatal_states.include?(sym) end
        # True if the given symbol is the name of a runtime state
        def runtime_state?(sym); @runtime_states.include?(sym) end

        def to_s
            "#<TaskContext: #{self.class.name}/#{name}>"
        end
	class << self
	    # The only way to create TaskContext is TaskContext.get
	    private :new
	end

        # Returns an array of symbols that give the tasks' state names from
        # their integer value. This is mostly for internal use.
        def available_states # :nodoc:
            if @states
                return @states
            end

        end

        # Find the running tasks from the provided names.
        def self.find_running(*names)
            names.map do |name|
                begin TaskContext.get name
                rescue Orocos::NotFound
                end
            end.compact.map(&:running?)
        end

        # Find one running tasks from the provided names. Raises if there is not
        # exactly one
        def self.find_one_running(*names)
            candidates = names.map do |name|
                begin TaskContext.get name
                rescue Orocos::NotFound
                end
            end.compact

            if candidates.empty?
                raise "cannot find any task in #{names.join(", ")}"
            end

            running_candidates = candidates.find_all(&:running?)
            if running_candidates.empty?
                raise "none of #{running_candidates.map(&:name).join(", ")} is running"
            elsif running_candidates.size > 1
                raise "multiple candidates are running: #{running_candidates.map(&:name)}"
            else
                running_candidates.first
            end
        end

        # Returns a task which provides the +type+ interface.
        #
        # Use TaskContext.get(:provides => name) instead.
        def self.get_provides(type) # :nodoc:
            results = Orocos.enum_for(:each_task).find_all do |task|
                task.implements?(type)
            end

            if results.empty?
                raise Orocos::NotFound, "no task implements #{type}"
            elsif results.size > 1
                candidates = results.map { |t| t.name }.join(", ")
                raise Orocos::NotFound, "more than one task implements #{type}: #{candidates}"
            end
            get(results.first.name)
        end

	# :call-seq:
        #   TaskContext.get(name) => task
        #   TaskContext.get(:provides => interface_name) => tas
        #
        # In the first form, returns the TaskContext instance representing the
        # remote task context with the given name.
        #
        # In the second form, searches for a task context that implements the given
        # interface. This is doable only if orogen has been used to generate the
        # components.
        #
        # Raises Orocos::NotFound if the task name does not exist, if no task
        # implements the given interface, or if more than one task does
        # implement the required interface
	def self.get(options, process = nil)
            if options.kind_of?(Hash)
                # Right now, the only allowed option is :provides
                options = Kernel.validate_options options, :provides => nil
                return get_provides(options[:provides].to_str)
            else
                name = options.to_str
            end

            # Try to find ourselves a process object if none is given
            if !process
                process = Orocos.enum_for(:each_process).
                    find do |p|
                        p.task_names.any? { |n| n == name }
                    end
            end

            result = CORBA.refine_exceptions("naming service") do
                do_get(name)
            end
            result.instance_variable_set :@process, process
            result.instance_variable_set :@name, name
            result.send(:initialize)
            result
	end

        # Returns true if +task_name+ is a TaskContext object that can be
        # reached through CORBA
        def self.reachable?(task_name)
            # TaskContext.do_get already checks if the remote task is
            # accessible, so no need to do it again
            t = CORBA.refine_exceptions("naming service") do
                TaskContext.do_get(task_name)
            end
            true
        rescue Orocos::NotFound
            false
        end

        # Returns true if the remote task context can still be reached through
        # CORBA, and false otherwise.
        def reachable?
            ping
            true
        rescue CORBA::ComError
            false
        end

        # Returns true if the task is in a state where code is executed. This
        # includes of course the running state, but also runtime error states.
        def running?
            @runtime_states.include?(state)
        end
        # Returns true if the task has been configured.
        def ready?;   state != :PRE_OPERATIONAL end
        # Returns true if the task is in an error state (runtime or fatal)
        def error?
            error_state?(state)
        end
        # Returns true if the task is in a runtime error state
        def runtime_error?
            error_state?(state) && !exception_state?(state) && !fatal_error_state?(state)
        end
        # Returns true if the task is in an exceptional state
        def exception?
            exception_state?(state)
        end
        # Returns true if the task is in a fatal error state
        def fatal_error?
            fatal_error_state?(state)
        end

        # Automated wrapper to handle CORBA exceptions coming from the C
        # extension
        def self.corba_wrap(m, *args) # :nodoc:
            class_eval <<-EOD
            def #{m}(#{args.join(". ")})
                CORBA.refine_exceptions(self) { do_#{m}(#{args.join(", ")}) }
            end
            EOD
        end

        # Returns a StateReader object that allows to flexibly monitor the
        # task's state
        def state_reader(policy = Hash.new)
            p = port('state')
            policy = p.validate_policy({:init => true, :type => :buffer, :size => 10}.merge(policy))

            # Create the mapping from state integers to state symbols
            reader = p.do_reader(StateReader, p.orocos_type_name, policy)
            reader.instance_variable_set :@state_symbols, @state_symbols
            reader
        end

        # :method: state
        #
        # call-seq:
        #  task.state => value
        #
        # Returns the state of the task, as a symbol. The possible values for
        # all task contexts are:
        # 
        #   :PRE_OPERATIONAL
        #   :STOPPED
        #   :ACTIVE
        #   :RUNNING
        #   :RUNTIME_WARNING
        #   :RUNTIME_ERROR
        #   :FATAL_ERROR
        #
        # If extended support is available, the custom states are also reported
        # with their name. For instance, after the orogen definition
        #
        #   runtime_states "CUSTOM_RUNTIME"
        #
        # #state will return :CUSTOM_RUNTIME if the component goes into that
        # state.
        def state(return_current = true)
            if model && model.extended_state_support?
                @state_reader ||= state_reader
                if return_current
                    while new_state = @state_reader.read_new
                        @current_state = new_state
                    end
                else
                    if new_state = @state_reader.read_new
                        @current_state = new_state
                    end
                end
                @current_state
            else
                rtt_state
            end
        end

        def rtt_state
            value = CORBA.refine_exceptions(self) { do_state() }
            @state_symbols[value]
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
        corba_wrap :configure

        ##
        # :method: start
        #
        # Starts the component, i.e. do the transition from STATE_STOPPED into
        # STATE_RUNNING.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call, or if the component refused to do the
        # transition (startHook() returned false)
        corba_wrap :start

        ##
        # :method: reset_error
        #
        # Recover from a fatal error. It does the transition from
        # STATE_FATAL_ERROR to STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in a proper
        # state before the call.
        corba_wrap :reset_exception

        ##
        # :method: stop
        #
        # Stops the component, i.e. do the transition from STATE_RUNNING into
        # STATE_STOPPED.
        #
        # Raises StateTransitionFailed if the component was not in STATE_RUNNING
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        corba_wrap :stop

        ##
        # :method: cleanup
        #
        # Cleans the component, i.e. do the transition from STATE_STOPPED into
        # STATE_PRE_OPERATIONAL.
        #
        # Raises StateTransitionFailed if the component was not in STATE_STOPPED
        # state before the call. The component cannot refuse to perform the
        # transition (but can take an arbitrarily long time to do it).
        corba_wrap :cleanup

        # Returns true if this task context has either a property or an attribute with the given name
        def has_property?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_property?(name)
            end
        end

        # Alias for has_property?
        def has_attribute?(name)
            has_property?(name)
        end

        # Returns true if this task context has a command with the given name
        def has_operation?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_operation?(name)
            end
        end

        # Returns true if this task context has a port with the given name
        def has_port?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_port?(name)
            end
        end

        # Returns the array of the names of available properties on this task
        # context
        def property_names
            CORBA.refine_exceptions(self) do
                do_property_names
            end
        end

        # Returns the array of the names of available attributes on this task
        # context
        def attribute_names
            CORBA.refine_exceptions(self) do
                do_attribute_names
            end
        end

        # Returns true if +name+ is the name of a property on this task context
        def has_property?(name)
            property_names.include?(name.to_str)
        end

        # Returns true if +name+ is the name of a attribute on this task context
        def has_attribute?(name)
            attribute_names.include?(name.to_str)
        end

        # Returns an Attribute object representing the given attribute
        #
        # Raises NotFound if no such attribute exists.
        #
        # Attributes can also be read and written by calling directly the
        # relevant method on the task context:
        #
        #   task.attribute("myProperty").get
        #   task.attribute("myProperty").set(value)
        #
        # is equivalent to
        #
        #   task.myProperty
        #   task.myProperty = value
        #
        def attribute(name)
            name = name.to_s
            type_name = CORBA.refine_exceptions(self) do
                do_attribute_type_name(name)
            end

            Attribute.new(self, name, type_name)
        end

        # Returns a Property object representing the given property
        #
        # Raises NotFound if no such property exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.property("myProperty").get
        #   task.property("myProperty").set(value)
        #
        # is equivalent to
        #
        #   task.myProperty
        #   task.myProperty = value
        #
        def property(name)
            name = name.to_s
            type_name = CORBA.refine_exceptions(self) do
                begin
                    do_property_type_name(name)
                rescue ArgumentError
                    raise Orocos::NotFound, "no such property #{name}"
                end
            end

            Property.new(self, name, type_name)
        end

        # Returns the Orocos::Generation::OutputPort instance that describes the
        # required port, or nil if the port does not exist
        def output_port_model(name)
            if port_model = model.each_output_port.find { |p| p.name == name }
                port_model
            else model.find_dynamic_output_ports(name, nil).first
            end
        end

        # Returns the Orocos::Generation::InputPort instance that describes the
        # required port, or nil if the port does not exist
        def input_port_model(name)
            if port_model = model.each_input_port.find { |p| p.name == name }
                port_model
            else model.find_dynamic_input_ports(name, nil).first
            end
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
                    if !verify || has_port?(name) # Check that this port is still valid
                        @ports[name]
                    else
                        @ports.delete(name)
                        raise NotFound, "no port named '#{name}' on task '#{self.name}'"
                    end
                else
                    @ports[name] = do_port(name)
                end
            end
        end

        # call-seq:
        #  task.each_port { |p| ... } => task
        # 
        # Enumerates the ports that are available on this task, as instances of
        # either Orocos::InputPort or Orocos::OutputPort
        def each_port(&block)
            CORBA.refine_exceptions(self) do
                do_each_port(&block)
            end
            self
        end

        # call-seq:
        #  task.each_property { |a| ... } => task
        # 
        # Enumerates the properties that are available on
        # this task, as instances of Orocos::Attribute
        def each_property(&block)
            if !block_given?
                return enum_for(:each_property)
            end

            names = CORBA.refine_exceptions(self) do
                do_property_names
            end
            names.each do |name|
                yield(property(name))
            end
        end

        # call-seq:
        #  task.each_attribute { |a| ... } => task
        # 
        # Enumerates the attributes that are available on
        # this task, as instances of Orocos::Attribute
        def each_attribute(&block)
            if !block_given?
                return enum_for(:each_attribute)
            end

            names = CORBA.refine_exceptions(self) do
                do_attribute_names
            end
            names.each do |name|
                yield(attribute(name))
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
        end

        def method_missing(m, *args) # :nodoc:
            m = m.to_s
            if m =~ /^(\w+)=/
                name = $1
                begin
                    return property(name).write(*args)
                rescue Orocos::NotFound
                end

            else
                if has_port?(m)
                    return port(m)
                elsif has_operation?(m)
                    return operation(m).callop(*args)
                end

                begin
                    return property(m).read(*args)
                rescue Orocos::NotFound
                end
            end
            super(m.to_sym, *args)
        end

        # Returns the Orogen specification object for this task instance.
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen *and* this deployment has been
        # started by this Ruby instance
        #
        # To get the Orogen specification for the task context itself (an
        # Orocos::Generation::TaskContext instance), use #model.
        #
        # The returned value is an instance of Orocos::Generation::TaskDeployment
        #
        # See also #model
        def info
            if process
                @info ||= process.orogen.task_activities.find { |act| act.name == name }
            end
        end

        # Returns the Orogen specification object for this task's model
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
        #
        # The returned value is an instance of Orocos::Generation::TaskContext
        #
        # See also #info
        def model
            if @model
                @model
            elsif info
                @model = info.context
            elsif has_operation?("getModelName")
                model_name = self.getModelName

                # Try to find the tasklib that handles our model
                if tasklib_name = Orocos.available_task_models[model_name]
                    tasklib = Orocos.master_project.load_task_library(tasklib_name)
                    @model = tasklib.tasks.find { |t| t.name == model_name }
                end
            end
        end

        # True if this task's model is a subclass of the provided class name
        #
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
        def implements?(class_name)
            model.implements?(class_name)
        end

        def pretty_print(pp) # :nodoc:
            states_description = TaskContext.constants.grep(/^STATE_/).
                inject([]) do |map, name|
                    map[TaskContext.const_get(name)] = name.to_s.gsub /^STATE_/, ''
                    map
                end

            pp.text "Component #{name}"
            pp.breakable
            pp.text "  state: #{state}"
            pp.breakable

            [['attributes', each_attribute], ['properties', each_property]].each do |kind, enum|
                objects = enum.to_a
                if objects.empty?
                    pp.text "No #{kind}"
                    pp.breakable
                else
                    pp.text "#{kind.capitalize}:"
                    pp.breakable
                    pp.nest(2) do
                        pp.text "  "
                        objects.each do |o|
                            o.pretty_print(pp)
                            pp.breakable
                        end
                    end
                    pp.breakable
                end
            end

            ports = enum_for(:each_port).to_a
            if ports.empty?
                pp.text "No ports"
                pp.breakable
            else
                pp.text "Ports:"
                pp.breakable
                pp.nest(2) do
                    pp.text "  "
                    each_port do |port|
                        port.pretty_print(pp)
                        pp.breakable
                    end
                end
                pp.breakable
            end
        end

        # Searches for a port object in +port_set+ that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def self.find_all_ports(port_set, type, port_name)
            candidates = port_set.dup

            # Filter out on type
            if type
                type_name =
                    if !type.respond_to?(:to_str)
                        type.name
                    else type.to_str
                    end
                candidates.delete_if { |port| port.type_name != type_name }
            end

            # Filter out on name
            if port_name
                if !port_name.kind_of?(Regexp)
                    port_name = Regexp.new(port_name) 
                end
                candidates.delete_if { |port| port.full_name !~ port_name }
            end
            candidates
        end

        # Searches for a port object in +port_set+ that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def self.find_port(port_set, type, port_name)
            candidates = find_all_ports(port_set, type, port_name)
            if candidates.size > 1
                type_name =
                    if !type.respond_to?(:to_str)
                        type.name
                    else type.to_str
                    end
                if port_name
                    raise ArgumentError, "#{type_name} is provided by multiple streams that match #{port_name}: #{candidates.map(&:stream).map(&:name).join(", ")}"
                else
                    raise ArgumentError, "#{type_name} is provided by multiple streams: #{candidates.map(&:stream).map(&:name).join(", ")}"
                end
            else candidates.first
            end
        end

        # Returns the set of ports in +self+ that match the given specification.
        # Set one of the criteria to nil to ignore it.
        #
        # See also #find_port and TaskContext.find_all_ports
        def find_all_ports(type_name, port_name)
            TaskContext.find_all_ports(@ports.values, type_name, port_name)
        end

        # Returns a single port in +self+ that match the given specification.
        # Set one of the criteria to nil to ignore it.
        #
        # Raises ArgumentError if multiple candidates are available
        #
        # See also #find_all_ports and TaskContext.find_port
        def find_port(type_name, port_name)
            TaskContext.find_port(@ports.values, type_name, port_name)
        end
    end
end

