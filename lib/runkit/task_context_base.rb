# frozen_string_literal: true

require "runkit/ports_searchable"

module Runkit
    # Base implementation for task contexts
    class TaskContextBase
        include PortsSearchable

        # The underlying orogen model
        #
        # It may be partial
        #
        # @return [OroGen::Spec::TaskContext]
        attr_reader :model

        # @return [String] The IOR of this task context
        attr_reader :ior

        # @return [String] The full name of the task context
        attr_reader :name

        # @param [String] name The name of the task.
        # @param [Hash] options The options.
        # @option options [Runkit::Process] :process The process supporting the task
        # @option options [String] :namespace The namespace of the task
        def initialize(name, model:)
            @name = name
            @model = model
            initialize_model_info(model)
        end

        # call-seq:
        #  task.each_operation { |a| ... } => task
        #
        # Enumerates the operation that are available on
        # this task, as instances of Runkit::Operation
        def each_operation(&block)
            return enum_for(:each_operation) unless block_given?

            names = operation_names
            names.each do |name|
                yield(operation(name))
            end
        end

        # call-seq:
        #  task.each_property { |a| ... } => task
        #
        # Enumerates the properties that are available on
        # this task, as instances of Runkit::Attribute
        def each_property
            return enum_for(:each_property) unless block_given?

            names = property_names
            names.each do |name|
                yield(property(name))
            end
        end

        # call-seq:
        #  task.each_attribute { |a| ... } => task
        #
        # Enumerates the attributes that are available on
        # this task, as instances of Runkit::Attribute
        def each_attribute(&block)
            return enum_for(:each_attribute) unless block_given?

            names = attribute_names
            names.each do |name|
                yield(attribute(name))
            end
        end

        # Enumerates the ports that are available on this task, as instances of
        # either Runkit::InputPort or Runkit::OutputPort
        #
        # @yieldparam [InputPort,OutputPort] port
        def each_port
            return enum_for(:each_port) unless block_given?

            port_names.each do |name|
                yield port(name)
            end
            self
        end

        # Returns true if +name+ is the name of a attribute on this task context
        def attribute?(name)
            attribute_names.include?(name.to_str)
        end

        # Returns true if this task context has either a property or an attribute with the given name
        def property?(name)
            property_names.include?(name.to_str)
        end

        # Returns true if this task context has a command with the given name
        def operation?(name)
            operation_names.include?(name.to_str)
        end

        # Returns true if this task context has a port with the given name
        def port?(name)
            port_names.include?(name.to_str)
        end

        # Returns true if a documentation about the task is available
        # otherwise it returns false
        def doc?
            (doc && !doc.empty?)
        end

        # True if the given symbol is the name of a runtime state
        def runtime_state?(sym)
            @runtime_states.include?(sym)
        end

        # True if the given symbol is the name of an error state
        def error_state?(sym)
            @error_states.include?(sym)
        end

        # True if the given symbol is the name of an exception state
        def exception_state?(sym)
            @exception_states.include?(sym)
        end

        # True if the given symbol is the name of a fatal error state
        def fatal_error_state?(sym)
            @fatal_states.include?(sym)
        end

        def input_port(name)
            p = port(name)
            unless p.respond_to?(:writer)
                raise InterfaceObjectNotFound.new(self, name),
                      "#{name} is an output port of #{self.name}, "\
                      "was expecting an input port"
            end

            p
        end

        def output_port(name)
            p = port(name)
            unless p.respond_to?(:reader)
                raise InterfaceObjectNotFound.new(self, name),
                      "#{name} is an input port of #{self.name}, "\
                      "was expecting an output port"
            end

            p
        end

        # Returns an array of all the ports defined on this task context
        def ports
            each_port.to_a
        end

        # call-seq:
        #  task.each_input_port { |p| ... } => task
        #
        # Enumerates the input ports that are available on this task, as
        # instances of Runkit::InputPort
        def each_input_port
            each_port do |p|
                yield(p) if p.respond_to?(:writer)
            end
        end

        # call-seq:
        #  task.each_output_port { |p| ... } => task
        #
        # Enumerates the input ports that are available on this task, as
        # instances of Runkit::OutputPort
        def each_output_port
            each_port do |p|
                yield(p) if p.respond_to?(:reader)
            end
        end

        # Returns true if the remote task context can still be reached through
        # and false otherwise.
        def reachable?
            ping
            true
        rescue Runkit::ComError
            false
        end

        def to_s
            "#<TaskContextBase: #{self.class.name}/#{name}>"
        end

        def inspect
            "#<#{self.class}: #{self.class.name}/#{name}>"
        end

        # @return [Symbol] the toplevel state that corresponds to +state+, i.e.
        #   the value returned by #rtt_state when #state returns 'state'
        def toplevel_state(state)
            if exception_state?(state) then :EXCEPTION
            elsif fatal_state?(state) then :FATAL_ERROR
            elsif error_state?(state) then :RUNTIME_ERROR
            elsif runtime_state?(state) then :RUNNING
            else state
            end
        end

        def add_default_states
            @error_states   << :RUNTIME_ERROR << :FATAL_ERROR << :EXCEPTION
            @runtime_states << :RUNNING << :RUNTIME_ERROR
            @exception_states << :EXCEPTION
            @fatal_states     << :FATAL_ERROR
        end

        # load all informations from the model
        def initialize_model_info(model)
            @state_symbols = model.each_state.map { |name, type| name.to_sym }
            @error_states  =
                model
                .each_state
                .map { |name, type| name.to_sym if %I[error exception fatal].include?(type) }
                .compact.to_set

            @exception_states =
                model
                .each_state
                .map { |name, type| name.to_sym if type == :exception }
                .compact.to_set

            @runtime_states =
                model
                .each_state
                .map { |name, type| name.to_sym if %I[error runtime].include?(type) }
                .compact.to_set

            @fatal_states =
                model
                .each_state
                .map { |name, type| name.to_sym if type == :fatal }
                .compact.to_set

            add_default_states
        end

        def pretty_print(pp) # :nodoc:
            pp.text "Component #{name}"
            pp.breakable

            [["attributes", each_attribute], ["properties", each_property]].each do |kind, enum|
                pp.breakable
                objects = enum.to_a
                if objects.empty?
                    pp.text "No #{kind}"
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
                end
            end

            ports = each_port.to_a
            pp.breakable
            if ports.empty?
                pp.text "No ports"
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
            end
        end

        def method_missing(m, *args) # :nodoc:
            m = m.to_s
            if m =~ /^(\w+)=/
                name = $1
                begin
                    return property(name).write(*args)
                rescue Runkit::NotFound
                end

            elsif port?(m)
                raise ArgumentError, "expected zero arguments for #{m}, got #{args.size}" unless args.empty?

                return port(m)
            elsif operation?(m)
                return operation(m).callop(*args)
            elsif property?(m) || attribute?(m)
                raise ArgumentError, "expected zero arguments for #{m}, got #{args.size}" unless args.empty?

                prop = if property?(m) then property(m)
                       else attribute(m)
                       end
                value = prop.read
                if block_given?
                    yield(value)
                    prop.write(value)
                end
                return value
            end

            super(m.to_sym, *args)
        end

        def to_h
            Hash[
                name: name,
                model: model.to_h,
                state: state
            ]
        end

        # This methods must be implemented by
        # the child class of TaskContextBase
        module PureVirtual
            # Returns an object that represents the given port on the task
            # context. The returned object is either an InputPort or an OutputPort
            def port(_name)
                raise Runkit::NotFound, "#port is not implemented in #{self.class}"
            end

            # Returns an Attribute object representing the given attribute
            def attribute(_name)
                raise Runkit::NotFound, "#attribute is not implemented in #{self.class}"
            end

            # Returns a Property object representing the given property
            def property(_name)
                raise Runkit::NotFound, "#property is not implemented in #{self.class}"
            end

            # Returns an Operation object that represents the given method on the
            # remote component.
            def operation(_name)
                raise Runkit::NotFound, "#operation is not implemented in #{self.class}"
            end

            # Returns the array of the names of available properties on this task
            # context
            def property_names
                raise NotImplementedError
            end

            # Returns the array of the names of available attributes on this task
            # context
            def attribute_names
                raise NotImplementedError
            end

            # Returns the array of the names of available operations on this task
            # context
            def operation_names
                raise NotImplementedError
            end

            # Returns the names of all the ports defined on this task context
            def port_names
                raise NotImplementedError
            end

            # Reads the state
            def rtt_state
                raise NotImplementedError
            end

            # raises an runtime error if the task is not
            # reachable
            def ping
                raise NotImplementedError
            end
        end
        include PureVirtual
    end
end
