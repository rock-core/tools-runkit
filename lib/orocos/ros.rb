module Orocos
    module ROS
        def self.available?
            defined? TRANSPORT_ROS
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

        def self.default_ros_master_uri
            ENV['ROS_MASTER_URI']
        end

        # Returns the ROS name service that gives access to the master listed in
        # ROS_MASTER_URI
        #
        # @return [NameService,false] the name service object, or false if it
        #   cannot be accessed
        def self.name_service
            if @name_service
                return @name_service
            else
                ns = Orocos::ROS::NameService.new
                ns.validate
                @name_service = ns
            end
        end
    end

    if ROS.available?
        Port.transport_names[TRANSPORT_ROS] = 'ROS'
    end
end
require 'xmlrpc/client'
require 'utilrb/thread_pool'
require 'orogen_ros'
require 'orocos/ros/rpc'
require 'orocos/ros/name_service'
require 'orocos/ros/node'
require 'orocos/ros/topic'
require 'orocos/ros/ports'
require 'orocos/ros/name_mappings'
require 'orocos/ros/process_manager'
