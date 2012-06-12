require 'utilrb/logger'

# Module for replaying log files
module Orocos
    module Log
	extend Logger::Hierarchy
	extend Logger::Forward

        #class which is storing stream annotions
        class Annotations
            attr_reader :samples
            attr_reader :stream
            attr_reader :file_name

            def initialize(path,stream)
                @samples = Array.new
                @file_name = path
                @stream = stream

                stream.samples.each do |rt,lg,sample|
                    @samples << sample
                end

                @samples.sort! do |a,b|
                    a.time <=> b.time
                end
            end

            def pretty_print(pp)
                pp.text "Stream name #{@file_name}, number of annotations #{@annotations.size}"
            end
        end

        #Class for loading and replaying OROCOS log files.
        #
        #This class creates TaskContexts and OutputPorts to simulate the recorded tasks.
        class Replay
            class << self 
                attr_accessor :log_config_file 
            end
            @log_config_file = "properties."

            #desired replay speed = 1 --> record time
            attr_accessor :speed            

            #name of the log file which holds the logged properties
            #is converted into Regexp
            attr_accessor :log_config_file            

            #last replayed sample
            attr_reader :current_sample

            #array of all replayed ports  
            #this array is filled after align was called
            attr_accessor :replayed_ports

            #array of all replayed properties
            #this array is filled after align was called
            attr_accessor :replayed_properties


            #set it to true if processing of qt events is needed during synced replay
            attr_accessor :process_qt_events             

            #hash of code blocks which are used to calculate the replayed timestamps
            #during replay 
            attr_reader :timestamps

            #indicates if the replayed data are replayed synchronously 
            #<0 means the replayed samples are behind the simulated times
            #>0 means that the replayed samples are replayed to fast
            attr_reader :out_of_sync_delta

            #actual replay speed 
            #this can be different to speed if the hard disk is too slow  
            attr_reader :actual_speed

            #array of stream annotations
            attr_reader :annotations

            def self.open(*path)
                replay = new
                replay.load(*path)
                replay
            rescue ArgumentError => e
                Vizkit.error "Cannot load logfiles"
                raise e 
            rescue Pocolog::Logfiles::MissingPrologue => e
                Vizkit.error "Wrong log format"
                raise e
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
                @annotations = Array.new
                @speed = 1
                @replayed_ports = Array.new
                @replayed_properties = Array.new
                @replayed_objects = Array.new
                @used_streams = Array.new
                @stream = nil
                @current_sample = nil
                @process_qt_events = false
                @log_config_file = Replay::log_config_file
                reset_time_sync
                time_sync
            end

            #returns an array of all simulated tasks
            def tasks
                @tasks.values
            end

            #returns the time of the current sample replayed
            def time
                @base_time
            end

            #returns false if no ports are or will be replayed
            def replay? 
                #check if stream was initialized
                if @stream 
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
                    pp.text "Markers = #{@markers}"
                    pp.breakable
                    pp.text "TaskContext(s):"
                    @tasks.each_value do |task|
                        pp.breakable
                        task.pretty_print(pp)
                    end
                    pp.breakable
                    pp.text "Stream Annotations:"
                    @annotations.each do |a|
                        pp.breakable
                        a.pretty_print(pp)
                    end
                end
            end

            def sample_index_for_time(time)
                prev_pos = sample_index
                seek(time)
                target_sample_pos = sample_index
                seek(prev_pos)
                return target_sample_pos
            end

            def sample_index()
                return @stream.sample_index if @stream
                return nil
            end

            def single_data(id)
                if @stream
                    return @stream.single_data(id)
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

            #If set to true all ports are replayed and are not filtered out by the
            #filter
            #otherwise only ports are replayed which have a reader or
            #a connection to an other port
            def track(value,filter=Hash.new)
                options, filter = Kernel::filter_options(filter,[:tasks])
                @tasks.each_value do |task|
                    task.track(value,filter) if !options.has_key?(:tasks) || task.name =~ options[:tasks]
                end
            end

            def find_all_ports(type_name, port_name=nil)
                Orocos::TaskContext.find_all_ports(ports, type_name, port_name)
            end
            def find_port(type_name, port_name=nil)
                Orocos::TaskContext.find_port(ports, type_name, port_name)
            end

            #Tries to find a OutputPort for a specefic data type.
            #For port_name Regexp is allowed.
            #If precise is set to true an error will be raised if more
            #than one port is matching type_name and port_name.
            def port_for(type_name, port_name, precise=true)
                Log.warn "#port_for is deprecated. Use either #find_all_ports or #find_port"
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
                #convenience block to do connect_to(task,:auto_ignore)
                if port_mappings == :auto_ignore
                    ports_ignored = port_mappings
                    port_mappings = Hash.new
                end
                ports_ignored = Array.new(ports_ignored)

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
                    if port.to_orocos_port.kind_of?(Orocos::InputPort) && !ports_ignored.include?(port.name)
                        target_port = find_port(port.type_name,port_mappings[port.name]||port.name)
                        if target_port
                            target_port.connect_to(port,port_policies[port.name])
                        elsif !ports_ignored.include? :auto_ignore
                            raise ArgumentError, "cannot find an output port for #{port.name}"
                        else
                            Log.warn "No input port can be found for output port #{port.full_name}."
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

                if !replay?
                    Log.warn "No ports are selected. Assuming that all ports shall be replayed."
                    Log.warn "Connect port(s) or set their track flag to true to get rid of this message."
                    track(true)
                end

                #get all streams which shall be replayed
                each_port do |port|
                    if port.used?
                        if !port.stream.empty?
                            @replayed_ports << port
                            @used_streams << port.stream
                        end
                    end
                    port.set_replay
                end

                #get all properties which shall be replayed
                each_task do |task|
                    if task.used?
                        task.properties.values.each do |property|
                            @replayed_properties << property
                            @used_streams << property.stream
                        end
                    end
                end
                @replayed_objects = @replayed_ports + @replayed_properties

                Log.info "Aligning streams --> all ports which are unused will not be loaded!!!"
                if @used_streams.size == 0
                    Log.warn "No log data are replayed. All selected streams are empty."
                    return
                end

                Log.info "Replayed Ports:"
                @replayed_ports.each {|port| Log.info PP.pp(port,"")}

                #register task on the local name server
                register_tasks

                #join streams 
                @stream = Pocolog::StreamAligner.new(option, *@used_streams)
                @stream.rewind

                reset_time_sync
                return step
            end

            def advance
                if(@stream)
                    return @stream.advance
                else
                    throw "Stream is not initialized yet"
                end
            end

            def first_sample_pos(stream)
                @stream.first_sample_pos(stream)
            end

            def last_sample_pos(stream)
                @stream.last_sample_pos(stream)
            end

            # registers all replayed log tasks on the local name server
            def register_tasks
                #enable local name service 
                service = if Nameservice.enabled? :Local
                              Nameservice.get :Local 
                          else
                              Nameservice.enable :Local
                          end
                each_task do |task|
                    if task.used?
                        service.registered_tasks[task.name] = task
                    end
                end
            end

            def stream_index_for_name(name)
                if @stream
                    return @stream.stream_index_for_name(name)
                end
                throw "Stream is not initialized yet"
            end

            def stream_index_for_type(name)
                if @stream
                    return @stream.stream_index_for_type(name)
                end
                throw "Stream is not initialized yet"
            end

            def aligned?
                return @stream != nil
            end

            #Resets the simulated time.
            #This should be called after the replay was paused.
            def reset_time_sync
                @start_time = nil 
                @base_time  = nil
                @actual_speed = 0
                @out_of_sync_delta = 0
            end

            #this can be used to set a different time sync logic
            #the code block has three parameters
            #time = current sample time
            #actual_delta = time between start of replay and now
            #required_delta = time which should have elapsed between start and now
            #to replay at the desired speed 
            #the code block must return the number of seconds which 
            #the replay shall wait before the sample is repalyed 
            #
            #Do not block the program otherwise qt events are no longer processed!!!
            #
            #Example
            #time_sync do |time,actual_delta,required_delta|
            #   my_object.busy? ? 1 : 0
            #end
            #
            def time_sync(&block)
                if block_given?
                    @time_sync_proc = block
                else
                    @time_sync_proc = Proc.new do |time,actual_delta,required_delta|
                        required_delta - actual_delta
                    end
                end
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

                if getter = (timestamps[data.class.name] || default_timestamp)
                    time = getter[data]
                end
                @base_time ||= time
                @start_time ||= Time.now
                required_delta = (time - @base_time)/@speed
                actual_delta   = Time.now - @start_time

                #wait if replay is faster than the desired speed and time_sync is set to true
                if time_sync
                    while (wait = @time_sync_proc.call(time,actual_delta,required_delta)) > 0.001
                        #process qt events every 0.01 sec
                        if @process_qt_events == true
                            start_wait = Time.now
                            while true
                                $qApp.processEvents()
                                break if !@start_time                           #break if start_time was reseted throuh processEvents
                                wait2 =wait -(Time.now - start_wait)
                                if wait2 > 0.001
                                    sleep [0.01,wait2].min
                                else
                                    break
                                end
                            end
                        else
                            sleep(wait)
                        end
                        break if !@start_time        # if time was resetted go out 
                        actual_delta   = Time.now - @start_time
                    end
                    actual_delta = @start_time ? Time.now - @start_time : required_delta
                    @out_of_sync_delta = required_delta - actual_delta
                end
                @actual_speed = required_delta/actual_delta*@speed

                #write sample to simulated ports or properties
                @replayed_objects[index].write(data)
                yield(@replayed_objects[index],data) if block_given?
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
                @replayed_objects[index].write(data)
                yield(@replayed_objects[index],data) if block_given?
                return @current_sample
            end

            #Rewinds all streams and replays the first sample.
            def rewind()
                @stream.rewind
                step
            end

            #returns the last port which recieved data
            def current_port
                if @current_sample
                    index,_,_ = @current_sample
                    replayed_ports[index]
                end
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

            #Returns an array of all simulated ports 
            def ports 
                result = Array.new
                each_port do |port|
                    result << port
                end
                result
            end

            #returns an array of log_markers
            def log_markers
                @markers ||= Array.new
                return @markers if !@markers.empty?

                annotations.each do |annotation|
                    #check if this is the right type
                    if annotation.stream.type_name == "/logger/Annotations"
                        @markers.concat LogMarker::parse(annotation.samples)
                    end
                end
                @markers.sort! do |a,b|
                    a.time <=> b.time 
                end
                @markers
            end

            def has_task?(name)
                @tasks.has_key?(name.to_s)
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
                @current_sample = @stream.seek(pos)
                #write all data to the ports
                0.upto(@stream.streams.length-1) do |index|
                    data = @stream.single_data(index)
                    #only write samples if they are available
                    if(data)
                        @replayed_objects[index].write(data)
                    end
                end
            end

            #replays the last sample to the log port
            def refresh
                index, time, data = @current_sample
                @replayed_objects[index].write(data)
            end

            def load_task_from_stream(stream,path)
                #get the name of the task which was logged into the stream
                task_name = if stream.metadata.has_key? "rock_task_name"
                                stream.metadata["rock_task_name"]
                            else
                                result = stream.name.to_s.match(/^(.*)\./)
                                result[1] if result
                            end
                if task_name == nil
                    task_name = "unknown"
                    Log.warn "Stream name (#{stream.name}) does not follow the convention TASKNAME.PORTNAME and has no metadata, assuming as TASKNAME \"#{task_name}\""
                end

                task = @tasks[task_name]
                if !task
                    task = @tasks[task_name]= TaskContext.new(self,task_name, path,@log_config_file)
                end

                begin
                    task.add_stream(path,stream)
                    Log.info "    loading stream #{stream.name} (#{stream.type_name})"
                rescue InitializePortError => error
                    Log.warn "    loading stream #{stream.name} (#{stream.type_name}) failed. Call the port for an error message."
                end
                task
            end

            # Loads all the streams defined in the provided log file
            def load_log_file(file, path)
                Log.info "  loading log file #{path}"
                file.streams.each do |s|
                    if s.metadata["rock_stream_type"] == "annotations"
                        @annotations << Annotations.new(path,s)
                        next
                    end
                    load_task_from_stream(s,path)
                end
            end

            #Loads a log files and creates TaskContexts which simulates the recorded tasks.
            #You can either specify a single file or a hole directory. If you want to load
            #more than one directory or file simultaneously you can use an array.
            def load(*paths)
                paths.flatten!
                raise ArgumentError, "No log file was given" if paths.empty?

                logreg = nil
                if paths.last.kind_of?(Typelib::Registry)
                    logreg = paths.pop
                end

                paths.each do |path| 
                    #check if path is a directory
                    path = File.expand_path(path)
                    if File.directory?(path)
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
                            load_log_file(logfile, files.first)
                        end
                    elsif File.file?(path)
                        file = Pocolog::Logfiles.open(path, logreg)
                        load_log_file(file, path)
                    else
                        raise ArgumentError, "Can not load log file: #{path} is neither a directory nor a file"
                    end
                end
                raise ArgumentError, "Nothing was loded from the following log files #{paths.join("; ")}" if @tasks.empty?
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

                begin  
                    super(m.to_sym,*args,&block)
                rescue  NoMethodError => e
                    Log.error "#{m} is not a Log::Task of the current log file(s)"
                    Log.error "The following tasks are availabe:"
                    @tasks.each_value do |task|
                        Log.error "  #{task.name}"
                    end
                    raise e 
                end
            end
        end
    end
end

