# Module for replaying log files
module Orocos
    module Log
        # Simulates an output port based on log files.
        # It has the same behavior like an OutputReader
        class OutputReader
            #Handle to the port the reader is reading from
            attr_reader :port  

            #Creates a new OutputReader
            #
            #port => handle to the port the reader shall read from
            #policy => policy for reading data 
            #
            #see project orocos.rb for more information
            def initialize(port,policy=Hash.new)
                @port = port
                @buffer = Array.new

                policy = Orocos::Port.validate_policy(policy)
                @policy_type = policy[:type]
                @buffer_size = policy[:size]
                if ![:buffer, :data].include?(@policy_type)
                    raise ArgumentError, "type policy #{@policy_type} is not supported by OutputReader"
                end
            end

            #This method is called each time new data are availabe.
            def update(data) 
                if @policy_type == :buffer
                    @buffer.shift if @buffer.size == @buffer_size
                    @buffer << data
                end
            end

            #Clears the buffer of the reader.
            def clear_buffer 
                @buffer.clear
            end

            #Reads data from the associated port.
            def read
                return port.read if @policy_type == :data
                return @buffer.shift
            end
        end

        #Simulates a port based on log files
        #It has the same behavior like Orocos::OutputPorts
        class OutputPort

            #true -->  this port shall be replayed even if there are no connections
            attr_accessor :tracked         

            #name of the recorded port
            attr_reader :name 

            #name of the type as Typelib::Type object           
            attr_reader :type          

            #name of the type as it is used in ruby
            attr_reader :type_name      

            #connections between this port and InputPort ports that support a writer
            attr_reader :connections    

            #dedicated stream for simulating the port
            attr_reader :stream         

            #parent log task
            attr_reader :task          

            #number of readers which are using the port
            attr_reader :readers        

            #returns true if replay has started
            attr_reader :replay         

            @@default_policy = Hash.new         
            @@default_policy[:type] = :data

            #Defines a connection which is set through connect_to
            class Connection #:nodoc:
                attr_accessor :port,:writer
                def initialize(port,policy=Hash.new)
                    @port = port
                    @writer = port.writer(policy)
                end
            end

            #Pretty print for OutputPort.
            def pp(prefix = "  ")
                puts prefix + "#{task.name}.#{name}"
                puts prefix + "  tracked = #{@tracked}"
                puts prefix + "  readers = #{@readers.size}"
                @connections.each do |connection|
                    puts prefix + "  connected to #{connection.port.task.name}.#{connection.port.name}"
                end
            end

            # Give the full name for this port. It is the stream name.
            def full_name
                stream.name
            end

            #Creates a new object of OutputPort
            #
            #task => simulated task for which the port shall be created
            #stream => stream from which the port shall be created 
            def initialize(task,stream)
                raise "Cannot create OutputPort out of #{stream.class}" if !stream.instance_of?(Pocosim::DataStream)
                @stream = stream
                @name = stream.name.to_s.match(/\.(.*$)/)
                raise 'Stream name does not follow the convention TASKNAME.PORTNAME' if @name == nil
                @name = @name[1]
                @type = stream.type
                @type_name = stream.typename
                @task = task
                @connections = Array.new
                @current_data = nil
                @tracked = false
                @readers = Array.new
                @replay = false
            end

            #Sets the default policy for all ports.
            def  self.default_policy=(policy)
                @@default_policy = policy
            end

            #Creates a new reader for the port.
            def reader(policy = Hash.new)
                raise "can not initialize a reader for the unused port #{stream.name} after the replay has started" if !used? && replay==true
                new_reader = OutputReader.new(self,policy)
                @readers << new_reader
                return new_reader
            end

            #Returns true if the port has at least one connection or 
            #tracked is set to true.
            def used?
                return true if (!@connections.empty? || @tracked || !@readers.empty?)
                return false
            end

            #Returns the current sample data.
            def read()
                return @current_data
            end

            #If set to true the port is replayed.  
            def tracked=(value)
                raise "can not track unused port #{stream.name} after the replay has started" if !used? && replay
                @tracked = value
            end

            #Register InputPort which is updated each time write is called
            def connect_to(port,policy = @@default_policy)
                raise "can not connect the unused port #{stream.name} to #{port.name} after the replay has started" if !used? && replay
                raise "Cannot connect to #{port.class}" if(!port.instance_of?(Orocos::InputPort))
                @connections << Connection.new(port,policy)
                puts "setting connection: #{task.name}.#{name} --> #{port.task.name}.#{port.name}".green
            end

            #Feeds data to the connected ports
            def write(data)
                @current_data = data
                @connections.each do |connection|
                    connection.writer.write(@current_data)
                end
                @readers.each do |reader|
                    reader.update(data)
                end
            end

            #Disconnects all ports and deletes all readers 
            def disconnect_all
                @connections.clear
                @readers.clear
            end

            #Returns a new sample object
            def new_sample
                @type.new
            end

            #Clears all reader buffers 
            def clear_reader_buffers
                @readers.each do |reader|
                    reader.clear_buffer
                end
            end

            #Is called from align.
            #If replay is set to true, the log file streams are aligned and no more
            #streams can be added.
            def set_replay
                @replay = true
            end

            #Returns the number of samples for the port.
            def number_of_samples
                return @stream.size
            end
        end

        #Simulates task based on a log file.
        #Each stream is modeled as one OutputPort which supports the connect_to method
        class TaskContext
            attr_accessor :ports        #all simulated ports
            attr_reader :file_path      #path of the dedicated log file
            attr_reader :name
            attr_reader :state

            #Creates a new instance of TaskContext.
            #
            #* task_name => name of the task
            #* file_path => path of the log file
            def initialize(task_name,file_path)
                @ports = Hash.new
                @file_path = file_path
                @name = task_name
                @state = :replay
            end

            #Adds a new port to the TaskContext
            #
            #* file_path = path of the log file
            #* stream = stream which shall be simulated as OutputPort
            def add_port(file_path,stream)
                raise "You are trying to add ports to the task from different log files #{@file_path}; #{file_path}!!!" if @file_path != file_path
                log_port = OutputPort.new(self,stream)
                raise ArgumentError, "The log file #{file_path} is already loaded" if @ports.has_key?(log_port.name)
                @ports[log_port.name] = log_port
                return log_port
            end

            #TaskContexts do not have attributes. 
            #This is implementd to be compatible with TaskContext.
            def each_attribute
            end

            # Returns true if this task has a Orocos method with the given name.
            # In this case it always returns false because a TaskContext does not have
            # Orocos methods.
            # This is implementd to be compatible with TaskContext.
            def has_method?(name)
                return false;
            end

            # Returns true if this task has a command with the given name.
            # In this case it always returns false because a TaskContext does not have
            # command.
            # This is implementd to be compatible with TaskContext.
            def has_command?(name)
                return false;
            end

            # Returns true if this task has a port with the given name.
            def has_port?(name)
                name = name.to_s
                return @ports.has_key?(name)
            end

            # Iterates through all simulated ports.
            def each_port(&block)
                @ports.each_value do |port|
                    yield(port) if block_given?
                end
            end

            #Returns the port with the given name.
            #If no port can be found a exception is raised.
            def port(name, verify = true)
                name = name.to_str
                if @ports[name]
                    return @ports[name]
                else
                    raise NotFound, "no port named '#{name}' on log task '#{self.name}'"
                end
            end

            #Returns an array of ports where each port has at least one connection
            #or tracked set to true.
            def used_ports
                ports = Array.new
                @ports.each_value do |port|
                    ports << port if port.used?
                end
                return ports
            end

            #Returns an array of unused ports
            def unused_ports
                ports = Array.new
                @ports.each_value do |port|
                    ports << port if !port.used?
                end
                return ports
            end

            def find_all_ports(type_name, port_name)
                Orocos::TaskContext.find_all_ports(@ports.values, type_name, port_name)
            end
            def find_port(type_name, port_name)
                Orocos::TaskContext.find_port(@ports.values, type_name, port_name)
            end

            #Tries to find a OutputPort for a specefic data type.
            #For port_name Regexp is allowed.
            #If precise is set to true an error will be raised if more
            #than one port is matching type_name and port_name.
            def port_for(type_name, port_name, precise=true)
                STDERR.puts "#port_for is deprecated. Use either #find_all_ports or #find_port"
                if precise
                    find_port(type_name, port_name)
                else find_all_ports(type_name, port_name)
                end
            end

            #If set to true all ports are replayed
            #otherwise only ports are replayed which have a reader or
            #a connection to an other port
            def track(value)
                @ports.each_value do |port|
                    port.tracked = value
                    puts "set" + port.stream.name + value.to_s
                end
            end

            #Clears all reader buffers
            def clear_reader_buffers
                @ports.each_value do |port|
                    port.clear_reader_buffers
                end
            end

            #This is used to allow the following syntax
            #task.port_name.connect_to(other_port)
            def method_missing(m, *args) #:nodoc:
                m = m.to_s
                if m =~ /^(\w+)=/
                    name = $1
                    puts "Warning: Setting the property #{name} the TaskContext #{@name} is not supported"
                    return
                end
                return port(m )if has_port?(m)
                super(m.to_sym, *args)
            end
        end


        #Class for loading and replaying OROCOS log files.
        #
        #This class creates TaskContexts and OutputPorts to simulate the recorded tasks.
        class Replay
            #replay speed = 1 --> record time
            attr_accessor :speed            

            #array of all simulated tasks
            attr_reader :tasks

            #array of all simulated ports  
            attr_accessor :ports

            #set it to true if processing of qt events is needed during synced replay
            attr_accessor :process_qt_events             

            #hash of code blocks which are used to calculate the replayed timestamps
            #during replay 
            attr_reader :timestamps

            #indicates if the replayed data are replayed synchronously 
            #<0 means the replayed samples are behind the simulated times
            #>0 means that the replayed samples are replayed to fast
            attr_reader :out_of_sync_delta         

            def self.open(*path)
                replay = new
                replay.load(path)
                replay
            end

            #Creates a new instance of Replay
            #
            #If a path is givien load is called after
            #creation to load the log files.
            def initialize(*path)
                if !path.empty?
                    raise ArgumentError, "Replay.new(*path) is deprecated, use Replay.open(*path) to create and load files at the same time"
                end

                @default_timestamp = nil
                @timestamps = Hash.new
                @tasks = Hash.new
                @speed = 1
                @used_ports = Array.new
                @used_streams = Array.new
                @stream = nil
                @current_sample = nil
                @ports = Hash.new
                @process_qt_events = false
                @out_of_sync_delta = 0
            end

            #Sets a code block to calculate the default timestamp duricng replay.
            def default_timestamp(&block)
                if block_given? then @default_timestamp = block
                else @default_timestamp
                end
            end

            #Sets a code block for a special type to calculate the timestamp during repaly.
            def timestamp(type_name, &block)
                timestamps[type_name] = block
            end

            #If set to true all ports are replayed
            #otherwise only ports are replayed which have a reader or
            #a connection to an other port
            def track(value)
                @tasks.each_value do |task|
                    task.track(value)
                end
            end

            def find_all_ports(type_name, port_name)
                Orocos::TaskContext.find_all_ports(@ports.values, type_name, port_name)
            end
            def find_port(type_name, port_name)
                Orocos::TaskContext.find_port(@ports.values, type_name, port_name)
            end

            #Tries to find a OutputPort for a specefic data type.
            #For port_name Regexp is allowed.
            #If precise is set to true an error will be raised if more
            #than one port is matching type_name and port_name.
            def port_for(type_name, port_name, precise=true)
                STDERR.puts "#port_for is deprecated. Use either #find_all_ports or #find_port"
                if precise
                    find_port(type_name, port_name)
                else find_all_ports(type_name, port_name)
                end
            end

            #Tries to connect all input ports of the OROCOS task to simulated OutputPorts
            #
            #==Parameter:
            # *task => task to connect to
            # *port_mappings => hash to define port mappings {src_port_name => dst_port_name}
            # *ports_ignored => array of port names which shall be ignored
            #
            def connect_to(task,port_mappings = Hash.new ,port_policies = Hash.new,ports_ignored = Array.new)
                #start task if necessary 
                if task.state == :PRE_OPERATIONAL
                    task.configure
                end
                if task.state == :STOPPED
                    task.start
                end

                #to have a better user interface the hash is inverted 
                #port1 connect_to port2 is written as ('port1' => 'port2')
                port_mappings = port_mappings.invert

                task.each_port do |port|
                    if port.kind_of?(Orocos::InputPort) && !ports_ignored.include?(port.name)
                        begin
                            port_for(port.type_name,port_mappings[port.name]||port.name).connect_to(port,port_policies[port.name])
                        rescue ArgumentError => e
                            raise ArgumentError, "cannot find an output port for #{port.name}: #{e.message}"
                        end
                    end
                end
            end

            #Returns the simulated task with the given namen. 
            def task(name)
                raise "cannot find TaskContext which is called #{name}" if !@tasks.has_key?(name)
                return @tasks[name]
            end

            #Aligns all streams which have at least: 
            # *one reader 
            # *or one connections
            # *or track set to true.
            #
            #After calling this method no more ports can be tracked.
            def align()
                @used_ports = Array.new
                @used_streams = Array.new

                #get all streams which shall be replayed
                each_port do |port|
                    if port.used?
                        @used_ports << port
                        @used_streams << port.stream
                    end
                    port.set_replay
                end

                puts ""
                puts "Aligning streams --> all ports which are unused will not be loaded!!!"
                puts ""
                puts "Replayed Ports:"
                @used_ports.each {|port| port.pp}
                puts ""

                #join streams 
                @stream = Pocosim::StreamAligner.new(false, *@used_streams)
                @stream.rewind

                reset_time_sync
                return step
            end

            #Resets the simulated time.
            #This should be called after the replay was paused.
            def reset_time_sync
                @start_time = nil 
                @base_time  = nil
                @last_display = nil
            end

            #Gets the next sample and writes it to the ports which are connected
            #to the OutputPort and updates all its readers.
            #
            #If time_sync is set to true the method will wait until the 
            #simulated time delta is equal the recorded time delta.
            #
            #If a block is given it is called this the name of the replayed port.
            #
            #You can change the replay speed by changing the instance variable speed.
            #
            def step(time_sync=false,&block)
                #check if stream was generated otherwise call align
                if @stream == nil
                    return align
                end
                @current_sample = @stream.step
                return nil if @current_sample == nil
                index, time, data = @current_sample

                #wait if replay is faster than the desired speed and time_sync is set to true
                if time_sync
                    if getter = (timestamps[data.class.name] || default_timestamp)
                        time = getter[data]
                    end
                    @base_time ||= time
                    @start_time ||= Time.now
                    required_delta = time - @base_time
                    actual_delta   = Time.now - @start_time
                    wait = required_delta / @speed - actual_delta
                    if wait > 0.001
                        #process qt events every 0.1 sec
                        if @process_qt_events == true
                            while true
                                $qApp.processEvents()
                                break if !@start_time     #break if start_time was reseted throuh processEvents
                                actual_delta   = Time.now - @start_time
                                wait = required_delta / @speed - actual_delta
                                if wait > 0.001
                                    sleep [0.1,wait].min
                                else
                                    break
                                end
                            end
                        else
                            sleep(wait)
                        end
                    end

                    if !@last_display || (required_delta - @last_display > 0.1)
                        print "replayed %.1fs of log data\r" % [required_delta]
                        @last_display = required_delta
                    end

                    actual_delta   = @start_time ? Time.now - @start_time : 0
                    @out_of_sync_delta = required_delta / @speed - actual_delta
                end

                #write sample to connected ports
                @used_ports[index].write(data)
                yield(@used_ports[index].stream.name) if block_given?
                return @current_sample
            end

            #Gets the previous sample and writes it to the ports which are connected
            #to the OutputPort and updated its readers (see step).
            def step_back(time_sync=false,&block)
                #check if stream was generated otherwise call start

                if @stream == nil
                    start
                    return
                end

                @current_sample = @stream.step_back
                return nil if @current_sample == nil
                index, time, data = @current_sample

                #write sample to connected ports
                @used_ports[index].write(data)
                yield(@used_ports[index].stream.name) if block_given?
                return @current_sample
            end

            #Rewinds all streams and replays the first sample.
            def rewind()
                @stream.rewind
                step
            end

            #Runs through the log files until the end is reached.
            def run(&block)
                start()
                while step(true,&block) do
                end
            end

            #Iterates through all simulated ports.
            def each_port(&block)
                @tasks.each_value do |task|
                    task.each_port(&block)
                end
            end

            #Iterates through all simulated tasks
            def each_task (&block)
                @tasks.each_value do |task|
                    yield(task) if block_given?
                end
            end

            #Returns the current position of the replayed sample.
            def current_pos
                @stream.current_pos
            end

            #Returns the number of samples.
            def count_samples
                return @stream.count_samples
            end

            #Returns the time of the current sample.
            def time
                return @stream.time
            end

            #Returns true if the end of file is reached.
            def eof?
                return @stream.eof
            end

            #Seeks to the given position
            def seek(pos)
                @stream.seek(pos)
                #write all data to the ports
                0.upto(@stream.streams.length-1) do |index|
                    @used_ports[index].write(@stream.single_data(index))
                    yield(@used_ports[index].stream.name) if block_given?
                end
            end

            # Loads all the streams defined in the provided log file
            def load_log_file(file, path)
                result = []
                puts "  loading log file #{path}"
                file.streams.each do |s|
                    task_name = s.name.to_s.match(/^(.*)\./)
                    raise 'Stream name does not follow the convention TASKNAME.PORTNAME' if task_name == nil
                    task_name = task_name[1]
                    task = @tasks[task_name]
                    if !task
                        task = @tasks[task_name]= TaskContext.new(task_name, path)
                        result << task
                    end
                    if s.empty?
                        puts "    ignored empty stream #{s.name} (#{s.type_name})"
                    else
                        ports[s.name] = task.add_port(path,s)
                        puts "    loading stream #{s.name} (#{s.type_name})"
                    end
                end
                result
            end

            #Loads a log files and creates TaskContexts which simulates the recorded tasks.
            #You can either specify a single file or a hole directory. If you want to load
            #more than one directory or file simultaneously you can use an array.
            def load(path)
                tasks = Array.new
                return tasks if path == nil

                #check if path is an array
                if path.instance_of?(Array)
                    path.each do |p|
                        tasks.concat(load(p))
                    end
                    tasks.flatten
                #check if path is a directory
                elsif File.directory?(path)
                    path = File.expand_path(path)
                    all_files = Dir.enum_for(:glob, File.join(path, '*.*.log'))
                    by_basename = all_files.inject(Hash.new) do |h, path|
                        split = path.match(/^(.*)\.(\d+)\.log$/)
                        basename, number = split[1], Integer(split[2])
                        h[basename] ||= Array.new
                        h[basename][number] = path
                        h
                    end

                    pp by_basename
                    by_basename.each_value do |files|
                        args = files.compact.map do |path|
                            File.open(path)
                        end
                        args << Orocos.registry

                        logfile = Pocosim::Logfiles.new(*args.compact)
                        new_tasks = load_log_file(logfile, files.first)
                        tasks.concat(new_tasks)
                    end

                elsif File.file?(path)
                    file = Pocosim::Logfiles.open(path, Orocos.registry)
                    tasks.concat(load_log_file(file, path))
                else
                    raise ArgumentError, "Can not load log file: #{path} is neither a directory nor a file"
                end
                return tasks
            end

            #Clears all reader buffers.
            #This is usfull if you are changing the replay direction.
            def clear_reader_buffers
                @tasks.each_value do |task|
                    task.clear_reader_buffers
                end
            end

            #This is used to support the syntax.
            #log_replay.task 
            def method_missing(m,*args,&block) #:nodoc:
                return @tasks[m.to_s] if @tasks.has_key?(m.to_s)
                super
            end
        end
    end
end

