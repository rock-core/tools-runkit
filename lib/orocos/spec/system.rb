module Orocos
    module Spec
        class Subsystem
            class << self
                attr_accessor :system
            end
            attr_reader :name
            def initialize(name = nil)
                @name = name || self.class.name
                if !@name
                    raise Orocos::Spec::ConfigError, "no name given to #{self}"
                end
            end

            def self.method_missing(name, *args)
                if args.empty?
                    if p = each_output.find { |p| p.name == name }
                        return p
                    elsif p = each_input.find { |p| p.name == name }
                        return p
                    end
                end
                super
            end

            def self.provides?(model)
                self <= model
            end
        end


        class Composition < Subsystem
            attr_reader :children

            def initialize
                super
                @children = Array.new
            end

            def pretty_print(pp)
                pp.text name
                pp.nest(2) do
                    pp.breakable
                    pp.seplist(children) do |child|
                        pp.text "- "
                        child.pretty_print(pp)
                    end
                end
            end

            class << self
                attr_accessor :name
                def to_s
                    "#<Subsystem/Composition: #{name}>"
                end

                def abstract; @abstract = true end
                def abstract?; @abstract end

                attribute(:children) { Hash.new }

                attribute(:outputs) { Array.new }
                attribute(:inputs)  { Array.new }

                attribute(:connections) { Array.new }

                def instanciate(engine)
                    if instance = engine.subsystems[name]
                        return instance
                    end

                    instance = new
                    children.each_value do |child_model|
                        instance.children << child_model.instanciate(engine)
                    end
                    
                    # Now check the need for communication busses. For that, we
                    # check our children 
                    com_bus = children.each_key.map do |model_name|
                        if device = engine.robot.devices[model_name]
                            device.com_bus
                        end
                    end.compact.to_set

                    com_bus.each do |name|
                        instance.children << engine.com_bus(name)
                    end

                    engine.subsystems[name] = instance
                    instance
                end

                def each_output(&block)
                    outputs.each(&block)
                end
                def each_input(&block)
                    inputs.each(&block)
                end

                # If true, we will try to autoconnect the user-added components
                # of this composition at configuration time.
                def autoconnect?; @autoconnect end

                def autoconnect
                    @autoconnect = true
                end

                def add(model_name)
                    task = system.get(model_name)
                    task.system = system
                    children[model_name] = task
                    task
                end

                def pretty_print(pp)
                    pp.nest(2) do
                        pp.breakable
                        pp.seplist(children) do |_, child|
                            pp.text "- "
                            child.pretty_print(pp)
                        end
                    end
                end

                def connect(input, output, policy = nil)
                    connections << [input, output, policy]
                end
            end
        end

        class TaskContext < Subsystem
            attr_reader :engine
            attr_reader :task

            def system_model
                self.class.system
            end

            def initialize(engine)
                super
                @engine = engine
            end

            def name
                task.name
            end

            def pretty_print(pp)
                pp.text "#{task.name} (#{self.class.name})"
            end

            def find_instance
                models = self.class.find_matching_models
                models.delete_if(&:abstract?)

                if models.size > 1
                    models = engine.disambiguate(self.class, models)
                end

                if models.size > 1
                    raise SpecError, "#{self.class.task_model.name} is provided by more than one task: #{models.map(&:name).join(", ")}"
                elsif models.empty?
                    raise SpecError, "no task model implements #{self.class.task_model.name}"
                end
                @task = engine.task_instance_of(models.first)
            end


            class << self
                attr_accessor :configure_block
                attr_accessor :task_model

                def abstract?; task_model.abstract? end
                def name; task_model.name end
                def to_s
                    "#<Subsystem/TaskContext: #{task_model.name}>"
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

                def find_matching_models
                    system.subsystems.
                        map { |_, sys| sys }.
                        to_value_set.
                        find_all do |sys|
                            sys.provides?(self)
                        end

                end

                def instanciate(engine)
                    task = new(engine)
                    task.find_instance
                    task
                end

                def output(name)
                    port = task_model.each_output_port.find { |p| p.name == name.to_s }
                    if !port
                        raise SpecError, "#{task_model} has no port named #{name}"
                    end
                    port
                end
                def input(name)
                    port = task_model.each_input_port.find { |p| p.name == name.to_s }
                    if !port
                        raise SpecError, "#{task_model} has no port named #{name}"
                    end
                    port
                end
                def each_input(&block)
                    task_model.each_input_port(&block)
                end
                def each_output(&block)
                    task_model.each_output_port(&block)
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

