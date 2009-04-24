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
            @type = Orocos.registry.get(@type_name)
        end

        def read
            value = type.new
            do_read(@type_name, value)
            value.to_ruby
        end

        def write(value)
            value = Typelib.from_ruby(value, type)
            do_write(@type_name, value)
        end

        def pretty_print(pp) # :nodoc:
            pp.text "attribute #{name} (#{type_name})"
        end
    end

    class TaskContext
        # The name of this task context
        attr_reader :name

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
	def self.get(name)
	    name = name.to_s
	    CORBA.refine_exceptions("naming service") do
		do_get(name)
	    end
	end

        # Returns true if the task is in a state where code is executed. This
        # includes of course the running state, but also runtime error states.
        def running?; RUNNING_STATES[state] end
        # Returns true if the task has been configured.
        def ready?;   state != STATE_PRE_OPERATIONAL end

        def self.corba_wrap(m, *args)
            class_eval <<-EOD
            def #{m}(#{args.join(". ")})
                CORBA.refine_exceptions(self) { do_#{m}(#{args.join(", ")}) }
            end
            EOD
        end

        corba_wrap :state
        corba_wrap :start
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

            pp.nest(2) do
                pp.text "  "
                each_attribute do |attribute|
                    attribute.pretty_print(pp)
                    pp.breakable
                end
            end

            pp.nest(2) do
                pp.text "  "
                each_port do |port|
                    port.pretty_print(pp)
                    pp.breakable
                end
            end
        end
    end
end

