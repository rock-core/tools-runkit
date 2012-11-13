module Orocos
    module ROS
        def self.available?
            defined? TRANSPORT_ROS
        end
    end

    if ROS.available?
        Port.transport_names[TRANSPORT_ROS] = 'ROS'
    end
end
require 'xmlrpc/client'
require 'orocos/ros/rpc'
require 'orocos/ros/types'
require 'orocos/ros/name_service'
require 'orocos/ros/node'
require 'orocos/ros/topic'
