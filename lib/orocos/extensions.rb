module Orocos
    class << self
	attr_accessor :default_log_buffer_size
    end
    @default_log_buffer_size = 25

    extend_task 'logger::Logger' do
        # Create a new log port for the given interface object
        #
        # @param [Attribute,Property,OutputPort] object the object that is going
        #   to be logged
        # @param [Hash] options
        # @option options [String] name (#{object.task.name}.#{object.name}) the created port name 
        # @option options [Array<{'key' => String, 'value' => String}>] metadata additional metadata to be stored in the log stream
        # @return [String] the stream name, which is also the name of the
        #   created input port
        def create_log(object, options = Hash.new)
            options = Kernel.validate_options options,
                :name => "#{object.task.name}.#{object.name}",
                :metadata => []

            stream_name = options[:name]
            if !has_port?(stream_name)
                stream_metadata = object.log_metadata.map do |key, value|
                    Hash['key' => key, 'value' => value]
                end
                stream_metadata.concat(options[:metadata])

                if !createLoggingPort(stream_name, object.orocos_type_name, stream_metadata)
                    raise ArgumentError, "cannot create log port on log task #{name} for #{stream_name} and type #{object.orocos_type_name}"
                end
                Orocos.info "created logging port #{stream_name} of type #{object.orocos_type_name}"
            end
            stream_name
        end

        # Log the given interface object on self
        #
        # It creates the log port using {create_log} if needed, or reuses
        # an existing log port with a matching name
        #
        # @param [Attribute,Property,OutputPort] object the object that should
        #   be logged
        # @param [Integer] buffer_size the size of the log buffer (only used for
        #   ports)
        def log(object, buffer_size = Orocos.default_log_buffer_size)
            stream_name = create_log(object)
            if object.kind_of?(Port)
                port(stream_name).connect_to(object, :type => :buffer, :size => buffer_size)
            else
                object.log_port = port(stream_name)
                object.log_current_value
            end
            nil
        end

        #creates a log stream for annotations
        def create_log_annotations(stream_name,metadata=Hash.new)
            if !has_port?(stream_name)
                metadata = {"rock_stream_type" => "annotations"}.merge metadata
                metadata = metadata.map do |key, value|
                    Hash['key' => key, 'value' => value]
                end
                createLoggingPort(stream_name, Types::Logger::Annotations.name, metadata)
                Orocos.info "created logging port #{stream_name} of type #{Types::Logger::Annotations.name}"
            end
            stream_name
        end

        def log_annotations(time,key,value,stream_name = "")
            stream_name = create_log_annotations("log_annotations")
            sample = Types::Logger::Annotations.new
            sample.time = time
            sample.key = key
            sample.value = value
            sample.stream_name = stream_name
            @log_annotations_writer ||= port(stream_name).writer :type => :buffer, :size => 25
            @log_annotations_writer.write sample
        end

        def marker_start(index,comment)
            log_annotations(Time.now,"log_marker_start","<#{index}>;#{comment}")
        end

        def marker_stop(index,comment)
            log_annotations(Time.now,"log_marker_stop","<#{index}>;#{comment}")
        end

        def marker_abort(index,comment)
            log_annotations(Time.now,"log_marker_abort","<#{index}>;#{comment}")
        end

        def marker_event(comment)
            log_annotations(Time.now,"log_marker_event",comment)
        end

        def marker_stop_all(comment)
            log_annotations(Time.now,"log_marker_stop_all",comment)
        end

        def marker_abort_all(comment)
            log_annotations(Time.now,"log_marker_abort_all",comment)
        end

        #indicates that this task belongs to the tooling of rock
        def tooling?
            true
        end
    end

    extend_task 'taskmon::Task' do
        attribute(:watched_pids) { Hash.new { |h, k| Array.new } }
        attribute(:watched_tids) { Hash.new }

        def resolve_process_threads(pid, process_name, threads)
            # First, convert the process IDs into their corresponding threads
            # (note: we dup'ed the 'threads' hash)
            Dir.glob("/proc/#{pid}/task/*") do |thread_path|
                tid = Integer(File.basename(thread_path))
                threads[tid] ||= "#{process_name}-#{tid}"
            end
        end

        def add_watches(processes, _threads)
            watch_op = operation('watch')
            if _threads.respond_to?(:to_ary)
                threads = Hash.new
                _threads.each do |orocos_task|
                    tid = orocos_task.tid
                    if tid == 0
                        Orocos.warn "taskmon::Task: cannot automatically add a watch on #{orocos_task}: #tid returned zero, which probably means that you are on a system where oroGen does not implement the getTID operation (e.g. non-Linux)"
                    else
                        threads[tid] = orocos_task.name
                    end
                end
            else
                threads = _threads.to_hash.dup
            end
            sent_operations = []

            if on_localhost?
                processes.each do |pid, process_name|
                    process_name ||= pid
                    resolve_process_threads(pid, process_name, threads)
                end
            end

            # We can now add watches for threads that are either not watched
            # yet, or for which we started to know the name
            threads.each do |tid, thread_name|
                old_name = watched_tids[tid]
                if old_name
                    if old_name == thread_name || !_threads[tid]
                        next
                    else
                        Orocos.info "#{name}: renaming OS task statistics for #{tid} from #{old_name} to #{thread_name}"
                    end
                else
                    Orocos.info "#{name}: watching OS task statistics for #{tid} with name #{thread_name}"
                end
                sent_operations << watch_op.sendop(thread_name, tid)
                watched_tids[tid] = thread_name
            end
            sent_operations.each(&:collect)

            threads
        end

        def remove_watch(thread)
            remove_watches([thread])
        end

        def remove_watches(threads)
            # Now remove existing watches that are not required anymore
            remove_watch_op = operation('removeWatchFromPID')
            sent_operations = []
            threads.each do |thread|
                tid = if thread.kind_of?(Orocos::TaskContext) then thread.tid
                      else thread
                      end

                sent_operations << remove_watch_op.sendop(tid)
                watched_tids.delete(tid)
            end
            sent_operations.each(&:collect)
        end

        def watch(*args)
            if args.size == 2 # operation call
                super
            elsif args.size > 1
                raise ArgumentError, "expected one or two arguments, got #{args.size}"
            elsif args.first.kind_of?(Orocos::TaskContext)
                watch_task(args.first)
            elsif args.first.kind_of?(Orocos::Process)
                watch_process(args.first)
            else
                raise ArgumentError, "expected a task or process object, but got #{args.first}"
            end
        end

        def watch_process(process)
            processes = { process.pid => process.name }
            threads = Hash.new
            process.each_task do |task|
                threads[task.tid] = task.name
            end
            add_watches(processes, threads)
        end

        def watch_task(task)
            add_watches([], { task.tid => task.name })
        end
    end
end

