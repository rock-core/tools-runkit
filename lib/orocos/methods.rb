module Orocos
    # Base class for RTTMethod and Command
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
                if !(arg_type = Orocos.registry.get(type_name))
                    raise "cannot find type '#{type_name}' in the registry"
                end

                arguments_types << arg_type
            end
            @args_type_names = arguments_spec.map { |name, doc, type| type }
        end

        def common_call(args) # :nodoc:
            if args.size() != arguments_spec.size()
                raise ArgumentError, "not enough arguments"
            end

            filtered = []
            args.each_with_index do |v, i|
                if arguments_types[i].name == "/std/string"
                    filtered << v.to_str
                else
                    filtered << Typelib.from_ruby(v, arguments_types[i])
                end
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
                result = if !return_type.null?
                             return_type.new
                         end
                do_recall(result)
            end
        end

        # Calls the method with the provided arguments
        def call(*args)
            result = if return_type.null?
                     elsif return_type.name == "string" || return_type.name == "/std/string"
                         ""
                     elsif return_type.opaque?
                         raise ArgumentError, "I don't know how to handle #{return_type.name}"
                     else
                         return_type.new
                     end

            common_call(args) do |filtered|
                result = do_call(@args_type_names, filtered, result)
            end
            result
        end
    end

    # Represents a command, i.e. an asynchronous method call.
    class Command < Callable
        class StateError < RuntimeError; end

        # The last known command state
        #
        # Possible states are
        #   STATE_READY
        #   STATE_SENT
        #   STATE_ACCEPTED
        #   STATE_NOT_ACCEPTED
        #   STATE_VALID
        #   STATE_NOT_VALID
        #   STATE_DONE
        #
        # New commands start in the STATE_READY state.
        attr_reader :state

        def initialize
            super
            @state = STATE_READY
        end

        class << self
            # Set to true if state predicates should call Command#update_state
            # automatically.
            #
            # See the documentation of the state predicates and of #update_state
            # for more details.
            attr_writer :state_auto_update

            # True if state predicates should call Command#update_state
            # automatically.
            #
            # See the documentation of the state predicates and of #update_state
            # for more details.
            def state_auto_update?; @state_auto_update end
        end
        @state_auto_update = true

        # Recalls the same command with the same arguments as the last call to
        # #call. This is an optimization feature, as arguments are stored on the
        # remote component's side
        #
        # Raises StateError if that command is not in a READY state
        def recall
            if state != STATE_READY
                raise StateError, "the command is not ready. Call #reset first."
            end

            common_call(args) do |filtered|
                do_recall
                @state = STATE_SENT
            end
        end

        # Call the command with the given argument.
        #
        # If you need to repeatedly call the same command with the same
        # arguments, use #call once and then use #recall.
        #
        # Raises StateError if that command is not in a READY state
        def call(*args)
            if state != STATE_READY
                raise StateError, "the command is not ready. Call #reset first."
            end

            common_call(args) do |filtered|
                do_call(@args_type_names, filtered)
                @state = STATE_SENT
            end
        end

        # Transitions that command from the FINISHED state into the READY
        # state, so that #call or #recall can be used again.
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

        def self.state_predicate(name, with_negation) # :nodoc:
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

        ##
        # :method: sent?
        #
        # True if the command has been sent, i.e. #call has been used but the
        # command has not yet been accepted by the remote component.
        #
        # Note that you will usually want to use one of #ready?, #running?,
        # #finished?, #successful? and #failed?
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        state_predicate :sent, false

        ##
        # :method: accepted?
        #
        # True if the command has been accepted by the remote component, i.e. if
        # it is actually queued for execution.
        #
        # Note that you will usually want to use one of #ready?, #running?,
        # #finished?, #successful? and #failed?
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        state_predicate :accepted, true

        ##
        # :method: executed?
        #
        # True if the command's start method has been executed by the remote
        # component.
        #
        # Note that you will usually want to use one of #ready?, #running?,
        # #finished?, #successful? and #failed?
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        state_predicate :executed, false

        ##
        # :method: executed?
        #
        # True if the command's start method has been executed by the remote
        # component, and if that method returned true (i.e. the command's
        # parameters where valid).
        #
        # Note that you will usually want to use one of #ready?, #running?,
        # #finished?, #successful? and #failed?
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        state_predicate :valid, true

        ##
        # :method: done?
        #
        # True if the command execution is finished.
        #
        # Note that you will usually want to use one of #ready?, #running?,
        # #finished?, #successful? and #failed?
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        state_predicate :done, false

        STATE_IS_TERMINAL = []
        STATE_IS_TERMINAL[STATE_NOT_ACCEPTED] = true
        STATE_IS_TERMINAL[STATE_NOT_VALID] = true
        STATE_IS_TERMINAL[STATE_DONE] = true

        # True if the given state is terminal (i.e. represents the end of the
        # command execution)
        def self.terminal_state?(state); STATE_IS_TERMINAL[state] end

        # True if that command object can be used to start a new execution, i.e.
        # if #call and/or #recall can be used.
        def ready?; state == STATE_READY; end

        # True if that command is currently being executed
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
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

        # True if that command finished its execution
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        def finished?
            Command.terminal_state?(state) ||
                (Command.state_auto_update? && Command.terminal_state?(update_state))
        end

        # True if that command successfully finished its execution, i.e. if it
        # has been validated by the remote component.
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        def successful?; valid? if finished? end

        # True if that command failed, i.e. if it has been flagged as invalid by
        # the remote component.
        #
        # If Command.state_auto_update is true, then #update_state will be called
        # if needed. Otherwise, you will have to call it by yourself to update
        # the command's state.
        def failed?;     !valid? if finished? end

        # Calls the remote component to update the #state variable.
        #
        # Most state-reading predicates will call this method automatically if
        # Command.state_auto_update is true. This is described in the
        # documentation of these methods.
        def update_state
            return state if state == STATE_READY || Command.terminal_state?(state)

            CORBA.refine_exceptions(self) do
                @state = do_state
            end
            state
        end
    end
end

