require 'spec'

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
            @toplevel = Array.new
            @selections = Hash.new
            @available_tasks = Array.new

            @subsystems           = Hash.new
            @communication_busses = Hash.new
        end

        attr_accessor :system
        attr_accessor :robot
        attr_reader :selections
        attr_reader :toplevel

        attr_reader :communication_busses
        attr_reader :subsystems

        def add(name)
            @toplevel << system.get(name)
        end

        def select(mappings)
            mappings.each do |from_name, to_name|
                @selections[from_name] = system.get(to_name)
            end
        end

        attr_reader :available_tasks

        # Pick up the right system inside +models+
        def disambiguate(required_model, models)
            # Narrow the set of models by looking at the available task contexts
            models.delete_if do |task_model|
                available_tasks.all? { |available_model_name, _| available_model_name != task_model.name }
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
            _, task = available_tasks.find { |model_name, task| model_name == model.name }
            if !task
                raise Orocos::Spec::ConfigError, "no task of model #{model.name} is currently deployed"
            end
            task
        end

        def com_bus(bus)
            if task = communication_busses[bus.name]
                task
            else
                if handling_model = system.drivers[bus.name]
                    communication_busses[bus.name] = handling_model.instanciate(self)
                else
                    raise Spec::SpecError, "no device driver for #{name}"
                end
            end
        end

        def run(*deployments)
            Orocos::Process.spawn(*deployments) do
                available_tasks.clear

                Orocos.each_task do |task|
                    available_tasks << [task.getModelName, task]
                end
                # Instanciate all required subsystems
                @instances = toplevel.map do |sys|
                    sys.instanciate(self)
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
        end
    end
end

