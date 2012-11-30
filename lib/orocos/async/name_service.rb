module Orocos::Async

    def self.name_service
        @name_service ||= Orocos::Async::NameService.new(CORBA.name_service)
    end

    def self.get(name,options =Hash.new)
        name_service.get(name,options)
    end

    def self.proxy(name,options = Hash.new)
        name_service.proxy(name,options)
    end

    class NameServiceBase
        extend Utilrb::EventLoop::Forwardable
        def proxy(name,options)
            @task_context_proxies ||= Array.new
            options[:event_loop] ||= @event_loop
            options[:name_service] ||= self
            task = @task_context_proxies.find do |t|
                        t.name == name &&
                        t.event_loop == options[:event_loop] &&
                        t.name_service == options[:name_service]
            end
            if task
                task
            else
                @task_context_proxies << Orocos::Async::TaskContextProxy.new(name,options)
                @task_context_proxies.last
            end
        end
    end

    class NameService < NameServiceBase
        def initialize(*name_services)
            options = if name_services.last.is_a? Hash
                          name_services.pop
                      else
                          Hash.new
                      end
            options = Kernel.validate_options options,{:even_loop => Orocos::Async.event_loop}
            @event_loop = options[:even_loop]
            @name_service = Orocos::NameService.new *name_services
        end

        private
        # add methods which forward the call to the underlying name service
        forward_to :@name_service,:@event_loop, :known_errors => [Orocos::NotFound] do
            methods = Orocos::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
            methods -= NameService.instance_methods + [:method_missing]
            def_delegators methods
        end
    end

    module Local
        class NameService < NameServiceBase
            extend Utilrb::EventLoop::Forwardable

            def initialize(options)
                options = Kernel.validate_options options,{:even_loop => Async.event_loop,:tasks => Hash.new}
                @event_loop = options[:even_loop]
                @name_service = Orocos::Local::NameService.new options[:tasks]
            end

            # TODO implement Async::Log::TaskContext
            def get(name,options=Hash.new,&block)
                raise NotImplementedError
            end

            private
            # add methods which forward the call to the underlying name service
            forward_to :@name_service,:@event_loop do
                methods = Orocos::CORBA::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
                methods -= NameService.instance_methods + [:method_missing]
                def_delegators methods
                def_delegator :get,:alias => :orig_get
            end
        end
    end

    module CORBA
        class << self
            attr_reader :name_service
            def name_service=(service)
                Orocos::Async.name_service.name_services.each_with_index do |i,val|
                    if val == @name_service
                        Orocos::Async.name_service.name_services[i] = service
                        break
                    end
                end
                @name_service = service
            end
        end

        class NameService < NameServiceBase
            extend Utilrb::EventLoop::Forwardable

            def initialize(ip="",port="",options = Hash.new)
                options,other_options = Kernel.filter_options options,{:event_loop => Orocos::Async.event_loop}
                @event_loop = options[:event_loop]
                @name_service = Orocos::CORBA::NameService.new ip,port,other_options
            end

            def get(name,options=Hash.new,&block)
                async_options,other_options = Kernel.filter_options options, {:raise => nil,:event_loop => @event_loop,:period => nil,:wait => nil}
                if block
                    p = proc do |task,error|
                        async_options[:use] = task
                        task = Orocos::Async::CORBA::TaskContext.new(nil,async_options) unless error
                        if block.arity == 2
                            block.call task,error
                        elsif !error
                            block.call task
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
            forward_to :@name_service,:@event_loop, :known_errors => [Orocos::CORBA::ComError,Orocos::NotFound] do
                methods = Orocos::CORBA::NameService.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
                methods -= NameService.instance_methods + [:method_missing]
                def_delegators methods
                def_delegator :get,:alias => :orig_get
            end
        end
        @name_service ||= NameService.new
    end
end

