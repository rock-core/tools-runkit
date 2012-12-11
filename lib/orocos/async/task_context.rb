
module Orocos::Async::CORBA
    class TaskContext < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable

        # A TaskContext
        #
        # If not specified the default option settings are:
        #       :event_loop => Async.event_loop
        #       :raise => false
        #       :watchdog => true
        #       :period => 1.0
        #
        # @param [String,#ior] ior The ior of the task or a task context.
        # @param [Hash] options The options.
        # @option options [String] :name The name of the task.
        # @option options [Utilrb::EventLoop] :event_loop The event loop.
        # @option options [String] :ior The IOR
        # @option options [Boolean] :raise Raises an Orocos::NotFound error if the remote task is
        #       unreachable or went offline. Otherwise tries to reconnect and silently ignores method calls on
        #       the remote task object as long as the task is unreachable.
        # @option options [Boolean] :watchdog Checks the state of the tasks and if it is reachable.
        # @option options [Float] :period The period of the watchdog in seconds.
        # @option options [Orocos::TaskContext] :use Use the given task as designated object. After this any other other code
        #       path is not allowed to use the given task otherwise there might be multi threading problems. Furthermore
        #       it is assumed that the given task is reachable.
        # @overload initialize(options)
        # @overload initialize(task,options)
        #       @option options [#ior,#name] :task a task context.
        def initialize(ior,options=Hash.new)
            super(ior)
            ior,options = if ior.is_a? Hash
                              [nil,ior]
                          else
                              [ior,options]
                          end
            options,options_other = Kernel.filter_options options,:raise => false,:event_loop => Orocos::Async.event_loop
            @event_loop = options[:event_loop]
            @raise = options[:raise]
            @mutex = Mutex.new
            @watchdog = true
            @period = 1
            @last_state
            @port_names = Array.new
            @property_names = Array.new

            watchdog_proc = Proc.new do
                ping # call a method which raises ComError if the connection died
                # this is used to disconnect the task by an error handler
                [states,port_names,property_names]
            end
            @watchdog_timer = @event_loop.async_every(watchdog_proc,{:period => @period,
                                                      :default => [[],[],[]],
                                                      :start => false,
                                                      :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound]}) do |data,error|

                process_states(data[0])
                process_port_names(data[1])
                process_property_names(data[2])
                                                      end

            # disconnect if an error occurred
            on_error do |e|
                disconnect(e)
            end
            connect(ior,options_other)
        end

        def on_reachable(&block)
            call =  @mutex.synchronize do
                @callbacks[:on_reachable] << block
                if @__task_context
                    true
                else
                    false
                end
            end
            # must called outside of the mutex
            block.call if call
            self
        end

        def on_unreachable(&block)
            @callbacks[:on_unreachable] << block
            self
        end

        def on_port_reachable(&block)
            ports =  @mutex.synchronize do
                @callbacks[:on_port_reachable] << block
                if @__task_context
                    @port_names
                else
                    []
                end
            end
            ports.each do |name|
                block.call name
            end
            self
        end

        def on_port_unreachable(&block)
            @callbacks[:on_port_unreachable] << block
            self
        end

        def on_property_reachable(&block)
            properties =  @mutex.synchronize do
                @callbacks[:on_property_reachable] << block
                if @__task_context
                    @property_names
                else
                    []
                end
            end
            properties.each do |name|
                block.call name
            end
            self
        end

        def on_property_unreachable(&block)
            @callbacks[:on_property_unreachable] << block
            self
        end

        def on_state_change(&block)
            ArgumentError "activate watchdog first" unless @watchdog

            call =  @mutex.synchronize do
                @callbacks[:on_state_change] << block
                if @__task_context
                    true
                else
                    false
                end
            end
            if call
                current_state do |val|
                    block.call(val) if val
                end
            end
            self
        end

        def name
            @mutex.synchronize do
                @name
            end
        end

        def ior
            @mutex.synchronize do
                @ior
            end
        end

        # connects with the remote orocos Task specified by its IOR
        #
        # @param (see TaskContext#initialize)
        def connect(ior,options=Hash.new)
            @mutex.synchronize do
                options = Kernel.validate_options options,  :name=> nil,
                    :ior => ior,
                    :watchdog => @watchdog,
                    :wait => false,
                    :period => @period,
                    :use => nil
                @watchdog = options[:watchdog]
                @period = options[:period]
                @__task_context = options[:use]
                ior = options[:ior]

                @ior,@name = if @__task_context
                                 [@__task_context.ior,@__task_context.name]
                             elsif ior.respond_to?(:ior)
                                 [ior.ior, ior.name]
                             else
                                 [ior, options[:name]]
                             end

                raise ArgumentErrir,"no watchdog period is given" if !@period && @watchdog
                raise ArgumentError,"no IOR or task is given" unless @ior

                @watchdog_timer.start(@period) if @watchdog
                @event_loop.async(method(:__task_context))
            end
            wait if options[:wait]
        end

        # Disconnectes self from the remote task context and returns its underlying
        # object used to communicate with the remote task (designated object).
        # 
        # Returns nil if the TaskContext is not connected.
        # Returns an EventLoop Event if not called from the event loop thread.
        #
        # @prarm [Exception] reason The reason for the disconnect
        # @return [Orocos::TaskContext,nil,Utilrb::EventLoop::Event]
        def disconnect(reason = nil)
            # ensure that this is always called from the
            # event loop thread
            @event_loop.call do
                task,blocks  = @mutex.synchronize do
                    if @__task_context
                        @ior = nil
                        @ior_error = reason if reason
                        task,@__task_context = @__task_context,nil
                        @watchdog_timer.cancel if @watchdog_timer
                        [task, @callbacks[:on_unreachable]]
                    end
                end
                blocks.each(&:call) if blocks
                process_port_names()
                process_property_names()
                task
            end
        end

        def port(name, verify = true, &block)
            p = proc do |port,error|
                port = if port.respond_to? :write
                           Orocos::Async::CORBA::InputPort.new(self,port)
                       elsif port.respond_to? :reader
                           Orocos::Async::CORBA::OutputPort.new(self,port)
                       end
                if block
                    if block.arity == 2
                        block.call port,error
                    elsif !error
                        block.call port
                    end
                else
                    port
                end
            end
            if block
                port = orig_port(name,verify,&p)
            else
                port = orig_port(name,verify)
                p.call port
            end
        end

        def reachable?(&block)
            if block
                ping(&block)
            else
                ping
            end
            true
        rescue Orocos::NotFound,Orocos::CORBA::ComError => e
            disconnect(e)
            false
        end

        private
        # add methods which forward the call to the underlying task context
        forward_to :__task_context,:@event_loop, :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound],:on_error => :__on_error do
            thread_safe do
                def_delegator :ping,:known_errors => nil  #raise if there is an error in the communication
                methods = [:has_operation?, :has_port?,:property_names,:attribute_names,:port_names,:rtt_state]
                def_delegators methods
                def_delegator :reachable?, :alias => :orig_reachable?
            end
            def_delegator :port, :alias => :orig_port

            methods = Orocos::TaskContext.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= TaskContext.instance_methods + [:method_missing]
            def_delegators methods
        end


        # must be called from the event loop thread
        def process_port_names(port_names=[])
            added_ports = port_names - @port_names
            deleted_ports = @port_names - port_names
            deleted_ports.each do |name|
                @port_names.delete name
                event :on_port_unreachable, name
            end
            added_ports.each do |name|
                @port_names << name
                event :on_port_reachable, name
            end
        end

        # must be called from the event loop thread
        def process_property_names(property_names=[])
            added_properties = property_names - @property_names
            deleted_properties = @property_names - property_names
            deleted_properties.each do |name|
                @property_names.delete name
                event :on_property_unreachable, name
            end
            added_properties.each do |name|
                @property_names << name
                event :on_property_reachable, name
            end
        end

        # must be called from the event loop thread
        def process_states(states=[])
            if !states.empty?
                blocks = @callbacks[:on_state_change]
                states.each do |s|
                    next if @last_state == s
                    blocks.each do |b|
                        b.call(s)
                    end
                    @last_state = s
                end
            end
        end

        # Returns the designated object and an error object.
        # This must be thread safe as it is called from the worker threads!
        # @__task_context must not be directly accessed without synchronize.
        def __task_context
            @mutex.synchronize do
                begin
                    if @__task_context
                        @__task_context
                    elsif !@ior  # do not try again 
                        if !@ior_error
                            raise ArgumentError, "@ior is empty but no error was raised."
                        else
                            raise @ior_error
                        end
                    else
                        @__task_context = Orocos::TaskContext.new @ior ,:name => @name
                        @name = @__task_context.name
                        port_names = @__task_context.port_names
                        property_names = @__task_context.property_names
                        @event_loop.once do
                            event :on_reachable
                            process_port_names(port_names)
                            process_property_names(property_names)
                        end
                        @__task_context.state
                        @__task_context
                    end
                rescue Exception => e
                    @ior = nil          # ior seems to be invalid
                    @ior_error = e
                    raise e if @raise   # do not be silent if
                    # the task context is not reachable
                end
                [@__task_context,@ior_error]
            end
        end
    end
end
