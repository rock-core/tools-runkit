module Orocos
    module ROS
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
