module Orocos
    extend_task 'logger::Logger' do
        attribute(:logged_ports) { Set.new }

        def log(port, buffer_size = 25)
            port_name = "#{port.task.name}.#{port.name}"
            if logged_ports.include?(port_name)
                return
            end

            if !has_port?(port_name)
                Orocos.debug "created logging port #{port_name} of type #{port.orocos_type_name}"
                createLoggingPort(port_name, port.orocos_type_name)
            end

            port(port_name).connect_to(port, :type => :buffer, :size => buffer_size)
            logged_ports << port_name
            nil
        end
    end

    extend_task 'taskmon::Task' do
        attribute(:watched_pids) { Hash.new { |h, k| Array.new } }
        attribute(:watched_tids) { Hash.new }

        def resolve_process_threads(pid, threads)
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

            processes.each do |pid|
                resolve_process_threads(pid, threads)
            end

            # We can now add watches for threads that are either not watched
            # yet, or for which we started to know the name
            threads.each do |tid, thread_name|
                old_name = watched_tids[tid]
                if old_name
                    if old_name == thread_name || !_threads[tid]
                        next
                    else
                        Orocos.debug "renaming OS task statistics for #{tid} from #{old_name} to #{thread_name}"
                    end
                else
                    Orocos.debug "watching OS task statistics for #{tid} with name #{thread_name}"
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

