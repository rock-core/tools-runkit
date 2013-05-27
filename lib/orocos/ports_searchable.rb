module Orocos
    # The PortsSearchable mixin provides collection classes with several
    # methods for searching ports.
    #
    # The class must provide a method port which must return an
    # array of all avalilable {Orocos::Port} instances
    module PortsSearchable
        # Searches for a port object that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_all_ports(type, port_name=nil)
            candidates = ports.dup

            # Filter out on type
            if type
                type_name =
                    if !type.respond_to?(:to_str)
                        type.name
                    else type.to_str
                    end
                candidates.delete_if { |port| port.type_name != type_name }
            end

            # Filter out on name
            if port_name
                if !port_name.kind_of?(Regexp)
                    port_name = Regexp.new(port_name) 
                end
                candidates.delete_if { |port| port.full_name !~ port_name }
            end
            candidates
        end

        # Searches for an input port object that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_all_input_ports(type, port_name)
            find_all_ports(type,port_name).delete_if { |port| !port.respond_to?(:writer) }
        end

        # Searches for an output object in that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_all_output_ports(type, port_name)
            find_all_ports(type,port_name).delete_if { |port| !port.respond_to?(:reader) }
        end

        # Searches for a port object that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_port(type, port_name=nil)
            candidates = find_all_ports(type, port_name)
            if candidates.size > 1
                type_name =
                    if !type.respond_to?(:to_str)
                        type.name
                    else type.to_str
                    end
                if port_name
                    raise ArgumentError, "#{type_name} is provided by multiple ports #{port_name}: #{candidates.map(&:name).join(", ")}"
                else
                    raise ArgumentError, "#{type_name} is provided by multiple ports: #{candidates.map(&:name).join(", ")}"
                end
            else candidates.first
            end
        end

        # Searches for a input port object that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_input_port(type, port_name=nil)
            candidates = find_all_input_ports(type, port_name)
            if candidates.size > 1
                type_name = if !type.respond_to?(:to_str)
                                type.name
                            else type.to_str
                            end
                if port_name
                    raise ArgumentError, "#{type_name} is provided by multiple input ports #{port_name}: #{candidates.map(&:name).join(", ")}"
                else
                    raise ArgumentError, "#{type_name} is provided by multiple input ports: #{candidates.map(&:name).join(", ")}"
                end
            else candidates.first
            end
        end

        # Searches for an output port object that matches the type and
        # name specification. +type+ is either a string or a Typelib::Type
        # class, +port_name+ is either a string or a regular expression.
        #
        # This is a helper method used in various places
        def find_output_port(type, port_name=nil)
            candidates = find_all_output_ports(type, port_name)
            if candidates.size > 1
                type_name = if !type.respond_to?(:to_str)
                                type.name
                            else type.to_str
                            end
                if port_name
                    raise ArgumentError, "#{type_name} is provided by multiple output ports #{port_name}: #{candidates.map(&:name).join(", ")}"
                else
                    raise ArgumentError, "#{type_name} is provided by multiple output ports: #{candidates.map(&:name).join(", ")}"
                end
            else candidates.first
            end
        end
    end
end
