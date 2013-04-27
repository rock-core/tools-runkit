module Orocos
    module ROS
        def self.available?
            defined? TRANSPORT_ROS
        end
        def self.disable
            @enabled = false
        end
        def self.enabled?
            available? && @enabled && (ENV['ROS_MASTER_URI'] && ENV['ROCK_ROS_INTEGRATION'] != '0')
        end
        @enabled = true
    end

    if ROS.available?
        Port.transport_names[TRANSPORT_ROS] = 'ROS'
    end
end
require 'xmlrpc/client'
require 'utilrb/thread_pool'
require 'orocos/ros/rpc'
require 'orocos/ros/types'
require 'orocos/ros/name_service'
require 'orocos/ros/node'
require 'orocos/ros/topic'
require 'orocos/ros/ports'

# If ROS_MASTER_URI is set, auto-add the name service to the default
# list. One can remove it manually afterwards.
if Orocos::ROS.enabled?
    begin
        ns = Orocos::ROS::NameService.new
        ns.validate
        Orocos.name_service << ns
    rescue Orocos::ROS::ComError
        Orocos.warn "ROS integration was enabled, but I cannot contact the ROS master at #{ns.uri}, disabling"
        Orocos::ROS.disable
    end
end
