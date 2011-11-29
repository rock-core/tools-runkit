module Orocos
    extend_task 'logger::Logger' do
        attribute(:logged_ports) { Set.new }

        def create_log(object)
            stream_type =
                case object
                when Orocos::Port then 'port'
                when Orocos::Attribute then 'attribute'
                when Orocos::Property then 'property'
                else
                    raise ArgumentError, "expected a port, property or attribute but got #{object.class}"
                end

            stream_name = "#{object.task.name}.#{object.name}"

            if !has_port?(stream_name)
                metadata = object.log_metadata.map do |key, value|
                    Hash['key' => key, 'value' => value]
                end

                createLoggingPort(stream_name, object.orocos_type_name, metadata)
                Orocos.info "created logging port #{stream_name} of type #{object.orocos_type_name}"
            end
            stream_name
        end

        def log(object, buffer_size = 25)
            stream_name = create_log(object)
            if object.kind_of?(Port)
                port(stream_name).connect_to(object, :type => :buffer, :size => buffer_size)
            else
                object.log_port = port(stream_name)
                object.log_current_value
            end
            nil
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
            threads = _threads.dup
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

