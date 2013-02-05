
module Orocos::Async::CORBA
    class AttributeBase < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic

        define_event :change
        attr_reader :last_sample

        def initialize(async_task,attribute,options=Hash.new)
            super(attribute.name,async_task.event_loop)
            @options = Kernel.validate_options options, :period => default_period
            @task = async_task
            @mutex = Mutex.new

            reachable!(attribute) if attribute
            @poll_timer = @event_loop.async_every(@delegator_obj.method(:read), {:period => period, :start => false,:sync_key => @delegator_obj,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError,Orocos::TypekitTypeNotFound]}) do |data,error|
                if error
                    @poll_timer.cancel
                    self.period = @poll_timer.period
                    @event_loop.once do
                        event :error,error
                    end
                else
                    if number_of_listeners(:change) == 0
                        @poll_timer.cancel
                    elsif data
                        if @last_sample != data
                            @last_sample = data
                            event :change,data
                        end
                    end
                end
            end
            @poll_timer.doc = attribute.full_name
        end

        def unreachable!(options = Hash.new)
            @mutex.synchronize do
                super
                @last_sample = nil
            end
            @poll_timer.cancel
        end

        def reachable!(attribute,options = Hash.new)
            @mutex.synchronize do
                super
                @last_sample = nil
            end
            if number_of_listeners(:change) != 0
                @poll_timer.start 0
            end
        end

        def reachable?
            super && @last_sample
        end

        def period=(period)
            super
            @poll_timer.period = self.period
        end

        def add_listener(listener)
            @poll_timer.start(period) if listener.event == :change && !@poll_timer.running?
            if @last_sample
                event_loop.once{listener.call(@last_sample)}
            end
            super
        end

        private
        forward_to :attribute,:@event_loop,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError,Orocos::TypekitTypeNotFound],:on_error => :connection_error  do
            methods = Orocos::AttributeBase.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= Orocos::Async::CORBA::AttributeBase.instance_methods
            def_delegators methods
        end

        def connection_error(error)
            unreachable!(:error => error)
            emit_error error
        end

        def attribute
            @mutex.synchronize do
                if !valid_delegator?
                    error = Orocos::NotFound.new "#{self.class.name} #{name} is not reachable"
                    [nil,error]
                else
                    @delegator_obj
                end
            end
        end
    end

    class Property < AttributeBase
        self.default_period = 1.0
    end

    class Attribute < AttributeBase
        self.default_period = 1.0
    end
end
