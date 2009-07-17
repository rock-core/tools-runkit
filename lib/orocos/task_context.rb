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
            if @type_name == "/std/string" && value.respond_to?(:to_str)
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
        end

	class << self
	    # The only way to create TaskContext is TaskContext.get
	    private :new
	end

	# Returns the TaskContext instance representing the remote task context
	# with the given name. Raises Orocos::NotFound if the task name does
	# not exist.
	def self.get(name, process = nil)
            name = name.to_s

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
            result.instance_variable_set(:@process, process)
            result
	end

        # Returns true if the task is in a state where code is executed. This
        # includes of course the running state, but also runtime error states.
        def running?; RUNNING_STATES[state] end
        # Returns true if the task has been configured.
        def ready?;   state != STATE_PRE_OPERATIONAL end
        # Returns true if the task is in an error state (runtime or fatal)
        def error?
            s = state
            s == STATE_RUNTIME_ERROR || s == STATE_FATAL_ERROR
        end

        def self.corba_wrap(m, *args)
            class_eval <<-EOD
            def #{m}(#{args.join(". ")})
                CORBA.refine_exceptions(self) { do_#{m}(#{args.join(", ")}) }
            end
            EOD
        end

        corba_wrap :state
        corba_wrap :start
        corba_wrap :cleanup
        corba_wrap :stop
        corba_wrap :configure

        def has_port?(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_has_port?(name)
            end
        end

        def attribute(name)
            name = name.to_s
            CORBA.refine_exceptions(self) do
                do_attribute(name)
            end
        end

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

        def rtt_method(name)
            CORBA.refine_exceptions(self) do
                do_rtt_method(name.to_s)
            end
        end
	def command(name)
            CORBA.refine_exceptions(self) do
                do_command(name.to_s)
            end
	end

        def method_missing(m, *args)
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
                end

                begin
                    return attribute(m).read(*args)
                rescue Orocos::NotFound
                end
            end
            super(m.to_sym, *args)
        end

        def info
            process.orogen.task_activities.find { |act| act.name == name }
        end
        def model
            info.context
        end

        def implements?(class_name)
            model.implements?(class_name)
        end

        def pretty_print(pp)
            states_description = TaskContext.constants.grep(/^STATE_/).
                inject([]) do |map, name|
                    map[TaskContext.const_get(name)] = name.gsub /^STATE_/, ''
                    map
                end

            pp.text "Component #{name}"
            pp.breakable
            pp.text "  state: #{states_description[state]}"
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

