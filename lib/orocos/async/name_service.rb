module Orocos::Async

    def self.name_service
        @name_service ||= Orocos::Async::NameService.new()
    end

    def self.get(name,options =Hash.new)
        name_service.get(name,options)
    end

    def self.proxy(name,options = Hash.new)
        name_service.proxy(name,options)
    end

    class NameServiceBase < ObjectBase
        extend Utilrb::EventLoop::Forwardable
        extend Orocos::Async::ObjectBase::Periodic::ClassMethods
        include Orocos::Async::ObjectBase::Periodic

        define_events :task_added, :task_removed

        def initialize(name_service,options = Hash.new)
            @options ||= Kernel.validate_options options,:period => default_period,:start => false,:sync_key => nil,:known_errors => Orocos::NotFound,:event_loop => Orocos::Async.event_loop
            @stored_names ||= Set.new
            _,options_async = Kernel.filter_options @options,:event_loop=>nil
            super(name_service.name,@options[:event_loop])
            disable_emitting do
                reachable! name_service
            end
            @watchdog_timer = @event_loop.async_every method(:names),options_async do |names,error|
                if error
                    emit_error error
                else
                    if number_of_listeners(:task_removed) == 0 && number_of_listeners(:task_added) == 0
                        @watchdog_timer.cancel
                        @stored_names.clear
                    else
                        names.each do |name|
                            n = @stored_names.add? name
                            event :task_added,name if n
                        end
                        @stored_names.delete_if do |name|
                            if !names.include?(name)
                                event :task_removed,name
                                true
                            else
                                false
                            end
                        end
                    end
                end
            end
            @watchdog_timer.doc = name
        end

        def add_listener(listener)
            if listener.event == :task_added || listener.event == :task_removed 
                @watchdog_timer.start unless @watchdog_timer.running?
                if listener.use_last_value? && !@stored_names.empty?
                    event_loop.once do
                        @stored_names.each do |name|
                            listener.call name
                        end
                    end
                end
            end
            super
        end

        def proxy(name,options = Hash.new)
            @task_context_proxies ||= Array.new
            options[:event_loop] ||= @event_loop
            options[:name_service] ||= self
            task = @task_context_proxies.find do |t|
                        t.name == name &&
                        t.event_loop == options[:event_loop] &&
                        t.name_service == options[:name_service]
            end
            if task
                options.each_pair do |key,value|
                    if task.options[key] != value
                        Orocos.warn "TaskContextProxy #{name} is already initialized with the following options: #{task.options}."
                        Orocos.warn "Ignoring options: #{options}."
                        break
                    end
                end
                task
            else
                @task_context_proxies << Orocos::Async::TaskContextProxy.new(name,options)
                @task_context_proxies.last
            end
        end
    end

    class NameService < NameServiceBase
        self.default_period = 1.0

        def initialize(*name_services)
            options = if name_services.last.is_a? Hash
                          name_services.pop
                      else
                          Hash.new
                      end
            name_service = Orocos::NameService.new *name_services
            super(name_service,options)
        end

        private
        # add methods which forward the call to the underlying name service
        forward_to :@delegator_obj,:@event_loop, :known_errors => [Orocos::NotFound] do
            methods = Orocos::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= Orocos::Async::NameService.instance_methods + [:method_missing]
            def_delegators methods
        end
    end

    module Local
        class NameService < NameServiceBase
            extend Utilrb::EventLoop::Forwardable
            self.default_period = 1.0

            def initialize(options)
                options,other_options = Kernel.filter_options options,{:tasks => Array.new}
                name_service = Orocos::Local::NameService.new options[:tasks]
                super(name_service,other_options)
            end

            def get(name,options=Hash.new,&block)
                async_options,other_options = Kernel.filter_options options, {:sync_key => nil,:raise => nil,:event_loop => @event_loop,:period => nil,:wait => nil}
                if block
                    p = proc do |task,error|
                        task = Orocos::Async::Log::TaskContext.new(task,async_options) unless error
                        if block.arity == 2
                            block.call task,error
                        elsif !error
                            block.call task
                        end
                    end
                    orig_get name,other_options,&p
                else
                    task = orig_get name,other_options
                    Orocos::Async::Log::TaskContext.new(task,async_options)
                end
            end

            private
            # add methods which forward the call to the underlying name service
            forward_to :@delegator_obj,:@event_loop do
                methods = Orocos::Local::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
                methods -= Orocos::Async::Local::NameService.instance_methods + [:method_missing]
                def_delegators methods
                def_delegator :get,:alias => :orig_get
            end
        end
    end

    module CORBA

        class << self
            def name_service=(service)
                Orocos::Async.name_service.name_services.each_with_index do |i,val|
                    if val == @delegator_obj
                        Orocos::Async.name_service.name_services[i] = service
                        break
                    end
                end
                reachable! service
            end
            def name_service
                @name_service ||= NameService.new(Orocos::CORBA.name_service.ip,Orocos::CORBA.name_service.port)
            end

            def get(name,options =Hash.new)
                name_service.get(name,options)
            end

            def proxy(name,options = Hash.new)
                name_service.proxy(name,options)
            end
        end

        class NameService < NameServiceBase
            extend Utilrb::EventLoop::Forwardable
            self.default_period = 1.0

            def initialize(ip="",port="",options = Hash.new)
                ip,port,options = if ip.is_a? Hash
                                      ["","",ip]
                                  elsif port.is_a? Hash
                                      [ip,"",port]
                                  else port.is_a? Hash
                                      [ip,port,options]
                                  end
                my_options,other_options = Kernel.filter_options options,:reconnect=> true
                name_service_options,other_options = Kernel.filter_options other_options
                name_service = Orocos::CORBA::NameService.new ip,port,name_service_options
                other_options[:known_errors] = [Orocos::CORBA::ComError,Orocos::NotFound,Orocos::CORBAError]
                super(name_service,other_options)
                @options.merge! my_options
            end

            def unreachable!(options = Hash.new)
                @watchdog_timer.stop
                if valid_delegator?  && @options[:reconnect] == true && options.has_key?(:error)
                    obj = @delegator_obj
                    obj.reset
                    timer = @event_loop.async_every method(:names),:period => 1.0,:sync_key => nil,:known_errors => [Orocos::NotFound,Orocos::CORBAError,Orocos::CORBA::ComError] do |names,error|
                        if error
                            obj.reset
                        else
                            reachable!(obj)
                            @watchdog_timer.start
                            timer.stop
                        end
                    end
                    timer.doc = "NameService #{name} reconnect"
                end
                super
            end

            def name
                @delegator_obj.name
            end

            def get(name,options=Hash.new,&block)
                async_options,other_options = Kernel.filter_options options, {:sync_key => nil,:raise => nil,:event_loop => @event_loop,:period => nil,:wait => nil}
                if block
                    p = proc do |task,error|
                        async_options[:use] = task
                        atask = if !error
                                    Orocos::Async::CORBA::TaskContext.new(nil,async_options)
                                end
                        if block.arity == 2
                            block.call atask,error
                        elsif !error
                            block.call atask
                        end
                    end
                    orig_get name,other_options,&p
                else
                    task = orig_get name,other_options
                    async_options[:use] = task
                    Orocos::Async::CORBA::TaskContext.new(nil,async_options)
                end
            end

            private
            # add methods which forward the call to the underlying name service
            forward_to :@delegator_obj,:@event_loop, :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound,Orocos::CORBAError], :on_error => :error do
                methods = Orocos::CORBA::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
                methods -= Orocos::Async::CORBA::NameService.instance_methods + [:method_missing]
                thread_safe do 
                    def_delegators methods
                    def_delegator :get,:alias => :orig_get
                end
            end

            def error(e)
                emit_error e if !e.is_a? Orocos::NotFound
            end
        end
    end
end

