module Orocos
    class SimpleEngine
        # The configuration as a Hash. It can be loaded from a YAML file by
        # load_config
        attr_reader :configuration
        def load_config(file)
            @configuration = YAML.load(File.read(file))
        end

        def config(name)
            configuration[name]
        end

        # The set of already initialized instances
        attr_reader :instances

        def initialize
            @instances = Hash.new
            @configuration = Hash.new
            @toplevel = Hash.new
            @selections = Hash.new
            @available_tasks = Array.new
            @available_models = Set.new

            @subsystems           = Hash.new
            @communication_busses = Hash.new
            @connections          = Array.new
        end

        attr_accessor :system
        attr_accessor :robot
        attr_reader :selections
        attr_reader :toplevel
        attr_reader :connections

        attr_reader :communication_busses
        attr_reader :subsystems

        def add(model_name, options = Hash.new)
            options = Kernel.validate_options options, :as => model_name

            @toplevel[options[:as]] = system.get(model_name)
            self
        end

        def select(mappings)
            mappings.each do |from_name, to_name|
                @selections[from_name] = system.get(to_name)
            end
        end

        attr_reader :available_tasks
        attr_reader :available_models

        # Pick up the right system inside +models+
        def disambiguate(required_model, models)
            # Narrow the set of models by looking at the available task contexts
            models.delete_if do |task_model|
                !available_models.include?(task_model.name)
            end

            sel = selections[required_model.name]
            if models.size == 1
                if sel && models.first != sel
                    raise Orocos::Spec::SpecError, "#{sel.name} is explicitely selected for #{required_model.name}, but only #{models.first.name} is available in the running deployments"
                end
                models
            elsif sel
                [sel]
            else
                models
            end
        end

        def task_instance_of(model)
            candidates = available_tasks.find_all { |model_name, task| model_name == model.name }
            if candidates.empty?
                raise Orocos::Spec::ConfigError, "no task of model #{model.name} is currently deployed"
            elsif candidates.size > 1
                raise Orocos::Spec::ConfigError, "more than one candidate task found for #{model.name}: #{candidates.join(", ")}"
            end
            candidates.first.last
        end

        def com_bus(bus)
            if task = communication_busses[bus.name]
                task
            else
                if handling_model = system.drivers[bus.name]
                    communication_busses[bus.name] = handling_model.instanciate(self, bus.name)
                else
                    raise Spec::SpecError, "no device driver for #{name}"
                end
            end
        end

        def connect(scope, connection_set)
            connections.concat(connection_set)
        end

        def run(*deployments)
            Orocos::Process.spawn(*deployments) do
                available_tasks.clear
                available_models.clear

                Orocos.each_task do |task|
                    model = task.getModelName
                    available_tasks << [model, task]
                    available_models << model
                end
                puts available_models.inspect

                @connections = Array.new
                # Instanciate all required subsystems
                @instances = toplevel.map do |name, sys|
                    sys.instanciate(self, name)
                end


                pp self
            end
        end

        def pretty_print(pp)
            pp.text "Instance selection:"
            pp.nest(2) do
                instances.each do |sys|
                    pp.breakable
                    sys.pretty_print(pp)
                end
            end

            pp.breakable
            pp.breakable
            pp.text "Connections"
            pp.nest(2) do
                connections.each do |outp, inp, policy|
                    pp.breakable
                    pp.text "#{outp.task.name}.#{outp.name} => #{inp.task.name}.#{inp.name} (#{policy.inspect})"
                end
            end
        end
    end
end

