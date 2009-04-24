module Orocos
    class Callable
        # The task this method is part of
        attr_reader :task

        # The method name
        attr_reader :name
        # The method description
        attr_reader :description
        # An array describing the arguments. Each element is <tt>[name, doc,
        # type_name]</tt>
        attr_reader :arguments_spec
        # The typelib types for the arguments.
        attr_reader :arguments_types

        class << self
            private :new
        end

        def initialize
            @arguments_types = []
            arguments_spec.each do |_, _, type_name|
                arguments_types << Orocos.registry.get(type_name)
            end
            @args_type_names = arguments_spec.map { |name, doc, type| type }
        end

        def common_call(args)
            if args.size() != arguments_spec.size()
                raise ArgumentError, "not enough arguments"
            end

            filtered = []
            args.each_with_index do |v, i|
                filtered << Typelib.from_ruby(v, arguments_types[i])
            end
            CORBA.refine_exceptions(self) do
                yield(filtered)
            end
        end
    end

    # This class represents methods on remote components. It is called RTTMethod
    # in order to not clash with Ruby's Method object.
    class RTTMethod < Callable
        # The type name of the return value
        attr_reader :return_spec
        # The typelib object representing the type of the return value
        attr_reader :return_type

        def initialize
            super
            @return_type = Orocos.registry.get(return_spec)
        end

        # Calls the method with the last used arguments. This is much faster
        # than using #call because the arguments have already been marshalled
        # and sent to the other side
        #
        # Raises NeverCalled if the method has never been called before
        def recall
            CORBA.refine_exceptions(self) do
                result = return_type.new
                do_recall(result)
            end
        end

        # Calls the method with the provided arguments
        def call(*args)
            result = return_type.new
            common_call(args) do |filtered|
                do_call(@args_type_names, filtered, result)
            end
            result
        end
    end

    class Command < Callable
        class StateError < RuntimeError; end

        attr_reader :state

        def initialize
            super
            @state = STATE_READY
        end

        class << self
            attr_writer :state_auto_update
            def state_auto_update?; @state_auto_update end
        end
        @state_auto_update = true

        def recall
            if state != STATE_READY
                raise StateError, "the command is not ready. Call #reset first."
            end

            common_call(args) do |filtered|
                do_recall
                @state = STATE_SENT
            end
        end

        def call(*args)
            if state != STATE_READY
                raise StateError, "the command is not ready. Call #reset first."
            end

            common_call(args) do |filtered|
                do_call(@args_type_names, filtered)
                @state = STATE_SENT
            end
        end

        def reset
            if state != STATE_READY
                if !finished?
                    raise StateError, "#reset can be called only on finished or invalid commands"
                end

                CORBA.refine_exceptions(self) do
                    do_reset
                end
                @state  = STATE_READY
            end
        end

        def self.state_predicate(name, with_negation)
            name = name.to_s
            mdef = <<-EOD
            def #{name}?
                if state >= STATE_#{name.upcase}
                    true
                elsif Command.state_auto_update? && update_state >= STATE_#{name.upcase}
                    true
            EOD
            if with_negation
                mdef << <<-EOD
                elsif state == STATE_NOT_#{name.upcase}
                    false
                end
                EOD
            else
                mdef << <<-EOD
                else
                    false
                end
                EOD
            end
            mdef << "end"
            class_eval mdef
        end

        state_predicate :sent, false
        state_predicate :accepted, true
        state_predicate :executed, false
        state_predicate :valid, true
        state_predicate :done, false

        STATE_IS_TERMINAL = []
        STATE_IS_TERMINAL[STATE_NOT_ACCEPTED] = true
        STATE_IS_TERMINAL[STATE_NOT_VALID] = true
        STATE_IS_TERMINAL[STATE_DONE] = true

        def self.terminal_state?(state); STATE_IS_TERMINAL[state] end

        def ready?; state == STATE_READY; end
        def running?
            if Command.terminal_state?(state)
                return false
            elsif state < STATE_SENT
                return false
            elsif Command.state_auto_update?
                !terminal_State?(update_state)
            else
                true
            end
        end
        def finished?
            Command.terminal_state?(state) ||
                (Command.state_auto_update? && Command.terminal_state?(update_state))
        end
        def successful?; valid? if finished? end
        def failed?;     !valid? if finished? end

        def update_state
            return state if state == STATE_READY || Command.terminal_state?(state)

            CORBA.refine_exceptions(self) do
                @state = do_state
            end
            state
        end
    end
end

