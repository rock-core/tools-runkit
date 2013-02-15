require 'forwardable'
require 'delegate'

module Orocos::Async
    class AttributeBaseProxy < ObjectBase
        extend Forwardable
        define_events :change

        methods = Orocos::AttributeBase.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= AttributeBaseProxy.instance_methods + [:method_missing,:name]
        methods << :type
        def_delegators :@delegator_obj,*methods

        def initialize(task_proxy,attribute_name,options=Hash.new)
            @type = options.delete(:type) if options.has_key? :type
            @options = options
            super(attribute_name,task_proxy.event_loop)
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

        # do not emit anything because reachable will be emitted by the delegator_obj
        def reachable!(attribute,options = Hash.new)
            @options = attribute.options
            if @type && @type != attribute.type
                raise RuntimeError, "the given type #{@type} for attribute #{attribute.name} differes from the real type name #{attribute.type}"
            end
            @type ||= attribute.type
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            disable_emitting do
                super(attribute,options)
            end
            proxy_event(@delegator_obj,@delegator_obj.event_names)
        end

        # do not emit anything because reachable will be emitted by the delegator_obj
        def unreachable!(options=Hash.new)
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            disable_emitting do
                super(options)
            end
        end

        def period
            if @options.has_key? :period
                @options[:period]
            else
                nil
            end
        end

        def period=(period)
            @options[:period] = period
            @delegator_obj.period = period if valid_delegator?
        end

        def on_change(policy = Hash.new,&block)
            @options = if policy.empty?
                           @options
                       elsif @options.empty? && !valid_delegator?
                           policy
                       elsif @options == policy
                           @options
                       else
                           Orocos.warn "ProxyProperty #{full_name} cannot emit :change with different policies."
                           Orocos.warn "The current policy is: #{@options}."
                           Orocos.warn "Ignoring policy: #{policy}."
                           @options
                       end
            on_event :change,&block
        end

    end

    class PropertyProxy < AttributeBaseProxy
    end

    class AttributeProxy < AttributeBaseProxy
    end

    class PortProxy < ObjectBase
        extend Forwardable
        define_events :data

        methods = Orocos::Port.instance_methods.find_all{|method| nil == (method.to_s =~ /^do.*/)}
        methods -= PortProxy.instance_methods + [:method_missing,:name]
        methods << :write
        methods << :type
        def_delegators :@delegator_obj,*methods
        
        def initialize(task_proxy,port_name,options=Hash.new)
            super(port_name,task_proxy.event_loop)
            @task_proxy = task_proxy
            @type = options.delete(:type) if options.has_key? :type
            @options = options
        end

        def type_name
            type.name
        end

        def full_name
            "#{@task_proxy.name}.#{name}"
        end

        def type
            @type ||= @delegator_obj.type
        end

        def task
            @task_proxy
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

        # do not emit anything because reachable will be emitted by the delegator_obj
        def reachable!(port,options = Hash.new)
            raise ArgumentError, "port must not be kind of PortProxy" if port.is_a? PortProxy
            if @type && @type != port.type
                raise RuntimeError, "the given type #{@type} for port #{port.full_name} differes from the real type name #{port.type}"
            end

            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            disable_emitting do
                super(port,options)
            end
            proxy_event(@delegator_obj,@delegator_obj.event_names)
            @type ||= port.type

            #check which port we have
            if !port.respond_to?(:reader) && number_of_listeners(:data) != 0
                raise RuntimeError, "Port #{name} is an input port but callbacks for on_data are registered" 
            end
        end

        # do not emit anything because reachable will be emitted by the delegator_obj
        def unreachable!(options = Hash.new)
            remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
            disable_emitting do
                super(options)
            end
        end

        # returns a sub port for the given subfield
        def sub_port(subfield,type=nil)
            raise RuntimeError , "Port #{name} is not an output port" if !output?
            SubPortProxy.new(self,subfield,type)
        end

        def period
            if @options.has_key? :period
                @options[:period]
            else
                nil
            end
        end

        def period=(period)
            raise RuntimeError, "Port #{name} is not an output port" if !output?
            @options[:period] = period
            @delegator_obj.period = period if valid_delegator?
        end

        def on_data(policy = Hash.new,&block)
            raise RuntimeError , "Port #{name} is not an output port" if !output?
            @options = if policy.empty?
                           @options
                       elsif @options.empty? && !valid_delegator?
                           policy
                       elsif @options == policy
                           @options
                       else
                           Orocos.warn "ProxyPort #{full_name} cannot emit :data with different policies."
                           Orocos.warn "The current policy is: #{@options}."
                           Orocos.warn "Ignoring policy: #{policy}."
                           @options
                       end
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
        methods << :type
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

            self.namespace,name = split_name(name)
            super(name,@options[:event_loop])

            @name_service = @options[:name_service]
            @task_options[:event_loop] = @event_loop
            @mutex = Mutex.new
            @ports = Hash.new
            @attributes = Hash.new
            @properties = Hash.new
            @resolve_task = nil
            @resolve_timer = @event_loop.every(options[:retry_period],false) do
                if !@resolve_task
                    @resolve_task = @name_service.get @name,@task_options do |task_context,error|
                        if error
                            raise error if @options[:raise]
                            @resolve_task = nil
                            :ignore_error
                        else
                            reachable!(task_context)
                            @resolve_timer.stop
                            @resolve_task = nil
                        end
                    end
                end
            end
            @resolve_timer.doc = "#{name} reconnect"
            if @options.has_key?(:use)
                reachable!(@options[:use])
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
            @resolve_timer.start options[:retry_period]
            wait if wait_for_task == true
        end

        def property(name,options = Hash.new)
            options,other_options = Kernel.filter_options options,:wait => @options[:wait]
            wait if options[:wait]

            p = @mutex.synchronize do
                @properties[name] ||= PropertyProxy.new(self,name,other_options)
            end

            if !other_options.empty? && p.options != other_options
                Orocos.warn "Property #{p.full_name}: is already initialized with options: #{p.options}"
                Orocos.warn "ignoring options: #{other_options}"
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

            if !other_options.empty? && a.options != other_options
                Orocos.warn "Attribute #{a.full_name}: is already initialized with options: #{a.options}"
                Orocos.warn "ignoring options: #{other_options}"
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

            if !other_options.empty? && p.options != other_options
                Orocos.warn "Port #{p.full_name}: is already initialized with options: #{p.options}"
                Orocos.warn "ignoring options: #{other_options}"
            end

            if options[:wait]
                connect_port(p)
                p.wait
            else
                @event_loop.defer :known_errors => [Orocos::ComError,Orocos::NotFound] do
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
        # do not emit anything because reachable will be emitted by the delegator_obj
        def reachable!(task_context,options = Hash.new)
            raise ArgumentError, "task_context must not be instance of TaskContextProxy" if task_context.is_a?(TaskContextProxy)
            raise ArgumentError, "task_context must be an async instance" if !task_context.respond_to?(:event_names)
            ports,attributes,properties = @mutex.synchronize do
                remove_proxy_event(@delegator_obj,@delegator_obj.event_names) if valid_delegator?
                if @delegator_obj_old
                    remove_proxy_event(@delegator_obj_old,@delegator_obj_old.event_names)
                    @delegator_obj_old = nil
                end
                disable_emitting do
                    super(task_context,options)
                end
                proxy_event(@delegator_obj,@delegator_obj.event_names)
                [@ports.values,@attributes.values,@properties.values]
            end
            ports.each do |port|
                begin
                    connect_port(port)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no port called #{port.name} -> on_data will not be called!"
                rescue Orocos::CORBA::ComError => e
                    Orocos.warn "task #{name} with error on port: #{port.name} #{port.type} -- #{e}"
                end
            end
            attributes.each do |attribute|
                begin
                    connect_attribute(attribute)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no attribute called #{attribute.name} -> on_change will not be called!"
                rescue Orocos::CORBA::ComError => e
                    Orocos.warn "task #{name} with error on port: #{attribute.name} #{attribute.type} -- #{e}"
                end
            end
            properties.each do |property|
                begin
                    connect_property(property)
                rescue Orocos::NotFound
                    Orocos.warn "task #{name} has currently no property called #{property.name} -> on_change will not be called!"
                rescue Orocos::CORBA::ComError => e
                    Orocos.warn "task #{name} with error on port: #{property.name} #{property.type} -- #{e}"
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

                disable_emitting do
                    super(options)
                end
            end
            disconnect_ports
            disconnect_attributes
            disconnect_properties
            re = if options.has_key?(:reconnect)
                    options[:reconnect]
                 else
                    @options[:reconnect]
                 end
            reconnect if re
        end

        private
        # blocking call shoud be called from a different thread
        # all private methods must be thread safe
        def connect_port(port)
            p = @mutex.synchronize do
                return unless valid_delegator?
                @delegator_obj.disable_emitting do
                    port(port.name,true,port.options)
                end
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
                @delegator_obj.disable_emitting do
                    attribute(attribute.name)
                end
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
                @delegator_obj.disable_emitting do
                    property(property.name)
                end
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
