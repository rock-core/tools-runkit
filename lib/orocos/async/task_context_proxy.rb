require 'forwardable'

module Orocos::Async

    # Place holder class for the designated object
    class PlaceHolderObject
        def initialize(name,event_loop,type)
            @name = name
            @event_loop = event_loop
            @type = type
        end

        def reset_callbacks
        end

        def disconnect
        end

        def method_missing(m,*args,&block)
            error = raise Orocos::NotFound.new "#{@type} #{@name} is not reachable while accessing #{m}"
            if !block
                raise error
            else
                t = Utilrb::ThreadPool::Task.new do
                    raise error
                end
                task.execute
                if block.arity == 2
                    block.call nil,error
                end
                @event_loop.handle_error(error)
                # fake a task which raises an error
                task
            end
        end
    end

    class PortProxy < ObjectBase
        extend Forwardable
        attr_reader :policy
        methods = Orocos::Port.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= PortProxy.instance_methods + [:method_missing,:name]
        methods << :disconnect
        def_delegators :@port,*methods
        
        def initialize(task_proxy,port_name,policy=Hash.new)
            options,policy = Kernel.filter_options policy, :type_name => nil
            super()
            @type_name = options[:type_name]
            @policy = policy
            @task_proxy = task_proxy
            @port_name = port_name
            @event_loop = task_proxy.event_loop
            @port = PlaceHolderObject.new(@port_name,@event_loop,"Port")
            def @port.type_name
                raise ArgumentError,"PortProxy #{@name}: Cannot determine the type name of the port sample because there is no connection at this stage. Use the option :type_name to give a hint."
            end
        end

        def name
            @port_name
        end

        def type_name
            if @type_name
                @type_name
            else
                @port.type_name
            end
        end

        def designated_port=(port)
            @port.reset_callbacks
            @port = port

            port.on_error do |error|
                event :on_error,error
            end

            #check which port we have
            if port.respond_to? :reader
                port.on_data @policy do |data|
                    event :on_data, data
                end
            else
                if !@callbacks[:on_data].empty?
                    raise ArgumentError, "Port #{name} is an input port but callbacks for on_data are registered" 
                end
            end
        end

        def on_data(policy = Hash.new,&block)
            @policy.merge! policy
            if !@port.is_a?(Orocos::Async::PlaceHolderObject) && !@port.respond_to?(:reader)
                raise ArgumentError, "Port #{name} is an input port."
            end
            @callbacks[:on_data] << block
        end
    end

    class TaskContextProxy < ObjectBase
        attr_reader :name_service
        include Orocos::Namespace

        # forward methods to designated object
        extend Forwardable
        methods = Orocos::TaskContext.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= TaskContextProxy.instance_methods + [:method_missing,:reachable?,:port]
        def_delegators :@task_context,*methods

        def initialize(name,options=Hash.new)
            super()
            @options,@task_options = Kernel.filter_options options,{:name_service => Orocos::Async.name_service,
                                                       :event_loop => Orocos::Async.event_loop,
                                                       :reconnect => true,
                                                       :retry_period => 1.0,
                                                       :use => nil,
                                                       :raise => false,
                                                       :wait => nil }
            @name = name
            @name_service = @options[:name_service]
            @event_loop = @options[:event_loop]
            @task_context = @options[:use]
            register_callbacks(@task_context) if options[:use]
            @task_context ||= PlaceHolderObject.new(@name,@event_loop,"TaskContext")
            @resolve_task = nil
            @task_options[:event_loop] = @event_loop
            @mutex = Mutex.new
            @ports = Hash.new

            on_unreachable do
                disconnect_ports
                connect if @options[:reconnect]
            end

            if !@task_context.is_a? PlaceHolderObject
                event :on_reachable
            else
                connect
            end
            wait if @options[:wait]
        end

        def name
            map_to_namespace(@name)
        end

        def basename
            @name
        end

        def connect()
            if !@resolve_task
                event :on_connect
                @resolve_task = @name_service.get @name,@task_options do |task_context,error|
                    if error
                        raise error if @options[:raise]
                        t = [0,@options[:retry_period] - (Time.now - @resolve_task.started_at)].max
                        @event_loop.once(t) do
                            @event_loop.add_task @resolve_task
                        end
                    else
                        ports = @mutex.synchronize do
                            @resolve_task = nil
                            @task_context.reset_callbacks
                            @task_context = task_context
                            @ports.values
                        end
                        ports.each do |port|
                            connect_port(port)
                        end
                        register_callbacks(task_context)
                    end
                end
            end
        end

        def on_reachable(&block)
            @callbacks[:on_reachable] << block
        end

        def on_connect(&block)
            @callbacks[:on_connect] << block
        end

        def on_unreachable(&block)
            @callbacks[:on_unreachable] << block
        end

        def on_state_change(&block)
            @callbacks[:on_state_change] << block
        end

        def port(name,options = Hash.new)
            options,other_options = Kernel.filter_options options,:wait => @options[:wait]
            wait if options[:wait]
            @mutex.synchronize do 
                if @ports.has_key?(name)
                    @ports[name]
                else
                    p = @ports[name] = PortProxy.new(self,name,other_options)
                    if options[:wait]
                        p.designated_port = @task_context.port(name)
                    else
                        @event_loop.defer :known_errors => Orocos::NotFound do
                            connect_port(p)
                        end
                    end
                    p
                end
            end
        end

        # blocks until the task gets reachable
        def wait
            @event_loop.wait_for do
                reachable?
            end
        end

        def reachable?(&block)
            @task_context.reachable?(&block)
        rescue Orocos::NotFound
            false
        end

        private
        def register_callbacks(task)
            task.on_reachable do
                event :on_reachable
            end
            task.on_unreachable do
                event :on_unreachable
            end
            task.on_error do |e|
                event :on_error, e
            end
            task.on_state_change do |state|
                event :on_state_change,state
            end
        end

        # blocking call shoud be called from a different thread
        def connect_port(port)
            p = @mutex.synchronize do 
                    @task_context.port(port.name)
            end
            @event_loop.call do
                port.designated_port = p
            end
        end

        def disconnect_ports
            ports = @mutex.synchronize do 
                @ports.values
            end
            ports.each(&:disconnect)
        end

    end
end
