
module Orocos::Async::Log
    class OutputReader < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        attr_reader :policy
        define_event :data

        # @param [Async::OutputPort] port The Asyn::OutputPort
        # @param [Orocos::OutputReader] reader The designated reader
        def initialize(port,reader,options=Hash.new)
            super(port.name,port.event_loop)
            options = Kernel.validate_options options, :period => 0.1
            @port = port
            @period = options[:period]
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
            methods -= OutputReader.instance_methods
            def_delegators methods
        end
    end

    class OutputPort < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        define_event :data

        def initialize(async_task,port,options=Hash.new)
            super(port.name,async_task.event_loop)
            @policy = options
            @readers = Array.new
            reachable! port
            port.connect_to do |sample|
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

        def reader(options = Hash.new,&block)
            if block
                orig_reader(policy) do |reader|
                    block.call OutputReader.new(self,reader,options)
                end
            else
                OutputReader.new(self,orig_reader(policy),options)
            end
        end

        def on_data(policy = Hash.new,&block)
            on_event :data,&block
        end

        private
        forward_to :@delegator_obj,:@event_loop,:on_error => :emit_error do
            methods = Orocos::Log::OutputPort.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= OutputPort.instance_methods
            def_delegators methods
            def_delegator :reader, :alias => :orig_reader
            def_delegator :read, :alias => :orig_read
        end
    end
end
