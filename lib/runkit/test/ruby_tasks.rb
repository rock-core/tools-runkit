# frozen_string_literal: true

module Runkit
    module Test
        # Support for using ruby tasks in tests
        module RubyTasks
            def helpers_dir
                File.join(__dir__, "helpers")
            end

            def setup
                @allocated_task_contexts = []
                @started_external_ruby_task_contexts = []
                super
            end

            def teardown
                super
                @allocated_task_contexts.each(&:dispose)
                @started_external_ruby_task_contexts.each do |pid|
                    begin Process.kill "INT", pid
                    rescue Errno::ESRCH
                    end
                    _, status = Process.waitpid2 pid
                    raise "subprocess #{pid} failed with #{status.inspect}" unless status.success?
                end
            end

            def register_allocated_ruby_tasks(*tasks)
                @allocated_task_contexts.concat(tasks)
            end

            def new_ruby_task_context(name = self.name.gsub(/[^\w]/, "_"), **options, &block)
                task = Runkit::RubyTasks::TaskContext.new(name, **options, &block)
                @allocated_task_contexts << task
                task
            end

            def new_external_ruby_task_context(
                task_name,
                typekits: ["std"], input_ports: [], output_ports: [], timeout: 2
            )
                typekits = typekits.map do |typekit_name|
                    "--typekit=#{typekit_name}"
                end
                output_ports = output_ports.map do |name, type|
                    "--output-port=#{name}::#{type}"
                end
                input_ports = input_ports.map do |name, type|
                    "--input-port=#{name}::#{type}"
                end

                ior_r, ior_w = IO.pipe
                pid = spawn(Gem.ruby, File.join(helpers_dir, "ruby_task_spawner"),
                            task_name, *typekits, *input_ports, *output_ports,
                            "--ior-fd=#{ior_w.fileno}", { ior_w => ior_w })

                ior_w.close
                deadline = Time.now + timeout
                message = +""

                loop do
                    message += ior_r.read_nonblock(1024)
                rescue IO::WaitReadable
                    remaining_timeout = deadline - Time.now
                    if remaining_timeout < 0
                        flunk("timed out waiting for the external ruby task "\
                              "contexts to be ready")
                    end
                    select([ior_r], nil, nil, remaining_timeout)
                rescue EOFError
                    break
                end

                ior_r.close

                ior =
                    begin
                        JSON.parse(message)["tasks"][0]["ior"]
                    rescue JSON::ParserError
                        flunk("unexpected message received from ruby_task_spawner, "\
                              "got '#{message}'")
                    end

                [TaskContext.new(ior, name: task_name), pid]
            end
        end
    end
end
