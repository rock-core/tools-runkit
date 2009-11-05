module Orocos
    module Spec
        # This class represents a communication bus on the robot, i.e. a device
        # that multiplexes and demultiplexes I/O for device modules
        class CommunicationBus
            attr_reader :robot
            attr_reader :name

            attr_reader :devices

            def initialize(robot, name, options = Hash.new)
                @robot = robot
                @name   = name
            end

            def through(&block)
                instance_eval(&block)
            end

            # Used by the #through call to override com_bus specification.
            def device(name, options = Hash.new)
                # Check that we do have the configuration data for that device,
                # and declare it as being passing through us.
                if options[:com_bus] || options['com_bus']
                    raise SpecError, "cannot use the 'com_bus' option in a through block"
                end
                options[:com_bus] = self
                robot.device(name, options)
            end
        end

        # This class represents a device on the system, i.e. a component
        # (software or hardware) that is an I/O for the system
        class Device
            attr_reader :robot
            attr_reader :name
            attr_reader :trigger
            attr_reader :com_bus

            def initialize(robot, name, options = Hash.new)
                options = Kernel.validate_options options, :period => nil,
                    :triggered_by => nil,
                    :com_bus => nil

                if options[:period] && options[:triggered_by]
                    raise SpecError, "a device cannot be both periodic and explicitely triggered"
                end

                @robot   = robot
                @name    = name.to_str
                @trigger = options.delete(:period) || options.delete(:triggered_by)
                @com_bus = options.delete(:com_bus)
            end

            def periodic?; @trigger.kind_of?(Numeric) end
            def period; trigger if periodic? end
        end

        # This class models a robot. For now, it represents the devices that the
        # robot has, and how they are connected to communication busses.
        class Robot
            attr_reader :name

            class << self
                attribute(:robots) { Hash.new }
            end

            def self.[](name)
                @robots[name]
            end

            def initialize(name)
                @name = name
                Robot.robots[name] = self

                @com_busses = Hash.new
                @devices    = Hash.new
            end

            attr_reader :com_busses
            attr_reader :devices

            def com_bus(name)
                com_busses[name] = CommunicationBus.new(self, name)
            end

            def through(com_bus, &block)
                bus = com_busses[com_bus]
                if !bus
                    raise SpecError, "communication bus #{com_bus} does not exist"
                end
                bus.through(&block)
                bus
            end

            def device(name, options = Hash.new)
                if devices[name]
                    raise SpecError, "device #{name} is already defined"
                end

                devices[name] = Device.new(self, name, options)
            end
        end
    end
end


