
module Orocos::Async::CORBA
    class OutputReader < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        define_event :data
        attr_reader :policy

        # @param [Async::OutputPort] port The Asyn::OutputPort
        # @param [Orocos::OutputReader] reader The designated reader
        def initialize(port,reader,options=Hash.new)
            super(port.name,port.event_loop)
            options = Kernel.validate_options options, :period => 0.1
            @port = port
            @last_sample = nil
            @period = options[:period]
            reachable! reader
            proxy_event @port,:unreachable
            
            @poll_timer = @event_loop.async_every(@delegator_obj.method(:read_new), {:period => @period, :start => false,:sync_key => @delegator_obj,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError]}) do |data,error|
                @poll_timer.period = @period if @poll_timer.period <= 0
                if error
                    @poll_timer.cancel
                    @event_loop.once do
                        event :error,error
                    end
                else
                    @last_sample = data
                    if number_of_listeners(:data) == 0
                        # TODO call reader.disable
                        @poll_timer.cancel
                    elsif data
                        event :data,data
                    end
                end
            end
            @poll_timer.doc = port.full_name
        end

        # TODO keep timer and remote connection in mind
        def unreachable!(options = Hash.new)
            @poll_timer.cancel
            @last_sample = nil
            begin
                @delegator_obj.disconnect if valid_delegator?
            rescue Orocos::CORBAError,Orocos::CORBA::ComError
            end
            super
        end

        def reachable?
            super && @port.reachable?
        end

        def reachable!(reader,options = Hash.new)
            super
            if number_of_listeners(:data) != 0
                @poll_timer.start 0
            end
        end

        def period=(period)
            @period = period
            @poll_timer.period = period
        end

        def add_listener(listener)
            if listener.event == :data
                @period = @poll_timer.period
                @poll_timer.start(0)
            end
            super
        end

        private
        forward_to :@delegator_obj,:@event_loop,:known_errors => [Orocos::CORBA::ComError,Orocos::CORBAError],:on_error => :emit_error  do
            methods = Orocos::OutputReader.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= OutputReader.instance_methods
            def_delegators methods
        end
    end

    class InputWriter < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable

        def initialize(port,writer,options=Hash.new)
            super(port.name,port.event_loop)
            @port = port
            @task.on_unrechable do
                unreachable!
            end
            reachable!(writer)
        end

        def unreachable!(options = Hash.new)
            @delegator_obj.disconnect if validate_options?
            super
        end

        private
        forward_to :@delegator_obj,:@event_loop,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError],:on_error => :emit_error  do
            methods = Orocos::InputWriter.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= InputWriter.instance_methods
            def_delegators methods
        end
    end

    class Port < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable

        def task
            @task
        end

        def reachable!(port,options = Hash.new)
            @mutex.synchronize do
                super
            end
        end

        def unreachable!(options = Hash.new)
            @mutex.synchronize do
                super
            end
        end

        def reachabel?
            super && @task.reachable?
        end

        protected

        def initialize(async_task,port,options=Hash.new)
            raise ArgumentError, "no task is given" unless async_task
            raise ArgumentError, "no port is given" unless port
            super(port.name,async_task.event_loop)
            @task = async_task
            @mutex = Mutex.new
            @task.on_unreachable do
                unreachable!
            end
            reachable!(port,options)
        end

        def connection_error(error)
            emit_error error
        end

        def port
            @mutex.synchronize do 
                if !valid_delegator?
                    error = Orocos::NotFound.new "Port #{name} is not reachable"
                    [nil,error]
                else
                    @delegator_obj
                end
            end
        end
    end

    class OutputPort < Port
        define_event :data

        def initialize(async_task,port,options=Hash.new)
            super
            @policy = options
            @readers = Array.new
        end

        def reader(options = Hash.new,&block)
            options, policy = Kernel.filter_options options, :period => nil
            policy[:pull] = true unless policy.has_key?(:pull)
            if block
                orig_reader(policy) do |reader,error|
                    reader = OutputReader.new(self,reader,options) unless error
                    if block.arity == 2
                        block.call(reader,error)
                    elsif !error
                        block.call(reader)
                    end
                end
            else
                OutputReader.new(self,orig_reader(policy),options)
            end
        end

        # TODO if called multiple times check policy
        def on_data(policy = Hash.new,&block)
            @policy = policy
            on_event :data,&block
        end

        def add_listener(listener)
            if listener.event == :data
                @global_reader ||= reader(@policy) do |reader|
                    proxy_event(reader,:data)
                    @global_reader = reader # overwrites @global_reader before that it is a ThreadPool::Task
                end
            end
            super
        end

        def period=(period)
            @global_reader.period = period if @global_reader
        end

        def unreachable!(options = Hash.new)
            @global_reader.unreachable! if @global_reader
            super
        end

        def reachable!(port,options = Hash.new)
            super
            if @global_reader
                orig_reader(@policy) do |reader,error|
                    unless error
                        @global_reader.reachable!(reader)
                    end
                end
            end
        end

        forward_to :port,:@event_loop,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError],:on_error => :connection_error do
            methods = Orocos::OutputPort.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= OutputPort.instance_methods
            def_delegators methods
            def_delegator :reader, :alias => :orig_reader
            def_delegator :read, :alias => :orig_read
        end
    end

    class InputPort < Port
        def writer(options = Hash.new,&block)
            if block
                orig_writer(options) do |writer,error|
                    writer = InputWriter.new(self,writer) unless error
                    if block.arity == 2
                        block.call(writer,error)
                    elsif !error
                        block.call(writer)
                    end
                end
            else
                InputWriter.new(self,orig_writer(options))
            end
        end

        forward_to :port,:@event_loop,:known_errors => [Orocos::CORBAError,Orocos::CORBA::ComError],:on_error => :connection_error  do
            methods = Orocos::InputPort.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= InputPort.instance_methods
            def_delegators methods
            def_delegator :writer, :alias => :orig_writer
        end
    end
end
