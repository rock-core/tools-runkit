require 'logger'
require 'utilrb/logger'
module Orocos
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::WARN
    @logger.progname = "Genom.rb"
    @logger.formatter = lambda { |severity, time, progname, msg| "#{progname}: #{msg}\n" }
    extend Logger::Forward
    extend Logger::Hierarchy
end

