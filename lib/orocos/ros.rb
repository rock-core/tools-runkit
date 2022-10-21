# frozen_string_literal: true

module Orocos
    module ROS
        extend Logger::Hierarchy

        def self.available?
            @available = defined? TRANSPORT_ROS if @available.nil?
            @available
        end

        def self.disable
            @enabled = false
        end

        def self.enabled?
            if @enabled == false
                false
            elsif available? && (ENV["ROCK_ROS_INTEGRATION"] != "0")
                return false unless ENV["ROS_MASTER_URI"]

                if @enabled.nil?
                    # This is getting automatically enabled, check if it is
                    # actually available
                    begin
                        Orocos::ROS.name_service
                        Orocos.default_cmdline_arguments = Orocos.default_cmdline_arguments.merge("with-ros" => true)
                        Orocos.debug "ROS integration was enabled, passing default arguments: #{Orocos.default_cmdline_arguments}"
                        @enabled = true
                    rescue Orocos::ROS::ComError
                        Orocos.warn "ROS integration was enabled, but I cannot contact the ROS master at #{Orocos::ROS.default_ros_master_uri}, disabling"
                        Orocos::ROS.disable
                        Orocos.default_cmdline_arguments = Orocos.default_cmdline_arguments.delete("with-ros")
                        @enabled = false
                    end
                end
                @enabled
            end
        end

        def self.default_ros_master_uri
            ENV["ROS_MASTER_URI"]
        end

        # Returns the ROS name service that gives access to the master listed in
        # ROS_MASTER_URI
        #
        # @return [NameService,false] the name service object, or false if it
        #   cannot be accessed
        def self.name_service
            if @name_service
                @name_service
            else
                ns = Orocos::ROS::NameService.new
                ns.validate
                @name_service = ns
            end
        end
    end

    Port.transport_names[TRANSPORT_ROS] = "ROS" if ROS.available?
end
begin
    require "orogen_ros"
rescue LoadError
    if Orocos::ROS.available?
        Orocos.warn "ROS transport is available, but I cannot load the orogen_ros library, disabling"
        Orocos::ROS.disable
    end
end

require "xmlrpc/client"
require "utilrb/thread_pool"
require "orogen/ros"
require "orocos/ros/base"
require "orocos/ros/rpc"
require "orocos/ros/name_service"
require "orocos/ros/node"
require "orocos/ros/topic"
require "orocos/ros/ports"
require "orocos/ros/name_mappings"
require "orocos/ros/process_manager"
