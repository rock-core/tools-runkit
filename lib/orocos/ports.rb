require 'utilrb/kernel/options'

module Orocos
    class Port
        attr_reader :task
        attr_reader :name
        attr_reader :type_name

        def ==(other)
            other.class == self.class &&
                other.task == self.task &&
                other.name == self.name
        end

        def pretty_print(pp) # :nodoc:
            pp.text "#{self.class.name} #{name}"

            if read? then pp.text "[R]"
            elsif write? then pp.text "[W]"
            else pp.text "[RW]"
            end
        end

        def disconnect_all
            refine_exceptions do
                do_disconnect_all
            end
        end

    private

        def refine_exceptions(other = nil)
            yield

        rescue NotFound
            if !other || task.has_task?(name)
                raise CORBA::NotFound, "port '#{name}' disappeared from task '#{task.name}'"
            else
                raise CORBA::NotFound, "port '#{other.name}' disappeared from task '#{other.task.name}'"
            end

        rescue CORBA::ConnError
            if !other || task.try_connect
                raise CORBA::ConnError, "cannot connect to task '#{task.name}' anymore"
            else
                raise CORBA::ConnError, "cannot connect to task '#{other.task.name}' anymore"
            end
        end
    end

    class InputPort
        def disconnect_from(output)
            if output.kind_of?(InputPort)
                raise ArgumentError, "expected an OutputPort, got #{output}"
            end
            output.disconnect_from(self)
            self
        end

        def connect_to(output_port, options = Hash.new)
            unless output_port.kind_of?(OutputPort)
                raise ArgumentError, "an input port can only connect to an output port"
            end
            output_port.connect_to self, options
            self
        end
    end

    class OutputPort
        def disconnect_from(input)
            refine_exceptions(input) do
                do_disconnect_from(input)
            end
            self
        end

        def connect_to(input_port, options = Hash.new)
            if !input_port.kind_of?(InputPort)
                raise ArgumentError, "an output port can only connect to an input port"
            elsif input_port.type_name != type_name
                raise ArgumentError, "trying to connect am output port of type #{type_name} to an input port of type #{input_port.type_name}"
            end

            options = validate_options options,
                :type => :data,
                :init => false,
                :pull => false,
                :size => nil,
                :lock => :lock_free

            if options[:type] == :buffer && !options[:size]
                raise ArgumentError, "you must provide a 'size' argument for buffer connections"
            elsif options[:type] == :data && options[:size]
                raise ArgumentError, "there are no 'size' argument to data connections"
            end
            options[:size] ||= 0

            do_connect_to(input_port, options)
            self
        end
    end
end

