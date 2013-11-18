module Orocos
    module ROS
        extend Logger::Hierarchy

        def self.available?
            if @available.nil?
                @available =
                    if defined? TRANSPORT_ROS
                        begin require 'orogen_ros'
                            true
                        rescue LoadError
                            ROS.warn "the ROS transport is available, but the orogen_ros package is not, disabling ROS support"
                            false
                        end
                    end
            else @available = false
            end

        end
        def self.disable
            @enabled = false
        end
        def self.enabled?
            if @enabled == false
                return false
            elsif available? && (ENV['ROCK_ROS_INTEGRATION'] != '0')
                return false if !ENV['ROS_MASTER_URI']

                if @enabled.nil?
                    # This is getting automatically enabled, check if it is
                    # actually available
                    begin
                        Orocos::ROS.name_service
                        Orocos.default_cmdline_arguments = Orocos.default_cmdline_arguments.merge('with-ros' => true)
                        Orocos.debug "ROS integration was enabled, passing default arguments: #{Orocos.default_cmdline_arguments}"
                        @enabled = true
                    rescue Orocos::ROS::ComError
                        Orocos.warn "ROS integration was enabled, but I cannot contact the ROS master at #{Orocos::ROS.default_ros_master_uri}, disabling"
                        Orocos::ROS.disable
                        Orocos.default_cmdline_arguments = Orocos.default_cmdline_arguments.delete('with-ros')
                        @enabled = false
                    end
                end
                @enabled
            end
        end
    end
end
if Orocos::ROS.available?
    require 'orocos/ros'
end
