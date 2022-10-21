# frozen_string_literal: true

module Orocos
    module RemoteProcesses
        extend Logger::Hierarchy
    end
end

require "orocos/remote_processes/protocol"
require "orocos/remote_processes/client"
require "orocos/remote_processes/process"
require "orocos/remote_processes/loader"
