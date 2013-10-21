
module Orocos::Async::Log
    class AttributeBase < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic
        self.default_period = 0.1

        define_events :change,:raw_change
        attr_reader :raw_last_sample

        def initialize(async_task,attribute,options=Hash.new)
            super(attribute.name,async_task.event_loop)
            @task = async_task
            @raw_last_sample = attribute.raw_read
            # do not queue reachable event no listeners are registered so far
            disable_emitting do 
                reachable!(attribute)
            end
            attribute.notify do
                @raw_last_sample = attribute.raw_read
                emit_raw_change @raw_last_sample
                emit_change Typelib.to_ruby(@raw_last_sample)
            end
        end

        def last_sample
            if @raw_last_sample
                Typelib.to_ruby(@raw_last_sample)
            end
        end

        def really_add_listener(listener)
            return super unless listener.use_last_value?

            if listener.event == :change && @raw_last_sample
                event_loop.once{listener.call(Typelib.to_ruby(@raw_last_sample))}
            elsif listener.event == :raw_change && @raw_last_sample
                event_loop.once{listener.call(@raw_last_sample)}
            end
            super
        end

        def type?
            true
        end

        private
        forward_to :@delegator_obj,:@event_loop,:on_error => :emit_error  do
            methods = Orocos::Log::Property.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= Orocos::Async::Log::AttributeBase.instance_methods
            methods << :type
            def_delegators methods
            end
        end

        class Property < AttributeBase
        end

        class Attribute < AttributeBase
        end
    end
