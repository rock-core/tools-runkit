
module Orocos::Async::CORBA
    class OutputReader < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable

        # @param [Async::OutputPort] port The Asyn::OutputPort
        # @param [Orocos::OutputReader] reader The designated reader
        def initialize(port,reader,options=Hash.new)
            super(port.name)
            options,policy = Kernel.validate_options options, :period => 0.1
            @event_loop = port.event_loop
            @port = port
            @reader = reader

            @period = options[:period]
            @last_sample = @reader.new_sample
            p = proc do 
                sample = @reader.read_new(@last_sample)
            end
            @poll_timer = @event_loop.async_every(p, {:period => @period, :start => false,:sync_key => @reader,:known_errors => Orocos::CORBA::ComError}) do |data,error|
                if error
                    @poll_timer.cancel
                    @event_loop.once do 
                        event :on_error,error
                    end
                else
                    if @callbacks[:on_data].empty? 
                        @poll_timer.cancel
                    elsif data
                        event :on_data,data
                    end
                end
            end
            on_error do |e|
                disconnect
            end
        end

        # TODO keep timer and remote connection in mind
        def disconnect
            @poll_timer.cancel
        end

        def period=(period)
            @poll_timer.period = period
        end

        def on_data(&block)
            @callbacks[:on_data] << block
            @poll_timer.start(@period)
            block
            self
        end

        private
        forward_to :@reader,:@event_loop,:known_errors => Orocos::CORBA::ComError,:on_error => :__on_error  do
            methods = Orocos::OutputReader.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= OutputReader.instance_methods
            def_delegators methods
        end
    end

    class InputWriter < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable

        def initialize(port,writer,options=Hash.new)
            super(port.name)
            @event_loop = port.event_loop
            @port = port
            @writer = writer
        end

        private
        forward_to :@writer,:@event_loop,:known_errors => Orocos::CORBA::ComError,:on_error => :__on_error  do
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

        def connect(port)
            @mutex.synchronize do 
                @__port = port
            end
        end

        def disconnect
            connect(nil)
        end

        def valid?
            @mutex.synchronize do 
                !!@__port
            end
        end

        protected
        def initialize(async_task,port,options=Hash.new)
            super(port.name)
            raise ArgumentError, "no task is given" unless async_task
            raise ArgumentError, "no port is given" unless port 
            @task = async_task
            @event_loop = task.event_loop
            @mutex = Mutex.new
            @callblocks = Hash.new{ |hash,key| hash[key] = []}

            connect(port)
        end

        def __port
            @mutex.synchronize do 
                if !@__port
                    error = Orocos::NotFound.new "Port #{name} is not reachable"
                    [nil,error]
                else
                    @__port
                end
            end
        end

        def __on_error(e)
            @mutex.synchronize do 
                @__port = nil
            end
            super
        end
    end

    class OutputPort < Port
        def reader(options = Hash.new,&block)
            options, policy = Kernel.filter_options options, :period => nil
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
            @global_reader ||= reader(policy) do |reader|
                reader.on_data do |data|
                    event :on_data,data
                end
                @global_reader = reader # overwrites @global_reader before that it is a ThreadPool::Task
            end
            @callbacks[:on_data] << block
        end

        def period=(period)
            @global_reader.period = period if @global_reader
        end

        def disconnect
            @global_reader.disconnect if @global_reader
            super
        end

        forward_to :__port,:@event_loop,:known_errors => Orocos::CORBA::ComError,:on_error => :__on_error  do
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

        forward_to :__port,:@event_loop,:known_errors => Orocos::CORBA::ComError,:on_error => :__on_error  do
            methods = Orocos::InputPort.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= InputPort.instance_methods
            def_delegators methods
            def_delegator :writer, :alias => :orig_writer
        end
    end
end
