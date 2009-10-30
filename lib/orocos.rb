require 'rorocos_ext'
require 'orocos/logging'
require 'orocos/version'
require 'orocos/task_context'
require 'orocos/ports'
require 'orocos/methods'
require 'orocos/process'
require 'orocos/corba'
module Orocos
    def self.initialize
        Orocos::CORBA.init
    end
end

