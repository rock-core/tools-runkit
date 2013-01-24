
module Orocos::Async
    module Log
        class TaskContext < Orocos::Async::ObjectBase
            extend Utilrb::EventLoop::Forwardable
            define_events :port_reachable,
                :port_unreachable,
                :property_reachable,
                :property_unreachable,
                :attribute_reachable,
                :attribute_unreachable,
                :state_change

            def initialize(log_task,options=Hash.new)
                options = Kernel.validate_options options,:raise => false,:event_loop => Orocos::Async.event_loop
                super(log_task.name,options[:event_loop])
                if log_task.has_port? "state"
                    log_task.port("state").connect_to do |sample|
                        emit_state_change log_task.state
                    end
                end
                reachable!(log_task)
            end

            def add_listener(listener)
                # call new listeners with the current value
                # to prevent different behaviors depending on
                # the calling order
                if listener.event == :state_change
                    state = @delegator_obj.current_state
                    event_loop.once{listener.call state} if state
                elsif listener.event == :port_reachable
                    event_loop.once do 
                        port_names.each do |name|
                            listener.call name
                        end
                    end
                elsif listener.event == :property_reachable
                    event_loop.once do
                        property_names.each do |name|
                            listener.call name
                        end
                    end
                elsif listener.event == :attribute_reachable
                    event_loop.once do
                        attribute_names.each do |name|
                            listener.call name
                        end
                    end
                end
                super
            end

            def attribute(name,&block)
                if block
                    orig_attribute(name) do |attr|
                        block.call Attribute.new(self,attr)
                    end
                else
                    Attribute.new(self,orig_attribute(name))
                end
            end

            def property(name,&block)
                if block
                    orig_property(name) do |prop|
                        block.call Property.new(self,prop)
                    end
                else
                    Property.new(self,orig_property(name))
                end
            end

            def port(name, verify = true, &block)
                if block
                    orig_port(name,verify) do |port|
                        block.call OutputPort.new(self,port)
                    end
                else
                    OutputPort.new(self,orig_port(name))
                end
            end

            private
            # add methods which forward the call to the underlying task context
            forward_to :@delegator_obj,:@event_loop,:on_error => :emit_error do
                def_delegator :port, :alias => :orig_port
                def_delegator :property, :alias => :orig_property
                def_delegator :attribute, :alias => :orig_attribute

                methods = Orocos::Log::TaskContext.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
                methods -= TaskContext.instance_methods + [:method_missing]
                def_delegators methods
            end
        end
    end
end

