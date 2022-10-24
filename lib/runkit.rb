# frozen_string_literal: true

begin
    require "orogen"
rescue LoadError
    STDERR.puts "Cannot require 'orogen'"
    STDERR.puts "If you are using Rock, the 'orogen' package should have been installed automatically."
    STDERR.puts "It should be installed in tools/orogen from the root of your Rock installation"
    STDERR.puts "Make sure that you have loaded autoproj's env.sh script before continuing"
    exit 1
end

begin
    require "runkit/rtt_corba_ext"
rescue LoadError => e
    STDERR.puts "Cannot require Runkit's Ruby/C extension #{e}"
    STDERR.puts "If you are using Rock, this should have been done automatically."
    STDERR.puts "Run"
    STDERR.puts "  amake runkit"
    STDERR.puts "and try again"
    exit 1
end

require "typelib"
require "runkit/base"
require "runkit/default_loader"
require "runkit/typekits"

# Low-level interface to Rock components
module Runkit
    RUNKIT_LIB_DIR = File.expand_path("runki", __dir__)

    extend Logger::Root("Runkit", Logger::WARN)
end

require "orogen"
require "utilrb/module/attr_predicate"
require "utilrb/hash/map_value"

require "runkit/version"

require "runkit/name_services/base"
require "runkit/name_services/corba"
require "runkit/name_services/local"
require "runkit/name_service"

require "runkit/port_base"
require "runkit/input_port_base"
require "runkit/output_port_base"
require "runkit/attribute_base"
require "runkit/task_context_base"

require "runkit/task_context_attribute_base"
require "runkit/port"
require "runkit/input_port"
require "runkit/output_port"
require "runkit/attribute"
require "runkit/property"
require "runkit/operations"
require "runkit/task_context"

require "runkit/process"
require "runkit/corba"
require "runkit/mqueue"

require "runkit/ruby_tasks/local_input_port"
require "runkit/ruby_tasks/local_output_port"
require "runkit/ruby_tasks/process_manager"
require "runkit/ruby_tasks/process"
require "runkit/ruby_tasks/task_context"
require "runkit/ruby_tasks/remote_task_context"
require "runkit/ruby_tasks/stub_task_context"
require "runkit/input_writer"
require "runkit/output_reader"

require "utilrb/hash/recursive_merge"
require "runkit/configurations"