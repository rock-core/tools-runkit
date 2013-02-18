
module Orocos::Async::Log
    class AttributeBase < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic
        self.default_period = 0.1

        define_event :change
        attr_reader :last_sample

        def initialize(async_task,attribute,options=Hash.new)
            super(attribute.name,async_task.event_loop)
            @task = async_task
            reachable!(attribute)
            attribute.notify do
                @last_sample = attribute.read
                emit_change @last_sample
            end
        end

        def add_listener(listener)
            if @last_sample
                event_loop.once{listener.call(@last_sample)}
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
            def_delegators methods
        end
    end

    class Property < AttributeBase
    end

    class Attribute < AttributeBase
    end
end
