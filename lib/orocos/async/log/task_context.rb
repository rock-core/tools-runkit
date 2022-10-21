# frozen_string_literal: true

module Orocos::Async
    module Log
        class TaskContext < Orocos::Async::ObjectBase
            extend Utilrb::EventLoop::Forwardable
            extend Orocos::Async::ObjectBase::Periodic::ClassMethods
            include Orocos::Async::ObjectBase::Periodic

            self.default_period = 1.0

            define_events :port_reachable,
                          :port_unreachable,
                          :property_reachable,
                          :property_unreachable,
                          :attribute_reachable,
                          :attribute_unreachable,
                          :state_change

            def initialize(log_task, options = {})
                @options ||= Kernel.validate_options options, raise: false, event_loop: Orocos::Async.event_loop, period: default_period
                super(log_task.name, @options[:event_loop])
                if log_task.has_port? "state"
                    log_task.port("state").on_data do |sample|
                        emit_state_change log_task.state
                    end
                end
                # do not queue reachable event no listeners are registered so far
                disable_emitting do
                    reachable!(log_task)
                end
                log_task.on_port_reachable do |name|
                    emit_port_reachable name
                end
                log_task.on_property_reachable do |name|
                    emit_property_reachable name
                end
                log_task.on_state_change do |val|
                    emit_state_change val
                end
            end

            # Creates a {RubyTasks::TaskContext} on which all logged values
            # should be mirrored
            #
            # It will create only one such task context, i.e. the method will
            # always return the same object
            #
            # @return [RubyTasks::TaskContext]
            def to_ruby
                @ruby_task_context ||= TaskContextBase.to_ruby(self)
            end

            # Checks whether this log task has a corresponding ruby task context
            #
            # @return [Boolean]
            # @see to_ruby
            def ruby_task_context?
                !!@ruby_task_context
            end

            def really_add_listener(listener)
                return super unless listener.use_last_value?

                # call new listeners with the current value
                # to prevent different behaviors depending on
                # the calling order
                if listener.event == :state_change
                    state = @delegator_obj.current_state
                    event_loop.once { listener.call state } if state
                elsif listener.event == :port_reachable
                    event_loop.once do
                        port_names.each do |name|
                            listener.call name if @delegator_obj.port(name).used?
                        end
                    end
                elsif listener.event == :property_reachable
                    event_loop.once do
                        property_names.each do |name|
                            listener.call name if @delegator_obj.property(name).used?
                        end
                    end
                elsif listener.event == :attribute_reachable
                    event_loop.once do
                        attribute_names.each do |name|
                            listener.call name if @delegator_obj.attribute(name).used?
                        end
                    end
                end
                super
            end

            def attribute(name, options = {}, &block)
                if block
                    orig_attribute(name) do |attr|
                        block.call Attribute.new(self, attr)
                    end
                else
                    Attribute.new(self, orig_attribute(name))
                end
            end

            def property(name, options = {}, &block)
                if block
                    orig_property(name) do |prop|
                        block.call Property.new(self, prop)
                    end
                else
                    Property.new(self, orig_property(name))
                end
            end

            def port(name, verify = true, options = {}, &block)
                if block
                    orig_port(name, verify) do |port|
                        block.call OutputPort.new(self, port)
                    end
                else
                    OutputPort.new(self, orig_port(name))
                end
            end

            def to_async(options = {})
                self
            end

            def to_proxy(options = {})
                options[:use] ||= self
                Orocos::Async.proxy(name, options).wait
            end

            # call-seq:
            #  task.each_property { |a| ... } => task
            #
            # Enumerates the properties that are available on
            # this task, as instances of Orocos::Attribute
            def each_property(&block)
                return enum_for(:each_property) unless block_given?

                names = property_names
                puts names
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
                return enum_for(:each_attribute) unless block_given?

                names = attribute_names
                names.each do |name|
                    yield(attribute(name))
                end
            end

            # call-seq:
            #  task.each_port { |p| ... } => task
            #
            # Enumerates the ports that are available on this task, as instances of
            # either Orocos::InputPort or Orocos::OutputPort
            def each_port(&block)
                return enum_for(:each_port) unless block_given?

                port_names.each do |name|
                    yield(port(name))
                end
                self
            end

            private

            # add methods which forward the call to the underlying task context
            forward_to :@delegator_obj, :@event_loop, on_error: :emit_error do
                def_delegator :port, alias: :orig_port
                def_delegator :property, alias: :orig_property
                def_delegator :attribute, alias: :orig_attribute

                methods = Orocos::Log::TaskContext.instance_methods.find_all { |method| (method.to_s =~ /^do.*/).nil? }
                methods -= Orocos::Async::Log::TaskContext.instance_methods + [:method_missing]
                methods << :type
                def_delegators methods
            end
        end
    end
end
