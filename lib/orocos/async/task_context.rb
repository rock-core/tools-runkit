
module Orocos::Async
    class TaskContext
        extend Utilrb::EventLoop::Forwardable

        # A TaskContext
        #
        # If not specified the default option settings are:
        #       :event_loop => Async.event_loop
        #       :name_service => Orocos::Async.name_service
        #       :raise => false
        #       :watchdog => true
        #       :period => 1.0
        #
        # @param [String,#to_task_context] ior The ior of the task or a task context.
        # @param [Hash] options The options.
        # @param [Orocos::TaskContext,#to_task_context] task The underlying task context.
        # @option options [String] :name The name of the task.
        # @option options [#get] :name_service The name service which is used to find the task.
        # @option options [Utilrb::EventLoop] :event_loop The event loop.
        # @option options [String] :ior The IOR.
        # @option options [Boolean] :raise Raises an Orocos::NotFound error if the remote task is
        #       unreachable or went offline. Otherwise tries to reconnect and silently ignores method calls on
        #       the remote task object as long as the task is unreachable.
        # @option options [Orocos::TaskContext,#to_task_context] :task The underlying task.
        # @option options [Boolean] :watchdog Checks the state of the tasks and if it is reachable.
        # @option options [Float] :period The period of the watchdog in seconds.
        # @overload initialize(options)
        def initialize(ior,options=Hash.new)
            ior,options = if ior.is_a? Hash
                               [nil,ior]
                           else
                               [ior,options]
                           end
            options = Kernel.validate_options options,:raise => false,
                                                      :name=> nil,
                                                      :name_service => Orocos::Async.name_service,
                                                      :event_loop => Orocos::Async.event_loop,
                                                      :ior => ior,
                                                      :task => nil,
                                                      :watchdog => true,
                                                      :period => 1.0
            @ior = if ior.respond_to?(:to_task_context)
                       options[:task] = ior
                       if options[:ior] == ior
                           nil
                       else
                           options[:ior]
                       end
                    else
                        options[:ior]
                   end
            @__task_conntext = if options[:task]
                                   options[:name] = options[:task].name
                                   options[:task].to_task_context
                               end
            @name_service = options[:name_service]
            @name = options[:name]
            @event_loop = options[:event_loop]
            @raise = options[:raise]
            @watchdog = options[:watchdog]
            @period = options[:period]
            @mutex = Mutex.new
            @on_connected = []
            @on_disconnected = []
            @on_state_change = []
            @on_error = []

            raise ArgumentErrir,"no watchdog period is given" if !@period && @watchdog
            raise ArgumentError,"no IOR or task name is given" unless @ior || @name
            raise ArgumentError,"no name service is given to find the task context #{@name}" if @name && !@name_service

            # activate watchdog which is reading the state of the task 
            # every given period
            @watchdog_timer = if @watchdog
                                  rtt_state_every @period do |state,e|
                                      __disconnect unless state
                                  end
                              end

            # disconnect if an Orocos::NotFound or Orocos::CORBA::ComError error occurred
            @event_loop.on_errors Orocos::NotFound,Orocos::CORBA::ComError do |e|
                __disconnect
            end

            # asynchronously try to connect to the remote task
            # all other access will be blocked during that period
            # if an error occurred it will be stored until 
            # step is called
            @event_loop.async(method(:__task_context))
        end

        def on_connected(&block)
            call =  @mutex.synchronize do 
                @on_connected << block
                if @__task_context
                    true
                else
                    false
                end
            end
            # must called outside of the mutex
            block.call if call
        end

        def on_disconnected(&block)
            @on_disconnected << block
        end

        def on_state_change(&block)
            @on_state_change << block
        end

        def on_error(error_class,&block)
            @event_loop.on_error error_class, &block
        end

        def on_errors(*error_classes,&block)
            @event_loop.on_errors *error_classes, &block
        end

        private
        # add methods which forward the call to the underlying task context
        forward_to :__task_context,:@event_loop  do 

            # forward thread safe functions which can be called in parallel
            thread_safe do
                thread_safe_bool = [:has_operation?, :has_port?]
                thread_safe_nil = [:ping, :rtt_state]
                thread_safe_array = [:property_names, :attribute_names, :port_names]
                def_delegators thread_safe_bool, :default => false
                def_delegators thread_safe_array, :default => []
                def_delegators thread_safe_nil,:default => nil
                def_delegator :reachable?,:filter => :__reachable?,:default => nil
            end

            #forward non thread safe functions 
            non_thread_safe_all = (Orocos::TaskContext.instance_methods-TaskContext.instance_methods).delete_if {|method| nil !=(method.to_s =~ /^do.*/)}
            non_thread_safe_all -= [:method_missing]
            non_thread_safe_bool = non_thread_safe_all.dup.delete_if {|method| nil == (method.to_s =~ /.*(\?)$/)}
            non_thread_safe_nil = non_thread_safe_all - non_thread_safe_bool
            def_delegators  non_thread_safe_nil,:default => nil
            def_delegators  non_thread_safe_bool,:default => false
        end

        # filter which is called after reachable? to process its result value
        def __reachable?(state)
            if state
                true
            else
                __disconnect
               false
            end
        end

        # Returns the designated object and an error object.
        # This must be thread safe as it is called from the worker threads!
        # @__task_context must not be directly accessed without synchronize.
        def __task_context
            @mutex.synchronize do
                error = nil
                begin
                    if @__task_context
                        @__task_context
                    else
                        @__task_context = if @ior
                                              Orocos::TaskContext.new @ior
                                          else
                                              @name_service.get @name
                                          end
                        @event_loop.once do
                            @on_connected.each do |block|
                                block.call
                            end
                        end
                        @__task_context
                    end
                rescue Exception => e
                    raise e if @raise   # do not be silent if 
                                        # the task context is not reachable
                    error = e
                end
                [@__task_context,error]
            end
        end

        def __disconnect
            @mutex.synchronize do
                @__task_context = nil
            end
            @event_loop.once do
                @on_disconnected.each do |block|
                    block.call
                end
            end
            nil
        end
    end
end
