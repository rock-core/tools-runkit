
module Orocos::Async::CORBA
    class TaskContext < Orocos::Async::ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic

        self.default_period = 1.0

        define_events :port_reachable,
                      :port_unreachable,
                      :property_reachable,
                      :property_unreachable,
                      :attribute_reachable,
                      :attribute_unreachable,
                      :state_change

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
            ior,options = if ior.is_a? Hash
                              [nil,ior]
                          else
                              [ior,options]
                          end
            options,options_other = Kernel.filter_options options,:event_loop => Orocos::Async.event_loop
            super(ior,options[:event_loop])
            @mutex = Mutex.new
            @last_state = nil
            @port_names = Array.new
            @property_names = Array.new
            @attribute_names = Array.new

            watchdog_proc = Proc.new do
                ping # call a method which raises ComError if the connection died
                # this is used to disconnect the task by an error handler
                [states,port_names,property_names,attribute_names]
            end
            @watchdog_timer = @event_loop.async_every(watchdog_proc,{:period => default_period,
                                                      :default => [[],[],[],[]],
                                                      :start => false,
                                                      :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound,Orocos::CORBAError]}) do |data,error|
                                                            process_states(data[0])
                                                            process_port_names(data[1])
                                                            process_property_names(data[2])
                                                            process_attribute_names(data[3])
                                                      end
            @watchdog_timer.doc = ior
            reachable!(ior,options_other)
        end

        def add_listener(listener)
            # call new listeners with the current value
            # to prevent different behaviors depending on
            # the calling order
            if listener.event == :state_change
                state = @mutex.synchronize do
                    @delegator_obj.current_state if valid_delegator?
                end
                event_loop.once{listener.call state} if state
            elsif listener.event == :port_reachable
                event_loop.once do 
                    @port_names.each do |name|
                        listener.call name
                    end
                end
            elsif listener.event == :property_reachable
                event_loop.once do
                    @property_names.each do |name|
                        listener.call name
                    end
                end
            elsif listener.event == :attribute_reachable
                event_loop.once do
                    @attribute_names.each do |name|
                        listener.call name
                    end
                end
            end
            super
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
        def reachable!(ior,options=Hash.new)
            @mutex.synchronize do
                @options = Kernel.validate_options options,  :name=> nil,
                    :ior => ior,
                    :watchdog => true,
                    :wait => false,
                    :period => default_period,
                    :use => nil,
                    :raise => false
                if @options[:use]
                    @delegator_obj = @options[:use]
                    @ior = @delegator_obj.ior
                    @watchdog_timer.doc = @delegator_obj.name
                else
                    invalidate_delegator!
                end
                ior = @options[:ior]
                @ior,@name = if valid_delegator?
                                 [@delegator_obj.ior,@delegator_obj.name]
                             elsif ior.respond_to?(:ior)
                                 [ior.ior, ior.name]
                             else
                                 [ior, @options[:name]]
                             end

                raise ArgumentError,"no IOR or task is given" unless @ior
                @watchdog_timer.start(period,false) if @options[:watchdog]
                @event_loop.async(method(:task_context))
            end
            wait if @options[:wait]
        end

        # Disconnectes self from the remote task context and returns its underlying
        # object used to communicate with the remote task (designated object).
        # 
        # Returns nil if the TaskContext is not connected.
        # Returns an EventLoop Event if not called from the event loop thread.
        #
        # @prarm [Exception] reason The reason for the disconnect
        # @return [Orocos::TaskContext,nil,Utilrb::EventLoop::Event]
        def unreachable!(options = Hash.new)
            Kernel.validate_options(options,:error)
            # ensure that this is always called from the
            # event loop thread
            @event_loop.call do
                old_task = @mutex.synchronize do
                    if valid_delegator?
                        @ior = nil
                        @ior_error = options[:error] if options.has_key?(:error)
                        task = @delegator_obj
                        invalidate_delegator!
                        @watchdog_timer.cancel if @watchdog_timer
                        task
                    end
                end
                process_port_names()
                process_attribute_names()
                process_property_names()
                event :unreachable if old_task
                old_task
            end
        end

        def reachable?(&block)
            if block
                ping(&block)
            else
                ping
            end
            true
        rescue Orocos::NotFound,Orocos::CORBA::ComError,Orocos::CORBAError => e
            unreachable!(:error => e)
            false
        end

        def attribute(name,&block)
            p = proc do |attribute,error|
                attribute = Orocos::Async::CORBA::Attribute.new(self,attribute)
                if block
                    if block.arity == 2
                        block.call attribute,error
                    elsif !error
                        block.call attribute
                    end
                else
                    attribute
                end
            end
            if block
                attribute = orig_attribute(name,&p)
            else
                attribute = orig_attribute(name)
                p.call attribute
            end
        end

        def property(name,&block)
            p = proc do |property,error|
                property = Orocos::Async::CORBA::Property.new(self,property)
                if block
                    if block.arity == 2
                        block.call property,error
                    elsif !error
                        block.call property
                    end
                else
                    property
                end
            end
            if block
                property = orig_property(name,&p)
            else
                property = orig_property(name)
                p.call property
            end
        end

        def port(name, verify = true,options=Hash.new, &block)
            p = proc do |port,error|
                port = if port.respond_to? :writer
                           Orocos::Async::CORBA::InputPort.new(self,port,options)
                       elsif port.respond_to? :reader
                           Orocos::Async::CORBA::OutputPort.new(self,port,options)
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
                orig_port(name,verify,&p)
            else
                port = orig_port(name,verify)
                p.call port,nil
            end
        end

        private
        # add methods which forward the call to the underlying task context
        forward_to :task_context,:@event_loop, :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound,Orocos::CORBAError],:on_error => :emit_error do
            thread_safe do
                def_delegator :ping,:known_errors => nil  #raise if there is an error in the communication
                methods = [:has_operation?, :has_port?,:property_names,:attribute_names,:port_names,:rtt_state]
                def_delegators methods
                def_delegator :reachable?, :alias => :orig_reachable?
            end
            def_delegator :port, :alias => :orig_port
            def_delegator :property, :alias => :orig_property
            def_delegator :attribute, :alias => :orig_attribute

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
                event :port_unreachable, name
            end
            added_ports.each do |name|
                @port_names << name
                event :port_reachable, name
            end
        end

        # must be called from the event loop thread
        def process_property_names(property_names=[])
            added_properties = property_names - @property_names
            deleted_properties = @property_names - property_names
            deleted_properties.each do |name|
                @property_names.delete name
                event :property_unreachable, name
            end
            added_properties.each do |name|
                @property_names << name
                event :property_reachable, name
            end
        end

        # must be called from the event loop thread
        def process_attribute_names(attribute_names=[])
            added_properties = attribute_names - @attribute_names
            deleted_properties = @attribute_names - attribute_names
            deleted_properties.each do |name|
                @attribute_names.delete name
                event :attribute_unreachable, name
            end
            added_properties.each do |name|
                @attribute_names << name
                event :attribute_reachable, name
            end
        end

        # must be called from the event loop thread
        def process_states(states=[])
            if !states.empty?
                blocks = listeners :state_change
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
        # @delegator_obj must not be directly accessed without synchronize.
        def task_context
            @mutex.synchronize do
                begin
                    task = if valid_delegator?
                               @delegator_obj
                           elsif !@ior  # do not try again 
                               if !@ior_error
                                   raise ArgumentError, "@ior is empty but no error was raised."
                               else
                                   raise @ior_error
                               end
                           else
                               obj = Orocos::TaskContext.new @ior ,:name => @name
                               @name = obj.name
                               port_names = obj.port_names
                               property_names = obj.property_names
                               attribute_names = obj.attribute_names
                               obj.state
                               @event_loop.once do
                                   @watchdog_timer.doc = @name
                                   process_port_names(port_names)
                                   process_property_names(property_names)
                                   process_attribute_names(attribute_names)
                               end
                               @delegator_obj = obj
                               event :reachable
                               obj
                           end
                    [task,nil]
                rescue Exception => e
                    @ior = nil          # ior seems to be invalid
                    @ior_error = e
                    invalidate_delegator!
                    raise e if @options[:raise]   # do not be silent if
                    [nil,@ior_error]
                end
            end
        end
    end
end
