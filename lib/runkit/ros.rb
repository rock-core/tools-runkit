# frozen_string_literal: true

module Runkit
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
                        Runkit::ROS.name_service
                        Runkit.default_cmdline_arguments = Runkit.default_cmdline_arguments.merge("with-ros" => true)
                        Runkit.debug "ROS integration was enabled, passing default arguments: #{Runkit.default_cmdline_arguments}"
                        @enabled = true
                    rescue Runkit::ROS::ComError
                        Runkit.warn "ROS integration was enabled, but I cannot contact the ROS master at #{Runkit::ROS.default_ros_master_uri}, disabling"
                        Runkit::ROS.disable
                        Runkit.default_cmdline_arguments = Runkit.default_cmdline_arguments.delete("with-ros")
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
                ns = Runkit::ROS::NameService.new
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
    if Runkit::ROS.available?
        Runkit.warn "ROS transport is available, but I cannot load the orogen_ros library, disabling"
        Runkit::ROS.disable
    end
end

require "xmlrpc/client"
require "utilrb/thread_pool"
require "orogen/ros"
require "runkit/ros/base"
require "runkit/ros/rpc"
require "runkit/ros/name_service"
require "runkit/ros/node"
require "runkit/ros/topic"
require "runkit/ros/ports"
require "runkit/ros/name_mappings"
require "runkit/ros/process_manager"
