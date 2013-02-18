
module Orocos::Async::Log
    class OutputReader < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic

        self.default_period = 0.1

        attr_reader :policy
        define_event :data

        # @param [Async::OutputPort] port The Asyn::OutputPort
        # @param [Orocos::OutputReader] reader The designated reader
        def initialize(port,reader,options=Hash.new)
            super(port.name,port.event_loop)
            @options = Kernel.validate_options options, :period => default_period
            @port = port
            reachable! reader
            @port.connect_to do |sample|
                emit_data sample
            end
        end

        def add_listener(listener)
            if listener.event == :data
                sample = @delegator_obj.read
                if sample
                    event_loop.once do
                        listener.call sample
                    end
                end
            end
            super
        end

        private
        forward_to :@delegator_obj,:@event_loop,:on_error => :emit_error  do
            methods = Orocos::Log::OutputReader.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= Orocos::Async::Log::OutputReader.instance_methods
            def_delegators methods
        end
    end

    class OutputPort < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        define_event :data

        def initialize(async_task,port,options=Hash.new)
            @opitons ||= options
            @readers ||= Array.new
            super(port.name,async_task.event_loop)
            reachable! port
            port.connect_to do |sample|
                emit_data sample
            end
        end

        def type?
            true
        end

        def add_listener(listener)
            if listener.event == :data
                sample = @delegator_obj.read
                if sample
                    event_loop.once do
                        listener.call sample
                    end
                end
            end
            super
        end

        def reader(options = Hash.new,&block)
            if block
                orig_reader(policy) do |reader|
                    block.call OutputReader.new(self,reader,options)
                end
            else
                OutputReader.new(self,orig_reader(policy),options)
            end
        end

        def period
            if @options.has_key?(:period)
                @options[:period]
            else
                OutputReader.default_period
            end
        end

        def period=(value)
            @options[:period] = value
        end

        def on_data(policy = Hash.new,&block)
            @options = if policy.empty?
                           @options
                       elsif @options.empty? && !@global_reader
                           policy
                       elsif @options == policy
                           @options
                       else
                           Orocos.warn "Log::OutputPort #{full_name} cannot emit :data with different policies."
                           Orocos.warn "The current policy is: #{@options}."
                           Orocos.warn "Ignoring policy: #{policy}."
                           @options
                       end
            on_event :data,&block
        end

        private
        forward_to :@delegator_obj,:@event_loop,:on_error => :emit_error do
            methods = Orocos::Log::OutputPort.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= Orocos::Async::Log::OutputPort.instance_methods
            def_delegators methods
            def_delegator :reader, :alias => :orig_reader
            def_delegator :read, :alias => :orig_read
        end
    end
end
