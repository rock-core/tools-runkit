require 'utilrb/spawn'
module Orocos
    module ROS
        # A TaskContext-compatible interface of a ROS node
        #
        # The following caveats apply:
        #
        # * ROS nodes do not have an internal lifecycle state machine. In
        #   practice, it means that #configure has no effect, #start will start
        #   the node's process and #stop will kill it (if we have access to it).
        #   If the ROS process is not managed by orocos.rb, they will throw
        # * ROS nodes do not allow modifying subscriptions at runtime, so the
        #   port connection / disconnection methods can only be used while the
        #   node is not running
        class Node < TaskContextBase
            # [NameService] access to the state of the ROS graph
            attr_reader :name_service
            # [ROSSlave] access to the node XMLRPC API
            attr_reader :server
            # [Hash<String,Topic>] a cache of the topics that are known to be
            # associated with this node. It should never be used directly, as it
            # may contain stale entries. The key is the port name of the topic
            attr_reader :topics
            # @return [NameMappings] the name mappings that are applied from the
            #   node implementation to this running node. This is useful only
            #   when using a model
            attr_reader :name_mappings
            # @return [Integer] if started by this Ruby process, the PID of the
            #   ROS node process
            attr_reader :pid
            # @return [Integer] if started by this Ruby process, and then stopped,
            #   the exit status object that represents how the node finished
            attr_reader :exit_status

            def initialize(name_service, server, name = nil, options = Hash.new)
                @name_service = name_service
                @server = server
                @input_topics = Hash.new
                @output_topics = Hash.new
                @name_mappings = NameMappings.new

                if name.kind_of?(Hash)
                    name, options = nil, name
                end

                with_defaults, options = Kernel.filter_options options,
                    :model => Orocos::ROS::Spec::Node.new(nil,name),
                    :namespace => name_service.namespace
                options = options.merge(with_defaults)

                # We allow models to be specified by name
                if options[:model].respond_to?(:to_str)
                    options[:model] = Orocos.task_model_from_name(options[:model])
                end
                # Initialize the name from the model if it has one, and no name
                # was given
                if !name
                    if options[:model]
                        name = options[:model].name.gsub(/.*::/, '')
                    else
                        raise ArgumentError, "no name and no model given. At least one of the two must be provided."
                    end
                end
                super(name, options)

                if running?
                    @state_queue << :RUNNING
                else @state_queue << :STOPPED
                end
            end

            def ros_name
                _, basename = split_name(name)
                "/#{basename}"
            end

            def ==(other)
                other.class == self.class &&
                    other.name_service == self.name_service &&
                    other.name == self.name
            end

            # @return [Boolean] true if this Node is already running (somewhere)
            #   and false otherwise
            def running?
                !!server
            end

            def dead!(exit_status)
                exit_status = (@exit_status ||= exit_status)

                if !exit_status
                    Orocos.info "deployment #{name} exited, exit status unknown"
                elsif exit_status.success?
                    Orocos.info "deployment #{name} exited normally"
                elsif exit_status.signaled?
                    if @expected_exit == exit_status.termsig
                        Orocos.info "ROS node #{name} terminated with signal #{exit_status.termsig}"
                    elsif @expected_exit
                        Orocos.info "ROS node #{name} terminated with signal #{exit_status.termsig} but #{@expected_exit} was expected"
                    else
                        Orocos.warn "ROS node #{name} unexpectedly terminated with signal #{exit_status.termsig}"
                        @state_queue << :EXCEPTION
                    end
                else
                    Orocos.warn "ROS node #{name} terminated with code #{exit_status.to_i}"
                    @state_queue << :EXCEPTION
                end

                if @state_queue.last != :EXCEPTION
                    @state_queue << :STOPPED
                end

                @pid = nil 
                @server = nil
            end

            def configure(wait_for_completion = true)
                # This is a no-op for ROS nodes
            end

            def start(wait_for_completion = true)
                if running?
                    raise StateTransitionFailed, "#{self} is already running"
                end

                spawn
                if wait_for_completion
                    wait_running
                end
            end

            def stop(wait_for_completion = true)
                if !running?
                    raise StateTransitionFailed, "#{self} is not running"
                end
                kill
                if wait_for_completion
                    join
                end
            end

            def kill
                ::Process.kill('INT', @pid)
            end

            def join
                return if !running?

                begin
                    ::Process.waitpid(pid)
                    exit_status = $?
                        dead!(exit_status)
                rescue Errno::ECHILD
                end
            end

            def cleanup(wait_for_completion = true)
                # This is no-op for ROS nodes
            end

            def reset_exception(wait_for_completion = true)
                @state_queue << :STOPPED
                @exit_status = nil
            end

            # Starts this node
            def spawn
                args = name_mappings.to_command_line
                package_name, bin_name = *model.name.split("::")
                binary = Orocos::ROS.rosnode_find(package_name.gsub(/^ros_/, ''), bin_name)
                @pid = Utilrb.spawn binary, "__name:=#{name}", *args
            end

            # Waits for this node to be available
            def wait_running(timeout = nil)
                return if @server

                now = Time.now
                while true
                    begin
                        node = name_service.get name
                        @server = node.server
                        break
                    rescue Orocos::NotFound
                    end
                    if timeout && (Time.now - now) > timeout
                        raise Orocos::NotFound, "#{self} is still not reachable after #{timeout} seconds"
                    end
                end
            end

            # Applies the name mappings configured on this node on the given
            # name.
            #
            # In effect, given a name from {model}, it gives the name of the
            # corresponding object in the context of the running node
            def apply_name_mappings(name)
                name_mappings.apply(name)
            end

            # True if this task's model is a subclass of the provided class name
            #
            # This is available only if the deployment in which this task context
            # runs has been generated by orogen.
            def implements?(class_name)
                model.implements?(class_name)
            end

            def rtt_state
                @state_queue.last || @current_state
            end

            # Tests if this node is still available on the ROS system
            #
            # A node is reachable if it is still available on the ROS graph
            #
            # @return [Boolean]
            def reachable?
                name_service.has_node?(name)
                true
            rescue ComError
                false
            end

            def doc?; false end
            attr_reader :doc

            def each_property; end

            def port_names
                each_port.map(&:name)
            end

            def property_names; [] end
            def attribute_names; [] end
            def operation_names; [] end

            def has_port?(name)
                verify = true
                if model.spec_available?
                    verify = false
                end
                !!(find_output_port(name, verify) || find_input_port(name, verify))
            end

            def port(name, verify = true)
                p = (find_output_port(name, verify) || find_input_port(name, verify))
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} attached to node #{name}"
                end
                p
            end

            def input_port(name, verify = true)
                p = find_input_port(name, verify)
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} as a subscription of node #{self.name}"
                end
                p
            end

            def output_port(name, verify = true)
                p = find_output_port(name, verify)
                if !p
                    raise Orocos::NotFound, "cannot find topic #{name} as a publication of node #{self.name}"
                end
                p
            end
            
            # Finds the name of a topic this node is publishing
            #
            # @return [ROS::Topic,nil] the topic if found, nil otherwise
            def find_output_port(name, verify = true, wait_if_unavailable = true)
                each_output_port(verify) do |p|
                    if p.name == name || p.topic_name == name
                        return p
                    end
                end
                if verify && wait_if_unavailable
                    name_service.wait_for_update
                    find_output_port(name, true, false)
                end
            end
            
            # Finds the name of a topic this node is subscribed to
            #
            # @return [ROS::Topic,nil] the topic if found, nil otherwise
            def find_input_port(name, verify = true, wait_if_unavailable = true)
                each_input_port(verify) do |p|
                    if p.name == name || p.topic_name == name
                        return p
                    end
                end
                if verify && wait_if_unavailable
                    name_service.wait_for_update
                    find_input_port(name, true, false)
                end
            end

            def each_port(verify = true)
                return enum_for(:each_port, verify) if !block_given?
                each_output_port(verify) { |p| yield(p) }
                each_input_port(verify) { |p| yield(p) }
            end

            # Resolves the given topic name into a port name and a port model.
            # @return [(String,nil),(String,Orocos::Spec::ROSNode)]
            def resolve_output_topic_name(topic_name)
                model.each_output_port do |m|
                    if apply_name_mappings(m.topic_name) == topic_name
                        return m.name, m
                    end
                end
                return Topic.default_port_name(topic_name), nil
            end

            # Resolves the given topic name into a port name and a port model.
            # @return [(String,nil),(String,Orocos::Spec::ROSNode)]
            def resolve_input_topic_name(topic_name)
                model.each_input_port do |m|
                    if apply_name_mappings(m.topic_name) == topic_name
                        return m.name, m
                    end
                end
                return Topic.default_port_name(topic_name), nil
            end

            # Enumerates each "output topics" of this node
            def each_output_port(verify = true)
                return enum_for(:each_output_port, verify) if !block_given?

                if !verify
                    return @output_topics.values.each(&proc)
                end
                
                if !running?
                    model.each_output_port do |m|
                        yield(@output_topics[m.name] ||= OutputTopic.new(self, m.topic_name, m.topic_type, m.name))
                    end
                else
                    name_service.output_topics_for(ros_name).each do |topic_name, topic_type|
                        topic_type = name_service.topic_message_type(topic_name)
                        if ROS.compatible_message_type?(topic_type)
                            name, model = resolve_output_topic_name(topic_name)
                            topic = (@output_topics[name] ||= OutputTopic.new(self, topic_name, topic_type, model, name))
                            yield(topic)
                        end
                    end
                end
            end

            # Enumerates each "input topics" of this node
            def each_input_port(verify = true)
                return enum_for(:each_input_port, verify) if !block_given?

                if !verify
                    return @input_topics.values.each(&proc)
                end

                if !running?
                    model.each_input_port do |m|
                        yield(@input_topics[m.name] ||= InputTopic.new(self, m.topic_name, m.topic_type, m.name))
                    end
                else
                    name_service.input_topics_for(ros_name).each do |topic_name|
                        topic_type = name_service.topic_message_type(topic_name)
                        if ROS.compatible_message_type?(topic_type)
                            name, model = resolve_input_topic_name(topic_name)
                            topic = (@input_topics[name] ||= InputTopic.new(self, topic_name, topic_type, model, name))
                            yield(topic)
                        end
                    end
                end
            end

            def pretty_print(pp)
                pp.text "ROS Node #{name}"
                pp.breakable

                inputs  = each_input_port.to_a
                outputs = each_output_port.to_a
                ports = enum_for(:each_port).to_a
                if ports.empty?
                    pp.text "No ports"
                    pp.breakable
                else
                    pp.text "Ports:"
                    pp.breakable
                    pp.nest(2) do
                        pp.text "  "
                        each_port do |port|
                            port.pretty_print(pp)
                            pp.breakable
                        end
                    end
                    pp.breakable
                end
            end

            # @return [Orocos::Async::ROS::Node] an object that gives
            #   asynchronous access to this particular ROS node
            def to_async(options = Hash.new)
                Async::ROS::Node.new(name_service, server, name, options)
            end

            def to_proxy(options = Hash.new)
                options[:use] ||= to_async
                # use name service to check if there is already 
                # a proxy for the task
                Orocos::Async.proxy(name,options.merge(:name_service => name_service))
            end

            # Tests if this node is still available
            #
            # @raise [Orocos::ComError] if the node is not available anymore
            def ping
                if !name_service.has_node?(name)
                    raise Orocos::ComError, "ROS node #{name} is not available on the ROS graph anymore"
                end
            end

            def log_all_configuration(logfile)
                # n/a for ROS node
            end
        end
    end
end


