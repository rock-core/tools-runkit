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
                @name  = name
            end

            def through(&block)
                instance_eval(&block)
            end

            def find_device_port(type_name, device_name, ports)
                candidates = ports.find_all do |port|
                    port.type_name == type_name
                end

                if candidates.size > 1
                    selected = candidates.find_all { |p| p.name =~ /#{device_name}/i }
                    if selected.size > 1
                        raise SpecError, "ambiguous connection of #{device_name} to #{name}: #{selected.map(&:name).join(", ")} can be used for connection"
                    end
                    return *selected
                else
                    return *candidates
                end
            end

            def find_bus_port(bus, direction, type_name, port_name)
                # Search for an input port on the bus handler
                bus_ports = bus.send("each_#{direction}").
                    find_all { |p| p.type_name == type_name }

                candidate = bus_ports.find { |p| p.name == "in" } ||
                    bus_ports.find { |p| p.name == port_name }

                if candidate
                    candidate
                elsif bus.task_model.dynamic_input_port?(port_name, type_name)
                    Port.create(direction, bus, port_name, type_name, nil)
                end
            end

            # Returns the set of connections needed to properly connect the
            # driver +driver+ on this bus, as handled by the subsystem +bus+
            #
            # This is driven by the following rules:
            #  * we check first the driver side, to see what it requires.
            #    Namely, we check if at least an input and/or an output port are
            #    available.
            #  * if more than one port of either type is available,
            #    disambiguation is done on the device name.
            #  * if the driver requires an output port and/or an input port,
            #    such ports are searched for on the bus side. We search for
            #    static ports named "#{device_name}" and #{device_name}w". If
            #    none are available, an input port named "in" is searched for.
            #    Finally, either ports are tested against dynamic port
            #    declarations.
            def connect(scope, device_name, bus_model, driver_model)
                data_type = bus_model.message_type_name
                result    = []

                # Search for ports on driver_model
                input_port  = find_device_port(data_type, device_name, driver_model.each_input)
                output_port = find_device_port(data_type, device_name, driver_model.each_output)

                if !(output_port || input_port)
                    raise SpecError, "#{driver_model.name} offers neither input nor output means of connection to #{name}"
                end

                if output_port
                    bus_input = find_bus_port(bus_model, "input", data_type, "#{device_name}w")
                    if !bus_input
                        raise SpecError, "cannot find a input on #{name} for #{device_name}"
                    end
                    result << [output_port.bind_to(scope, device_name), bus_input.bind_to(scope, name), nil]
                end

                if input_port
                    bus_output = find_bus_port(bus_model, "output", data_type, device_name)
                    if !bus_output
                        raise SpecError, "cannot find an output on #{name} for #{device_name}"
                    end
                    result << [bus_output.bind_to(scope, name), input_port.bind_to(scope, device_name), nil]
                end
                result
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


