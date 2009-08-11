require 'pp'
#require 'orocos'
#require 'orogen'

module Graph

    class State
        STOPPED = 1
        STARTING = 2
        STARTED = 3
        STOPPING = 4
    end

    class TaskPort
        attr_reader :name
        attr_reader :parent
        attr_accessor :required
        attr_accessor :in_ports
        attr_accessor :out_ports

        def initialize(parent, name)
            @parent = parent
            @name = name
            @peers = Hash.new
            @required = false
            @in_ports = Array.new
            @out_ports = Array.new
        end

        def parentname; @parent.name  end
        def peers;      @peers.values end

        def connect_to(port, attr = Hash.new)
            if !port.is_a?(TaskPort)
                raise "Ports may only be connected to ports!"
            end

            if (@peers.has_key?(port.name))
                raise "Port '#{@task.name}.#{@name}' already connected to port #{port.taskname}.#{port.name}'!"
            end

            if (attr.has_key?(:required))
                @required = attr[:required]
            end

            @peers[port.name] = Array.new
            @peers[port.name] << port << attr

            port.in_ports << self
            @out_ports << port
        end
    end

    class TaskNode
        attr_reader :name

        def initialize(name)
            @name = name
            @state = State::STOPPED
            @ports = Hash.new
        end

        def method_missing(m, *args)
            m = m.to_s

            if !@ports.has_key?(m)
                @ports[m] = TaskPort.new(self, m)
            end

            @ports[m]
        end

        def incoming(required_only = false)
            @ports.each do |k,v|
                v.in_ports.each do |p|
                    if ((!required_only) || (p.required))
                        yield :src => v, :dst => p
                    end
                end
            end
        end

        def outgoing(required_only = false)
            @ports.each do |k,v|
                if ((!required_only) || (v.required))
                    v.out_ports.each do |p|
                        yield :src => v, :dst => p
                    end
                end
            end
        end
 
    end
end

#n1 = Graph::TaskNode.new("Task1")
#n2 = Graph::TaskNode.new("Task2")

#n1.bla.connect_to(n2.blubbx, :XXX => 1, :required => true)
#n2.blubb.connect_to(n1.blax, :YYY => 2, :required => true)

#n1.incoming(true) do |a|
#    puts "In:  #{a[:src].parentname}.#{a[:src].name} -> #{a[:dst].parentname}.#{a[:dst].name}"
#end
#n2.incoming(true) do |a|
#    puts "In:  #{a[:src].parentname}.#{a[:src].name} -> #{a[:dst].parentname}.#{a[:dst].name}"
#end

#n1.outgoing(true) do |a|
#    puts "Out: #{a[:src].parentname}.#{a[:src].name} -> #{a[:dst].parentname}.#{a[:dst].name}"
#end
#n2.outgoing(true) do |a|
#    puts "Out: #{a[:src].parentname}.#{a[:src].name} -> #{a[:dst].parentname}.#{a[:dst].name}"
#end
