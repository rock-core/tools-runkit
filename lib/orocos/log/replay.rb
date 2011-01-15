# Module for replaying log files
module Orocos
    module Log
        # Simulates an output port based on log files.
        # It has the same behavior like an OutputReader
        class OutputReader
            #Handle to the port the reader is reading from
            attr_reader :port

            #filter for log data 
            #the filter is applied during read
            #the buffer is not effected 
            attr_accessor :filter

            #Creates a new OutputReader
            #
            #port => handle to the port the reader shall read from
            #policy => policy for reading data 
            #
            #see project orocos.rb for more information
            def initialize(port,policy=default_policy)
                policy = default_policy if !policy
                @port = port
                @buffer = Array.new
                @filter, policy = Kernel.filter_options(policy,[:filter])
                @filter = @filter[:filter]
                policy = Orocos::Port.validate_policy(policy)
                @policy_type = policy[:type]
                @buffer_size = policy[:size]
                @last_update = Time.now
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
                @last_update = port.last_update
                if @policy_type == :data
                  return @filter.call(port.read) if @filter
                  return port.read
                else
                  return @filter.call(@buffer.shift) if @filter
                  return @buffer.shift
                end
            end
           
            #Reads data from the associated port.
            #Return nil if no new data are available
            def read_new
              return nil if @last_update == port.last_update 
              read
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

            #returns the system time when the port was updated with new data
            attr_reader :last_update

            #filter for log data
            #the filter is applied before all connections and readers are updated 
            #if you want to apply a filter only for one connection or one reader do not set 
            #the filter here.
            #the filter must be a proc, lambda, method or object with a function named call.
            #the signature must be:
            #new_massage call(old_message)
            attr_accessor :filter

            class << self
              attr_accessor :default_policy
            end
            self.default_policy = Hash.new
            self.default_policy[:type] = :data

            #Defines a connection which is set through connect_to
            class Connection #:nodoc:
                attr_accessor :port,:writer,:filter
                def initialize(port,policy=Hash.new)
                    @port = port
                    policy =  OutputPort::default_policy if !policy
                    @filter, policy = Kernel.filter_options(policy,[:filter])
                    @filter = @filter[:filter]
                    @writer = port.writer(policy)
                end

                def update(data)
                  if @filter 
                    @writer.write(@filter.call data)
                  else
                    @writer.write(data)
                  end
                end
            end

            def filter=(filter)
              @filter=filter
              self.tracked=true
            end

            #Pretty print for OutputPort.
	    def pretty_print(pp)
                pp.text "#{task.name}.#{name}"
		pp.nest(2) do
		    pp.breakable
		    pp.text "tracked = #{@tracked}"
		    pp.breakable
		    pp.text "readers = #{@readers.size}"
		    pp.breakable
		    pp.text "filtered = #{(@filter!=nil).to_s}"
		    @connections.each do |connection|
			pp.breakable
			pp.text "connected to #{connection.port.task.name}.#{connection.port.name} (filtered = #{(connection.filter!=nil).to_s})"
		    end
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
                raise "Cannot create OutputPort out of #{stream.class}" if !stream.instance_of?(Pocolog::DataStream)
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
                @last_update = Time.now
            end

            #Creates a new reader for the port.
            def reader(policy = OutputPort::default_policy,&block)
                policy[:filter] = block if block
                self.tracked = true
                new_reader = OutputReader.new(self,policy)
                @readers << new_reader
                return new_reader
            end

            #Returns true if the port has at least one connection or 
            #tracked is set to true.
            def used?
                return @tracked
            end

            #Returns the current sample data.
            def read()
                return yield @current_data if block_given?
                return @current_data
            end

            #If set to true the port is replayed.  
            def tracked=(value)
                raise "can not track unused port #{stream.name} after the replay has started" if !used? && replay
                @tracked = value
            end

            #Register InputPort which is updated each time write is called
            def connect_to(port,policy = OutputPort::default_policy,&block)
                self.tracked = true
                policy[:filter] = block if block
                raise "Cannot connect to #{port.class}" if(!port.instance_of?(Orocos::InputPort))
                @connections << Connection.new(port,policy)
                puts "setting connection: #{task.name}.#{name} --> #{port.task.name}.#{port.name}"
            end

            #Feeds data to the connected ports and readers
            def write(data)
                @last_update = Time.now
                @current_data = @filter ? @filter.call(data) : data
                @connections.each do |connection|
                    connection.update(@current_data)
                end
                @readers.each do |reader|
                    reader.update(@current_data)
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

            #pretty print for TaskContext
	    def pretty_print(pp)
                pp.text "#{name}:"
		pp.nest(2) do
		    pp.breakable
		    pp.text "log file: #{file_path}"
		    pp.breakable
		    pp.text "port(s):"
		    pp.nest(2) do
			@ports.each_value do |port|
			    pp.breakable
			    pp.text port.name
			end
		    end
		end
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

            def find_all_ports(type_name, port_name=nil)
                Orocos::TaskContext.find_all_ports(@ports.values, type_name, port_name)
            end
            def find_port(type_name, port_name=nil)
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
            def method_missing(m, *args,&block) #:nodoc:
                m = m.to_s
                if m =~ /^(\w+)=/
                    name = $1
                    puts "Warning: Setting the property #{name} the TaskContext #{@name} is not supported"
                    return
                end
                if has_port?(m) 
                  _port = port(m)
                  _port.filter = block if block         #overwirte filer
                  return _port
                end
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

            #array of all log ports  
            attr_accessor :ports

            #array of all replayed ports  
            #this array is filled after align was called
            attr_accessor :replayed_ports

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
                replay.load(*path)
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
                @replayed_ports = Array.new
                @used_streams = Array.new
                @stream = nil
                @current_sample = nil
                @ports = Hash.new
                @process_qt_events = false
                @out_of_sync_delta = 0
            end

            #returns false if no ports are or will be replayed
            def replay? 
              #check if stream was initialized
              if @steam 
                return true
              else
                each_port do |port|
                  return true if port.used?
                end
              end
              return false
            end

            #pretty print for Replay
	    def pretty_print(pp)
                pp.text "Orocos::Log::Replay"
		pp.nest(2) do
		    pp.breakable
		    pp.text "replay speed = #{@speed}"
		    pp.breakable
		    pp.text "TaskContext(s):"
		    @tasks.each_value do |task|
			pp.breakable
			task.pretty_print(pp)
		    end
		end
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

            def find_all_ports(type_name, port_name=nil)
                Orocos::TaskContext.find_all_ports(@ports.values, type_name, port_name)
            end
            def find_port(type_name, port_name=nil)
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
                        target_port = find_port(port.type_name,port_mappings[port.name]||port.name)
                        raise ArgumentError, "cannot find an output port for #{port.name}"  if !target_port
                        target_port.connect_to(port,port_policies[port.name])
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
	    #
	    # option is passed through to the StreamAligner and can 
	    # be one of the following
	    #
	    # true - use rt
	    # false - use lg
	    # :use_sample_time - use the timestamp in the data sample
	    #
            def align( option = false )
                @replayed_ports = Array.new
                @used_streams = Array.new

                #get all streams which shall be replayed
                each_port do |port|
                    if port.used?
                        @replayed_ports << port
                        @used_streams << port.stream
                    end
                    port.set_replay
                end

                puts ""
                puts "Aligning streams --> all ports which are unused will not be loaded!!!"
                puts ""

                if @used_streams.size == 0
                  puts "No ports are replayed."
                  puts "Connect replay ports or set their track flag to true."
                  return
                end

                puts "Replayed Ports:"
                @replayed_ports.each {|port| pp port}
                puts ""

                if @replayed_ports.size == 0
                  puts "No log data are marked for replay !!!"
                  return
                end

                #join streams 
                @stream = Pocolog::StreamAligner.new(option, *@used_streams)
                @stream.rewind

                reset_time_sync
                return step
            end

	    def aligned?
		return @stream != nil
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
                return if !@current_sample
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
                @replayed_ports[index].write(data)
                yield(@replayed_ports[index],data) if block_given?
                @current_sample
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
                @replayed_ports[index].write(data)
                yield(@replayed_ports[index],data) if block_given?
                return @current_sample
            end

            #Rewinds all streams and replays the first sample.
            def rewind()
                @stream.rewind
                step
            end

            #Runs through the log files until the end is reached.
            def run(time_sync = false,speed=1,&block)
                @speed = speed
                while step(time_sync,&block) do
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
            def sample_index
                @stream.sample_index
            end

            #Returns the number of samples.
            def size
                return @stream.size
            end

            #Returns the time of the current sample.
            def time
                return @stream.time
            end

            #Returns true if the end of file is reached.
            def eof?
                return @stream.eof?
            end

            #Seeks to the given position
            def seek(pos)
                @stream.seek(pos)
                #write all data to the ports
                0.upto(@stream.streams.length-1) do |index|
                    @replayed_ports[index].write(@stream.single_data(index))
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
            def load(path, logreg = Orocos.registry)
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

                    by_basename.each_value do |files|
                        args = files.compact.map do |path|
                            File.open(path)
                        end
                        args << logreg

                        logfile = Pocolog::Logfiles.new(*args.compact)
                        new_tasks = load_log_file(logfile, files.first)
                        tasks.concat(new_tasks)
                    end

                elsif File.file?(path)
                    file = Pocolog::Logfiles.open(path, logreg)
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
                task = @tasks[m.to_s]
                return task if task
                super
            end
        end
    end
end

