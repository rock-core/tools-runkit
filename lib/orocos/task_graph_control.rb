require 'orogen'
require 'task_graph'
require 'utilrb/pkgconfig'
require 'orocos'

module Graph

    class TaskGraphControl

        # Loads the given components
        def self.components(*names)
            @components = Hash.new
            names.each do |n|
                pkg = Utilrb::PkgConfig.new("orogen-#{n}")
                @components[n] = Orocos::Generation::Component.load(pkg.deffile)
            end

            print "Loaded components "
            @components.each do |k,v|
                print "'#{k}' "
            end
            puts

            yield
        end

        # Checks all ports of all nodes
        def self.check_nodes(nodes)
            nodes.each do |k,v|
                puts "Checking incoming and outgoing ports for node '#{k}'"

                v.incoming do |a|
                    check_port_internal(a)
                end

                v.outgoing do |a|
                    check_port_internal(a)
                end
 
            end
        end

        # Start a task node network
        # TODO: Not tested!
        def self.start(nodes, &block)

            puts "Starting processes and wiring tasks..."

            # Start processes
            names = @components.keys.dup
            names << Hash[:wait => 5, :output => '%m-log.txt']
            Dir.chdir 'log' do
                Orocos::Process.spawn(*names, &block)
            end

            # Wire tasks
            @tasks = Hash.new

            puts "Running tasks:"
            results = Orocos.enum_for(:each_task).find_all do |task|
                puts "+ #{task.name}"
            end

            # Try to find tasks defined in the task graph by searching the currently running tasks
            nodes.each do |k,v|
                found = false
                results = Orocos.enum_for(:each_task).find_all do |task|
                    if task.implements?(k)
                        @tasks[k] = task
                        found = true
                    end
                end

                if !found
                    raise "Unable to find task #{k}!"
                end
            end

            # Configure all tasks
             @tasks.each do |k,v|
                v.configure
            end

            # Connect ports
            nodes.each do |k,v|
                v.incoming do |a|
                    connect_ports_real(a)
                end
            end
        end

        protected
        def self.connect_ports_real(task_port_pair)
            dst_port = task_port_pair[:dst]
            dst_task = dst_port.parent
            src_port = task_port_pair[:src]
            src_task = src_port.parent

            # Get source task
            if !@tasks.key?(src_task.name)
                raise "Unable to find source task (#{src_task.name})!"
            end
            src_task_real = @tasks[src_task.name]

            # Get destination task
            if !@tasks.key?(dst_task.name)
                raise "Unable to find destination task (#{dst_task.name})!"
            end
            dst_task_real = @tasks[dst_task.name]

            # Check for the source port
            if !src_task_real.has_port?(src_port.name)
                raise "Unable to find source port (#{src_task.name}.#{src_port.name})!"
            end
            src_port_real = src_task_real.port(src_port.name)

            # Check for the destination port
            if !dst_task_real.has_port?(dst_port.name)
                raise "Unable to find destination port (#{dst_task.name}.#{dst_port.name})!"
            end
            dst_port_real = dst_task_real.port(dst_port.name)

            src_port_real.connect_to(src_port_real)

            puts "Ports successfully connected (#{src_task.name}.#{src_port.name} -> #{dst_task.name}.#{dst_port.name})!"
        end

        # Tries to find a task within the available components
        protected
        def self.find_task(type)
            result = nil

            @components.each do |k,v|
                v.tasks.each do |t|
                    if t.name == type
                        result = t
                    end
                end
            end
    
            if result == nil
                raise "no task implements #{type}"
            end
    
            result
        end

        # Tries to retrieve exactly one port with the given name from the given task
        protected
        def self.find_port(task, portname)
            ports = Array.new

            # Search all (static) ports
            task.all_ports.each do |p|
                # Check for port names
                if p.name == portname
                    ports << p
                end
            end

            # Search also all dynamic ports
            task.dynamic_ports.each do |p|
                # p.name is a regex, so try to match the rule
                if p.name =~ portname
                    ports << p
                end
            end

            if ports.length == 0
                raise "No ports found matching the given name (#{portname})!"
            end

            if ports.length > 1
                raise "More than one port found matching the given name (#{portname})!"
            end

            ports[0]
        end

        # Checks the incoming and outgoing ports for a single task port pair
        protected
        def self.check_port_internal(task_port_pair)
            src = task_port_pair[:src]
            src_task = find_task(src.parent.name)
            src_port = find_port(src_task, src.name)

            dst = task_port_pair[:dst]
            dst_task = find_task(dst.parent.name)
            dst_port = find_port(dst_task, dst.name)

            puts "+ Checking port types for #{src_task.name}.#{src_port.name} -> #{dst_task.name}.#{dst_port.name}"

            if src_port.type != dst_port.type
                raise "Incompatible types found (#{src_port.type.name}, #{dst_port.type.name})"
            end
        end
    end
end

Graph::TaskGraphControl.components('lowlevel') do
    can = Graph::TaskNode.new("can::Task")
    hbridge = Graph::TaskNode.new("hbridge::Task")

    can.hbridge.connect_to(hbridge.can_in, :type => :buffer, :size => 20, :required => true)
    hbridge.can_out.connect_to(can.whbridge, :type => :buffer, :size => 20, :required => true)
    
    Graph::TaskGraphControl.check_nodes(Graph::TaskNode::nodes)
    Graph::TaskGraphControl.start(Graph::TaskNode::nodes)
end


