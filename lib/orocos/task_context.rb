require 'utilrb/object/attribute'

module Orocos
    class Attribute
	class << self
	    # The only way to create an Attribute object is
	    # TaskContext#attribute
	    private :new
	end

        attr_reader :task
        attr_reader :name
        attr_reader :type

        def initialize
            if @type_name == "string"
                @type_name = "/std/string"
            end
            if !(@type = Orocos.registry.get(@type_name))
                raise "can not find #{@type_name} in the registry"
            end
        end

        def read
            if @type_name == "/std/string"
                do_read_string
            else
                value = type.new
                do_read(@type_name, value)
                value.to_ruby
            end
        end

        def write(value)
            if @type_name == "/std/string"
                do_write_string(value.to_str)
            else
                value = Typelib.from_ruby(value, type)
                do_write(@type_name, value)
            end
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type.name})"
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
	attr_reader :process

        RUNNING_STATES = []
        RUNNING_STATES[STATE_PRE_OPERATIONAL] = false
        RUNNING_STATES[STATE_ACTIVE]          = false
        RUNNING_STATES[STATE_STOPPED]         = false
        RUNNING_STATES[STATE_RUNNING]         = true
        RUNNING_STATES[STATE_RUNTIME_ERROR]   = true
        RUNNING_STATES[STATE_RUNTIME_WARNING] = true
        RUNNING_STATES[STATE_FATAL_ERROR]     = false

        def initialize
            @ports ||= Hash.new

            if model
                @state_symbols = model.each_state.map { |name, type| name.to_sym }
                @error_states  = model.each_state.
                    map { |name, type| name.to_sym if (type == :error || type == :fatal) }.
                    compact.to_set
                @runtime_states = model.each_state.
                    map { |name, type| name.to_sym if (type == :error || type == :runtime) }.
                    compact.to_set
                @fatal_states = model.each_state.
                    map { |name, type| name.to_sym if type == :fatal }.
                    compact.to_set
            else
                @state_symbols = []
                @state_symbols[STATE_PRE_OPERATIONAL] = :PRE_OPERATIONAL
                @state_symbols[STATE_ACTIVE]          = :ACTIVE
                @state_symbols[STATE_STOPPED]         = :STOPPED
                @state_symbols[STATE_RUNNING]         = :RUNNING
                @state_symbols[STATE_RUNTIME_ERROR]   = :RUNTIME_ERROR
                @state_symbols[STATE_RUNTIME_WARNING] = :RUNTIME_WARNING
                @state_symbols[STATE_FATAL_ERROR]     = :FATAL_ERROR
                @error_states  = Set.new
                @fatal_states  = Set.new
            end

            @error_states << :RUNTIME_ERROR << :FATAL_ERROR
            @runtime_states << :RUNNING << :RUNTIME_ERROR
            @fatal_states << :FATAL_ERROR
        end

        def error_state?(sym); @error_states.include?(sym) end
        def fatal_error_state?(sym); @fatal_states.include?(sym) end
        def runtime_state?(sym); @runtime_states.include?(sym) end

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

	# call-seq:
        #   TaskContext.get(name) => task
        #   TaskContext.get(:provides => interface_name) => task
        #
        # In the first form, returns the TaskContext instance representing the
        # remote task context with the given name.
        #
        # In the second form, searches for a task context that implements the given
        # interface. This is doable only if orogen has been used to generate the
        # components.
        #
        # Raises Orocos::NotFound if the task name does not exist, or if no task
        # implements the given interface.
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

        # Returns true if the task is in a state where code is executed. This
        # includes of course the running state, but also runtime error states.
        def running?
            @runtime_states.include?(state)
        end
        # Returns true if the task has been configured.
        def ready?;   state != :PRE_OPERATIONAL end
        # Returns true if the task is in an error state (runtime or fatal)
        def error?
            @error_states.include?(state)
        end
        # Returns true if the task is in a runtime error state
        def runtime_error?
            error_state?(state) && !fatal_error_state?(state)
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
            policy = p.validate_policy({:init => true}.merge(policy))
            policy[:init] = true

            # Create the mapping from state integers to state symbols
            reader = p.do_reader(StateReader, p.type_name, policy)
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
        # #state may return :CUSTOM_RUNTIME if the component goes into that
        # state.
        def state
            if model.extended_state_support?
                @state_reader ||= state_reader
                state_reader.read
            else
                value = CORBA.refine_exceptions(self) { do_state() }
                @state_symbols[value]
            end
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
        corba_wrap :reset_error

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

        # Returns true if this task context has a command with the given name
        def has_method?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_method?(name)
            end
        end

        # Returns true if this task context has a command with the given name
        def has_command?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_command?(name)
            end
        end

        # Returns true if this task context has a port with the given name
        def has_port?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_port?(name)
            end
        end

        # Returns an Attribute object representing the given attribute or
        # property.
        #
        # Raises NotFound if no such attribute or property exists.
        #
        # Ports can also be accessed by calling directly the relevant
        # method on the task context:
        #
        #   task.attribute("myProperty")
        #
        # is equivalent to
        #
        #   task.myProperty
        #
        def attribute(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_attribute(name)
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
        def port(name)
            name = name.to_str
            CORBA.refine_exceptions(self) do
                if @ports[name]
                    if has_port?(name) # Check that this port is still valid
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
        #  task.each_attribute { |a| ... } => task
        # 
        # Enumerates the attributes and properties that are available on
        # this task, as instances of Orocos::Attribute
        def each_attribute(&block)
            CORBA.refine_exceptions(self) do
                do_each_attribute(&block)
            end
            self
        end

        # Returns a RTTMethod object that represents the given method on the
        # remote component.
        #
        # Raises NotFound if no such method exists.
        def rtt_method(name)
            CORBA.refine_exceptions(self) do
                do_rtt_method(name.to_s)
            end
        end
        # Returns a Command object that represents the given command on the
        # remote component.
        #
        # Raises NotFound if no such command exists.
        #
        # See also #rtt_command
	def command(name)
            CORBA.refine_exceptions(self) do
                do_command(name.to_s)
            end
	end
        # Like #command. Provided for consistency with #rtt_method
        def rtt_command(name); command(name) end

        def method_missing(m, *args) # :nodoc:
            m = m.to_s
            if m =~ /^(\w+)=/
                name = $1
                begin
                    return attribute(name).write(*args)
                rescue Orocos::NotFound
                end

            else
                if has_port?(m)
                    return port(m)
                elsif has_method?(m)
                    return rtt_method(m).call(*args)
                elsif has_command?(m)
                    command = rtt_command(m)
                    command.call(*args)
                    return command
                end

                begin
                    return attribute(m).read(*args)
                rescue Orocos::NotFound
                end
            end
            super(m.to_sym, *args)
        end

        # Returns the Orogen specification object for this task instance.
        # This is available only if the deployment in which this task context
        # runs has been generated by orogen.
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
        # See also #info
        def model
            if @model
                @model
            elsif info
                @model = info.context
            elsif has_method?("getModelName")
                model_name = self.getModelName

                # Try to find the tasklib that handles our model
                if tasklib_name = Orocos.available_task_models[model_name]
                    tasklib = Orocos::Generation.load_task_library(tasklib_name)
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
                    map[TaskContext.const_get(name)] = name.gsub /^STATE_/, ''
                    map
                end

            pp.text "Component #{name}"
            pp.breakable
            pp.text "  state: #{state}"
            pp.breakable

            attributes = enum_for(:each_attribute).to_a
            if attributes.empty?
                pp.text "No attributes"
                pp.breakable
            else
                pp.text "Attributes:"
                pp.breakable
                pp.nest(2) do
                    pp.text "  "
                    each_attribute do |attribute|
                        attribute.pretty_print(pp)
                        pp.breakable
                    end
                end
                pp.breakable
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
    end
end

