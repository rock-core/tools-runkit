require 'forwardable'
require 'delegate'

module Orocos::Async
    class AttributeBaseProxy < ObjectBase
        extend Forwardable
        define_events :change

        methods = Orocos::AttributeBase.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= AttributeBaseProxy.instance_methods + [:method_missing,:name]
        def_delegators :@delegator_obj,*methods

        def initialize(task_proxy,attribute_name,policy=Hash.new)
            options,policy = Kernel.filter_options policy, :type => nil
            super(attribute_name,task_proxy.event_loop)
            @type = options[:type]
            @policy = policy
            @task_proxy = task_proxy
        end

        def type_name
            type.name
        end

        def last_sample
            if valid_delegator?
                @delegator_obj.last_sample
            else
                nil
            end
        end

        def type
            @type ||= @delegator_obj.type
        end

        def reachable!(attribute,options = Hash.new)
            if @type && @type != attribute.type
                raise RuntimeError, "the given type #{@type} for attribute #{attribute.name} differes from the real type name #{attribute.type}"
            end
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            super
            proxy_event(@delegator_obj,@delegator_obj.event_names)
        end

        def unreachable!(options=Hash.new)
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            super
        end

        def period=(period)
            @policy[:period] = period
            @delegator_obj.period = period if valid_delegator?
        end
    end

    class PropertyProxy < AttributeBaseProxy
    end

    class AttributeProxy < AttributeBaseProxy
    end

    class PortProxy < ObjectBase
        extend Forwardable
        attr_reader :policy
        define_events :data

        methods = Orocos::Port.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= PortProxy.instance_methods + [:method_missing,:name]
        def_delegators :@delegator_obj,*methods
        
        def initialize(task_proxy,port_name,policy=Hash.new)
            options,policy = Kernel.filter_options policy, :type => nil
            super(port_name,task_proxy.event_loop)
            @type = options[:type]
            @policy = policy
            @task_proxy = task_proxy
        end

        def type_name
            type.name
        end

        def type
            @type ||= @delegator_obj.type
        end

        def input?
            if !valid_delegator?
                true
            elsif @delegator_obj.respond_to?(:writer)
                true
            else
                false
            end
        end

        def output?
            if !valid_delegator?
                true
            elsif @delegator_obj.respond_to?(:reader)
                true
            else
                false
            end
        end

        def reachable?
            super && @delegator_obj.reachable?
        end

        def reachable!(port,options = Hash.new)
            raise ArgumentError, "port must not be kind of PortProxy" if port.is_a? PortProxy
            if @type && @type != port.type
                raise RuntimeError, "the given type #{@type} for port #{port.full_name} differes from the real type name #{port.type}"
            end

            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            super
            proxy_event(@delegator_obj,@delegator_obj.event_names)

            #check which port we have
            if !port.respond_to?(:reader) && number_of_listeners(:data) != 0
                raise RuntimeError, "Port #{name} is an input port but callbacks for on_data are registered" 
            end
        end

        def unreachable!(options = Hash.new)
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            super
        end

        # returns a sub port for the given subfield
        def sub_port(subfield,type=nil)
            raise RuntimeError , "Port #{name} is not an output port" if !output?
            SubPortProxy.new(self,subfield,type)
        end

        def period=(period)
            raise RuntimeError, "Port #{name} is not an output port" if !output?
            @policy[:period] = period
            @delegator_obj.period = period if valid_delegator?
        end

        def on_data(policy = Hash.new,&block)
            raise RuntimeError , "Port #{name} is not an output port" if !output?
            @policy.merge! policy
            on_event :data,&block
        end
    end

    class SubPortProxy < DelegateClass(PortProxy)
        def initialize(port_proxy,subfield = Array.new,type = nil)
            raise ArgumentError, "#{type} is not a Typelib::Type" if type && !type.is_a?(Typelib::Type)
            super(port_proxy)
            @subfield = Array(subfield)
            @type = type
            @ruby_type = nil
        end

        def on_data(policy = Hash.new,&block)
            p = proc do |sample|
                block.call subfield(sample,@subfield)
            end
            super(policy,&p)
        end

        def type_name
            type.name
        end

        def type
            @type ||= if !@subfield.empty?
                          type ||= super
                          @subfield.each do |f|
                              type = if type.respond_to? :deference
                                         type.deference
                                     else
                                         type[f]
                                     end
                          end
                          type
                      else
                          super
                      end
        end

        private
        def ruby_type
            @ruby_type ||= if Typelib.convertions_to_ruby.has_key?(type_name)
                               val = Typelib.convertions_to_ruby[type_name]
                               if val.empty?
                                   type
                               else
                                   val.flatten[1]
                               end
                           elsif type.is_a?(Typelib::NumericType)
                                if type.integer?
                                    Fixnum
                                else
                                    Float
                                end
                           else
                               type
                           end
        end
        
        def subfield(sample,field)
            field.each do |f|
                sample = sample[f]
                if !sample
                    #if the field name is wrong typelib will raise an ArgumentError
                    Vizkit.warn "Cannot extract subfield for port #{full_name}: Subfield #{f} does not exist (out of index)!"
                    break
                end
            end
            #check if the type is right
            if(!sample.is_a?(ruby_type))
                raise "Type miss match. Expected type #{ruby_type} but got #{sample.class} for subfield #{field.join(".")} of port #{full_name}"
            end
            sample
        end
    end

    class TaskContextProxy < ObjectBase
        attr_reader :name_service
        include Orocos::Namespace
        define_events :port_reachable,
                      :port_unreachable,
                      :property_reachable,
                      :property_unreachable,
                      :attribute_reachable,
                      :attribute_unreachable,
                      :state_change

        # forward methods to designated object
        extend Forwardable
        methods = Orocos::TaskContext.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= TaskContextProxy.instance_methods + [:method_missing,:reachable?,:port]
        def_delegators :@delegator_obj,*methods

        def initialize(name,options=Hash.new)
            @options,@task_options = Kernel.filter_options options,{:name_service => Orocos::Async.name_service,
                                                       :event_loop => Orocos::Async.event_loop,
                                                       :reconnect => true,
                                                       :retry_period => 1.0,
                                                       :use => nil,
                                                       :raise => false,
                                                       :wait => nil }

            namespace,name = split_name(name)
            self.namespace = namespace
            super(name,@options[:event_loop])

            @name_service = @options[:name_service]
            @resolve_task = nil
            @task_options[:event_loop] = @event_loop
            @mutex = Mutex.new
            @ports = Hash.new
            @attributes = Hash.new
            @properties = Hash.new

            if options.has_key?(:use)
                reachable!(options[:use])
            else
                reconnect(@options[:wait])
            end
        end

        def name
            map_to_namespace(@name)
        end

        def basename
            @name
        end

        # asychronsosly tries to connect to the remote task
        def reconnect(wait_for_task = false)
            if !@resolve_task
                @resolve_task = @name_service.get @name,@task_options do |task_context,error|
                    if error
                        raise error if @options[:raise]
                        t = [0,@options[:retry_period] - (Time.now - @resolve_task.started_at)].max
                        @event_loop.once(t) do
                            @event_loop.add_task @resolve_task
                        end
                    else
                        reachable!(task_context)
                        @resolve_task = nil
                    end
                end
            end
            wait if wait_for_task == true
        end

        def property(name,options = Hash.new)
            options,other_options = Kernel.filter_options options,:wait => @options[:wait]
            wait if options[:wait]

            p = @mutex.synchronize do
                @properties[name] ||= PropertyProxy.new(self,name,other_options)
            end

            if options[:wait]
                connect_property(p)
                p.wait
            else
                @event_loop.defer :known_errors => Orocos::NotFound do
                    connect_property(p)
                end
            end
            p
        end

        def attribute(name,options = Hash.new)
            options,other_options = Kernel.filter_options options,:wait => @options[:wait]
            wait if options[:wait]

            a = @mutex.synchronize do
                @attributes[name] ||= AttributeProxy.new(self,name,other_options)
            end

            if options[:wait]
                connect_attribute(a)
                a.wait
            else
                @event_loop.defer :known_errors => Orocos::NotFound do
                    connect_attribute(a)
                end
            end
            a
        end

        def port(name,options = Hash.new)
            options,other_options = Kernel.filter_options options,:wait => @options[:wait]
            wait if options[:wait]
            p = @mutex.synchronize do
                @ports[name] ||= PortProxy.new(self,name,other_options)
            end

            if options[:wait]
                connect_port(p)
                p.wait
            else
                @event_loop.defer :known_errors => Orocos::NotFound do
                    connect_port(p)
                end
            end
            p
        end

        def ports(options = Hash.new,&block)
           p = proc do |names|
               names.map{|name| port(name,options)}
           end
           if block
               port_names(&p)
           else
               p.call(port_names)
           end
        end

        def properties(&block)
           p = proc do |names|
               names.map{|name| property(name)}
           end
           if block
               property_names(&p)
           else
               p.call(property_names)
           end
        end

        def attributes(&block)
           p = proc do |names|
               names.map{|name| attribute(name)}
           end
           if block
               attribute_names(&p)
           else
               p.call(attribute_names)
           end
        end

        # must be thread safe 
        # do not emit anything because reachabel will be emitted by the delegator_obj
        def reachable!(task_context,options = Hash.new)
            raise ArgumentError, "task_context must not be instance of TaskContextProxy" if task_context.is_a?(TaskContextProxy)
            ports,attributes,properties = @mutex.synchronize do
                remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
                if @delegator_obj_old
                    remove_proxy_event(@delegator_obj_old,@delegator_obj_old.event_names)
                    @delegator_obj_old = nil
                end
                @delegator_obj = task_context
                proxy_event(@delegator_obj,@delegator_obj.event_names)
                [@ports.values,@attributes.values,@properties.values]
            end
            ports.each do |port|
                begin
                    connect_port(port)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no port called #{port.name} -> on_data will not be called!"
                rescue Orocos::CORBA::ComError
                end
            end
            attributes.each do |attribute|
                begin
                    connect_attribute(attribute)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no attribute called #{attribute.name} -> on_change will not be called!"
                rescue Orocos::CORBA::ComError
                end
            end
            properties.each do |property|
                begin
                    connect_property(property)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no property called #{property.name} -> on_change will not be called!"
                rescue Orocos::CORBA::ComError
                end
            end
        end

        def reachable?
            @mutex.synchronize do
                super && @delegator_obj.reachable?
            end
        rescue Orocos::NotFound => e
            unreachable! :error => e,:reconnect => @options[:reconnect]
            false
        end

        def unreachable!(options = {:reconnect => false})
            Kernel.validate_options options,:reconnect,:error
            @mutex.synchronize do
                # do not stop proxing events here (see reachable!)
                # otherwise unrechable event might get lost
                @delegator_obj_old = if valid_delegator?
                                         @delegator_obj
                                     else
                                         @delegator_obj_old
                                     end
                invalidate_delegator!
            end
            disconnect_ports
            disconnect_attributes
            disconnect_properties
            re = if options.has_key?(:reconnect)
                    options[:reconnect]
                 else
                    @options[:reconnect]
                 end
            event :unreachable
            reconnect if re
        end

        private
        # blocking call shoud be called from a different thread
        # all private methods must be thread safe
        def connect_port(port)
            p = @mutex.synchronize do
                return unless valid_delegator?
                @delegator_obj.port(port.name)
            end
            @event_loop.call do
                port.reachable!(p)
            end
        end

        def disconnect_ports
            ports = @mutex.synchronize do
                @ports.values
            end
            ports.each(&:unreachable!)
        end

        # blocking call shoud be called from a different thread
        def connect_attribute(attribute)
            a = @mutex.synchronize do
                return unless valid_delegator?
                @delegator_obj.attribute(attribute.name)
            end
            @event_loop.call do
                attribute.reachable!(a)
            end
        end

        def disconnect_attributes
            attributes = @mutex.synchronize do 
                @attributes.values
            end
            attributes.each(&:unreachable!)
        end

        # blocking call shoud be called from a different thread
        def connect_property(property)
            p = @mutex.synchronize do
                return unless valid_delegator?
                @delegator_obj.property(property.name)
            end
            @event_loop.call do
                property.reachable!(p)
            end
        end

        def disconnect_properties
            properties = @mutex.synchronize do
                @properties.values
            end
            properties.each(&:unreachable!)
        end
    end
end
