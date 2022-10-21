# frozen_string_literal: true

module Orocos
    module ROS
        # @return [String] the type name that should be used on the oroGen
        #   side to represent the given ROS message
        #
        # @param [String] message_type the ROS message type name
        def self.map_message_type_to_orogen(message_type)
            default_loader.map_message_type_to_orogen(message_type)
        end

        class DefaultLoader < OroGen::ROS::Loader
            def clear
                super
                search_path << OroGen::ROS::OROGEN_ROS_LIB_DIR unless search_path.include?(OroGen::ROS::OROGEN_ROS_LIB_DIR)
                root_loader.project_model_from_name "ros"
            end
        end

        def self.default_loader
            Orocos.default_loader
            @default_loader ||= DefaultLoader.new(Orocos.default_loader)
        end

        # Helper method for initialize
        def self.load
            @loaded = true
        end

        def self.loaded?
            !!@loaded
        end

        def self.clear
            default_loader.clear
            @loaded = false
        end

        # Get the roscore process id
        # @return [Int] Pid of the roscore process, if it has been started by this Ruby process,
        #     false otherwise
        def self.roscore_pid
            @roscore_pid || 0
        end

        # Test whether roscore is available or not
        # @return [Boolean] True if roscore is available, false otherwise
        def self.roscore_available?
            !rosnode_list.empty?
        rescue InternalError => e
            false
        end

        # Start the roscore process
        # @return[INT] Pid of the roscore process see #roscore_pid
        def self.roscore_start(*args)
            options = args.last.kind_of?(Hash) ? args.pop : {}
            options, unknown_options = Kernel.filter_options options,
                                                             redirect: File.join("/var/tmp/roscore.log")

            args << options

            if !roscore_available?
                @roscore_pid = Utilrb.spawn "roscore", *args
                ::Process.detach(@roscore_pid)
                @roscore_pid
            elsif !@roscore_pid
                warn "roscore is already running, but is not controlled by this process"
            else
                info "roscore is already running, pid '#{@roscore_pid}'"
            end

            return unless unknown_options[:wait]

            sleep 0.1 until roscore_available?
        end

        # Shutdown roscore if controlled by this process, otherwise
        # calls to this function will return false
        # This will only work if roscore has been started by the same ruby process
        # @throw [ArgumentError] if trying to shutdown an already dead roscore
        # @return [Boolean] True if roscore has been shutdown, false if not
        def self.roscore_shutdown
            begin
                if @roscore_pid
                    info "roscore will be shutdown"
                    status = ::Process.kill("INT", @roscore_pid)
                    @roscore_pid = nil
                    return status
                end
            rescue Errno::ESRCH
                raise ArgumentError, "trying to shutdown roscore, which is not running anymore with pid '#{@roscore_pid}'"
            end

            warn "roscore is not controlled by this process; no shutdown will be performed"
            false
        end

        # Run the launch from the package +package_name+ given by +launch_name+
        # @options [Hash] Options are forwarded to Utilrb.spawn, e.g.
        #     :working_directory
        #     :nice
        #     :redirect
        # @return [Int] Pid of the roslaunch process
        def self.roslaunch(package_name, launch_name, options = {})
            launch_name = launch_name.gsub(/\.launch/, "")
            launch_name = launch_name + ".launch"
            arguments = [package_name, launch_name]
            arguments += [options]

            pid = Utilrb.spawn "roslaunch", "__name:=#{launch_name}", *arguments
            pid
        end
    end
end
