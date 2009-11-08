module Orocos
    module Spec
        class Port
            attr_reader :subsystem
            attr_reader :name
            attr_reader :type_name
            attr_reader :port_model

            attr_reader :scope
            attr_reader :subsystem_name

            def initialize(subsystem, name, type_name, port_model)
                @subsystem  = subsystem
                @name       = name
                @type_name  = type_name
                @port_model = port_model
            end

            def ==(other_port)
                if !scope || !other_port.scope
                    raise ArgumentError, "cannot compare two unbound ports"
                end
                scope == other_port.scope && subsystem_name == other_port.subsystem_name
            end

            def bind_to(scope, subsystem_name)
                if self.scope
                    raise ArgumentError, "#{self} is already bound to #{scope}.#{subsystem_name}"
                end
                if !scope.kind_of?(Class) || !(scope < Subsystem)
                    raise TypeError, "can only bind to a subsystem model"
                end
                result = dup
                result.instance_variable_set :@scope, scope
                result.instance_variable_set :@subsystem_name, subsystem_name.to_str
                result
            end

            def self.create(direction, parent_name, name, type_name, port_model)
                klass = if direction == "input"
                            InputPort
                        elsif direction == "output"
                            OutputPort
                        else
                            raise ArgumentError, "direction should be either 'input' or 'output', got #{direction}"
                        end

                klass.new(parent_name, name, type_name, port_model)
            end

            def instanciate(engine, scope)
                if !self.scope
                    raise ArgumentError, "trying to instanciate a non-bound port"
                elsif !(scope.model <= self.scope)
                    raise ArgumentError, "trying to instanciate from a non-compatible scope"
                end
                scope[subsystem_name].port(self)
            end
        end
        class InputPort < Port; end
        class OutputPort < Port; end

        class DynamicPortStub
            attr_reader :task
            attr_reader :name
            attr_reader :type_name

            def initialize(task, name, type_name)
                @task = task
                @name = name
                @type_name = type_name
            end
            def method_missing(m, *args, &block)
                if !@port
                    @port = @task.port(self, false)
                end

                @port.send(m, *args, &block)
            end
        end

        class Subsystem
            class << self
                attr_accessor :system
            end

            def model; self.class end

            attr_reader :engine
            attr_reader :name
            def initialize(engine, name)
                @engine = engine
                @name   = name || self.class.name
                if !@name
                    raise Orocos::Spec::ConfigError, "no name given to #{self}"
                end
            end

            def resolve_connections
                self
            end

            def to_s; "#<#{self.class}: #{name}>" end

            def self.method_missing(name, *args)
                #if args.empty?
                #    if p = each_output.find { |p| p.name == name }
                #        return p
                #    elsif p = each_input.find { |p| p.name == name }
                #        return p
                #    end
                #end
                super
            end

            def self.provides?(model)
                self <= model
            end
        end


        class Composition < Subsystem
            attr_reader :children
            attr_reader :connections

            def initialize(engine, name)
                super
                @children    = Hash.new
                @connections = Array.new
            end

            def [](name)
                children[name]
            end

            def port(bound_port)
                model.each_output do |p|
                    if p.name == bound_port.name && p.type_name == bound_port.type_name
                        return p.instanciate(engine, self)
                    end
                end
                model.each_input do |p|
                    if p.name == bound_port.name && p.type_name == bound_port.type_name
                        return p.instanciate(engine, self)
                    end
                end
                raise "no port #{bound_port.name} of type #{bound_port.type_name} in #{name}"
            end

            def pretty_print(pp)
                pp.text name
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(children) do |child_def|
                        pp.text "#{child_def.first}: "
                        child_def.last.pretty_print(pp)
                    end
                end
            end

            def connect(output, input, policy)
                connections << [output, input, policy]
            end

            class << self
                attr_accessor :name
                def to_s
                    "#<Subsystem/Composition: #{name}>"
                end

                def abstract; @abstract = true end
                def abstract?; @abstract end

                attribute(:children) { Hash.new }

                attribute(:outputs)  { Hash.new }
                attribute(:inputs)   { Hash.new }

                def exported_port?(port_model)
                    outputs.values.any? { |p| port_model == p } ||
                        inputs.values.any? { |p| port_model == p }
                end

                def each_output(&block)
                    if !@exported_outputs
                        @exported_outputs = outputs.map do |name, p|
                            p.class.new(self, name, p.type_name, p.port_model)
                        end
                    end
                    @exported_outputs.each(&block)
                end
                def each_input(&block)
                    if !@exported_inputs
                        @exported_inputs = inputs.map do |name, p|
                            p.class.new(self, name, p.type_name, p.port_model)
                        end
                    end
                    @exported_inputs.each(&block)
                end

                attribute(:connections) { Array.new }

                def instanciate(engine, name)
                    if instance = engine.subsystems[name]
                        return instance
                    end

                    # The complete set of connections that are necessary for
                    # this composition
                    connections = Array.new

                    # First of all, create the instance object and instances for
                    # its children
                    instance = new(engine, name)
                    children.each do |child_name, child_model|
                        instance.children[child_name] = child_model.instanciate(engine, child_name)
                    end

                    # Autoconnect these (if required), and add the explicit
                    # connections.
                    if autoconnect?
                        connections.concat compute_autoconnection
                    end
                    
                    # Now check the need for communication busses. For that, we
                    # check our children and instanciate/get the required
                    # busses, and add the necessary connections to the
                    # connection set.
                    com_bus = Hash.new { |h, k| h[k] = Array.new }
                    children.each do |child_name, child|
                        if device = engine.robot.devices[child_name]
                            com_bus[device.com_bus] << [child_name, child]
                        end
                    end
                    com_bus.each do |bus, subsystems|
                        bus_instance = engine.com_bus(bus)
                        instance.children[bus.name] = bus_instance
                        subsystems.each do |child_name, sys|
                            bus_connections = bus.connect(self, child_name, bus_instance.model, instance[child_name].model)
                            connections.concat(bus_connections)
                        end
                    end

                    connections.concat(self.connections)

                    if !connections.empty?
                        # Translate the connections from the model ports into
                        # the instance ports
                        connections = connections.map do |output_model, input_model, policy|
                            if !output_model.kind_of?(Port)
                                raise TypeError, "inconsistent type in connection set. Expected an instance of Spec::Port, got #{output_model}"
                            elsif !input_model.kind_of?(Port) 
                                raise TypeError, "inconsistent type in connection set. Expected an instance of Spec::Port, got #{input_model}"
                            end
                            [output_model.instanciate(engine, instance), input_model.instanciate(engine, instance), policy]
                        end

                        engine.connect(instance, connections)
                    end

                    engine.subsystems[name] = instance
                    instance
                end

                # Automatically compute the connections that can be done in the
                # limits of this composition, and returns the set.
                #
                # Connections are determined by port direction and type name.
                #
                # It raises AmbiguousConnections if autoconnection does not know
                # what to do.
                def compute_autoconnection
                    result = Array.new
                    child_inputs  = Hash.new { |h, k| h[k] = Array.new }
                    child_outputs = Hash.new { |h, k| h[k] = Array.new }

                    # Gather all child input and outputs
                    children.each do |name, sys|
                        sys.each_input do |in_port|
                            if !exported_port?(in_port)
                                child_inputs[in_port.type_name] << in_port.bind_to(self, name)
                            end
                        end

                        sys.each_output do |out_port|
                            if !exported_port?(out_port)
                                child_outputs[out_port.type_name] << out_port.bind_to(self, name)
                            end
                        end
                    end

                    # Make sure there is only one input for one output, and add the
                    # connections
                    child_inputs.each do |typename, in_ports|
                        out_ports = child_outputs[typename]
                        out_ports.delete_if do |outp|
                            in_ports.any? { |inp| inp.subsystem == outp.subsystem }
                        end
                        next if out_ports.empty?

                        if in_ports.size > 1
                            raise AmbiguousConnections, "multiple input candidates for #{typename}: #{in_ports.map(&:name)}"
                        elsif out_ports.size > 1
                            raise AmbiguousConnections, "multiple output candidates for #{typename}: #{out_ports.map(&:name)}"
                        end

                        result << [out_ports.first, in_ports.first, nil]
                    end

                    result
                end

                # If true, we will try to autoconnect the user-added components
                # of this composition at configuration time.
                def autoconnect?; @autoconnect end

                # Enable autoconnection for this composition
                def autoconnect; @autoconnect = true end

                # Explicitely connect a child's output port to another child's
                # input port, using the provided connection policy
                def connect(input, output, policy = nil)
                    connections << [input, output, policy]
                end

                # Add a subsystem to this composition
                def add(model_name, options = Hash.new)
                    task = system.get(model_name)
                    task.system = system
                    children[model_name] = task
                    task
                end

                def pretty_print(pp) # :nodoc:
                    pp.nest(2) do
                        pp.breakable
                        pp.seplist(children) do |_, child|
                            pp.text "- "
                            child.pretty_print(pp)
                        end
                    end
                end
            end
        end

        class TaskContext < Subsystem
            attr_reader :task

            def system_model
                self.class.system
            end

            def task_name; task.name end

            def pretty_print(pp)
                pp.text "#{task.name} (#{self.class.name})"
            end

            def to_s; "#<#{self.class}: #{task.name}>" end

            def initialize(engine, name)
                super
                @task = engine.task_instance_of(model)
            end

            def port(bound_port, with_dynamic = true)
                task.each_port do |p|
                    if p.name == bound_port.name && p.type_name == bound_port.type_name
                        return p
                    end
                end
                if with_dynamic && task.model.dynamic_port?(bound_port.name, bound_port.type_name)
                    return DynamicPortStub.new(self, bound_port.name, bound_port.type_name)
                end
                raise "no port #{bound_port.name} of type #{bound_port.type_name} in #{task}"
            end

            class << self
                attr_accessor :configure_block
                attr_accessor :task_model

                def abstract?; task_model.abstract? end
                def name; task_model.name end
                def to_s
                    "#<Subsystem/TaskContext(#{task_model.name})>"
                end

                def new_submodel(task_model)
                    model = Class.new(self)
                    if !task_model
                        raise "no task model given"
                    end

                    model.task_model = task_model
                    model
                end

                def pretty_print(pp)
                    pp.text "task: #{name}"
                end

                def find_matching_models(engine)
                    system.subsystems.
                        map { |_, sys| sys }.
                        to_value_set.
                        find_all do |sys|
                            sys.provides?(self) && !sys.abstract?
                        end


                end

                def instanciate(engine, name)
                    models = find_matching_models(engine)
                    if models.size > 1
                        models = engine.disambiguate(self, models)
                    end
                    if models.size > 1
                        raise SpecError, "#{self.name} is provided by more than one task: #{models.map(&:name).join(", ")}"
                    elsif models.empty?
                        raise SpecError, "no task model implements #{self.name}"
                    end

                    models.first.new(engine, name)
                end

                def output(name)
                    port = each_output.find { |p| p.name == name.to_s }
                    if !port
                        raise SpecError, "#{task_model} has no port named #{name}"
                    end
                    port
                end
                def input(name)
                    port = each_input.find { |p| p.name == name.to_s }
                    if !port
                        raise SpecError, "#{task_model} has no port named #{name}"
                    end
                    port
                end
                def each_input(&block)
                    if !@input_ports
                        @input_ports = task_model.each_input_port.
                            map { |p| InputPort.new(self, p.name, p.type_name, p) }
                    end
                    @input_ports.each(&block)
                end
                def each_output(&block)
                    if !@output_ports
                        @output_ports = task_model.each_output_port.
                            map { |p| OutputPort.new(self, p.name, p.type_name, p) }
                    end
                    @output_ports.each(&block)
                end
            end
        end

        class System < Composition
            class << self
                attribute(:robots)     { Hash.new }
                attribute(:drivers)    { Hash.new }
                attribute(:subsystems) { Hash.new }

                attribute(:configuration) { Hash.new }

                def to_s
                    "#<SystemModel>"
                end

                def define_task_context_model(task_model)
                    if model = subsystems[task_model.name]
                        return model
                    end
                    
                    task_model = if parent_model = task_model.superclass
                                     parent = define_task_context_model(parent_model)
                                     parent.new_submodel(task_model)
                                 else
                                     TaskContext.new_submodel(task_model)
                                 end

                    task_model.system = self
                    subsystems[task_model.name] = task_model
                end

                def load_all_models
                    subsystems['RTT::TaskContext'] = Orocos::Spec::TaskContext
                    rtt_taskcontext = Orocos::Generation::Component.standard_tasks.
                        find { |task| task.name == "RTT::TaskContext" }
                    Orocos::Spec::TaskContext.task_model = rtt_taskcontext

                    Orocos.available_task_models.each do |name, task_lib|
                        next if subsystems[name]

                        task_lib   = Orocos::Generation.load_task_library(task_lib)
                        task_model = task_lib.find_task_context(name)
                        define_task_context_model(task_model)
                    end
                end

                def new_submodel
                    Class.new(self)
                end

                def load(file)
                    text = File.read(file)
                    Kernel.eval(text, binding)
                    self
                end

                def robot(name, &block)
                    new_model = Robot.new(name)
                    robots[name] = new_model
                    new_model.instance_eval(&block)
                    new_model
                end

                def subsystem(name, &block)
                    new_model = Class.new(Composition)
                    new_model.name = name
                    new_model.system = self
                    subsystems[name] = new_model
                    new_model.instance_eval(&block)
                    new_model
                end

                def message_type(klass_name, type_name)
                    sys = get(klass_name)
                    sys.class_eval do
                        class << self
                            attr_reader :message_type_name
                        end
                    end
                    sys.instance_variable_set :@message_type_name, type_name
                end

                def get(name)
                    if result = subsystems[name]
                        result
                    elsif defined?(super)
                        super
                    else
                        raise SpecError, "there is no subsystem named '#{name}'"
                    end
                end

                def device_drivers(mapping)
                    mapping.each do |names, model|
                        names = [names] if !names.respond_to?(:to_ary)

                        names.each do |name|
                            subsystems[name] = drivers[name] = get(model)
                        end
                    end
                    self
                end

                def configure(task_model, &block)
                    task = get(task_model)
                    if task.configure_block
                        raise SpecError, "#{task_model} already has a configure block"
                    end
                    task.configure_block = block
                    self
                end

                def pretty_print(pp)
                    inheritance = Hash.new { |h, k| h[k] = Set.new }
                    inheritance["Orocos::Spec::Subsystem"] << "Orocos::Spec::Composition"

                    pp.text "Subsystems"
                    pp.nest(2) do
                        pp.breakable
                        subsystems.sort_by { |name, sys| name }.
                            each do |name, sys|
                                inheritance[sys.superclass.name] << sys.name
                                pp.text "#{name}: "
                                pp.nest(2) do
                                    pp.breakable
                                    sys.pretty_print(pp)
                                end
                                pp.breakable
                            end
                    end

                    pp.breakable
                    pp.text "Models"
                    queue = [[0, "Orocos::Spec::Subsystem"]]

                    while !queue.empty?
                        indentation, model = queue.pop
                        pp.breakable
                        pp.text "#{" " * indentation}#{model}"

                        children = inheritance[model].
                            sort.reverse.
                            map { |m| [indentation + 2, m] }
                        queue.concat children
                    end
                end
            end
        end
    end
end

