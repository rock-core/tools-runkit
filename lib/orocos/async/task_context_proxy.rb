module Orocos::Async
    class TaskContextProxy
        extend Utilrb::EventLoop::Forwardable

        def initialize(name,options=Hash.new)
            options,@task_options = Kernel.filter_options options,{:name_service => Orocos::Async.name_service,
                                                       :event_loop => Orocos::Async.event_loop,
                                                       :reconnect => true,
                                                       :retry_period => 1.0,
                                                       :use => nil,
                                                       :raise => false}

            @name = name
            @name_service = options[:name_service]
            @event_loop = options[:event_loop]
            @retry_period = options[:retry_period]
            @reconnect = options[:reconnect]
            @raise = options[:raise]

            @callblocks = Hash.new{ |hash,key| hash[key] = []}
            @task_context = options[:use]
            @resolve_task = nil

            @task_options[:event_loop] = @event_loop

            on_disconnected do
                connect if @reconnect
            end

            if @task_context
                event :on_connected
            else
                connect
            end
        end

        def connect(wait = false)
            if !@resolve_task
                event :on_connect
                @resolve_task = @name_service.get @name,@task_options do |task_context,error|
                    if error
                        raise error if @raise
                        t = [0,@retry_period - (Time.now - @resolve_task.started_at)].max
                        @event_loop.once(t) do
                            @event_loop.add_task @resolve_task
                        end
                    else
                        event :on_reconnected if @task_context
                        @task_context = task_context
                        @resolve_task = nil
                        register_callbacks(@task_context)
                    end
                end
            end
        end

        def event(name,*args)
            @callblocks[name].each do |block|
                block.call *args
            end
        end

        def on_connected(&block)
            @callblocks[:on_connected] << block
        end

        def on_connect(&block)
            @callblocks[:on_connect] << block
        end

        def on_reconnected(&block)
            @callblocks[:on_reconnected] << block
        end

        def on_disconnected(&block)
            @callblocks[:on_disconnected] << block
        end

        def on_error(&block)
            @callblocks[:on_error] << block
        end

        def on_state_changed(&block)
            @callblocks[:on_state_changed] << block
        end

        def port
        end

        def property
        end

        def operation
        end

        def reachable?(&block)
            orig_reachable? &block
        rescue Orocos::NotFound
            false
        end

        private
        # add methods which forward the call to the underlying task context
        forward_to :__task_context,:@event_loop do
            methods = Orocos::TaskContext.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= TaskContextProxy.instance_methods + [:method_missing]
            def_delegators methods
            def_delegator :reachable?,:alias => :orig_reachable?
        end

        def register_callbacks(task)
            task.on_connected do
                event :on_connected
            end
            task.on_disconnected do
                event :on_disconnected
            end
            task.on_error do
                event :on_error
            end
            task.on_state_changed do |state|
                event :on_state_changed,state
            end
        end

        def __task_context
            task = @task_context
            if task
                task
            else
                raise Orocos::NotFound,"TaskContext #{@name} is not reachable - still trying by using the following name service #{@name_service}"
            end
        end
    end

    class PortProxy
    end

    class ReaderProxy
    end

    class WriterProxy
    end

    class PropertyProxy
    end

    class OperationProxy
    end
end
