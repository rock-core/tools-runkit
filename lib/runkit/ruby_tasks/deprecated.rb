# frozen_string_literal: true

Runkit.warn "runkit/ruby_process_server and runkit/ruby_task_context are deprecated."
Runkit.warn "The new class and file layouts are:"
Runkit.warn "require 'runkit/ruby_tasks'"
Runkit.warn "  Runkit::RubyTaskContext renamed to Runkit::RubyTasks::TaskContext"
Runkit.warn "  Runkit::LocalInputPort  renamed to Runkit::RubyTasks::LocalInputPort"
Runkit.warn "  Runkit::LocalOutputPort renamed to Runkit::RubyTasks::LocalOutputPort"
Runkit.warn "require 'runkit/ruby_tasks/process_manager'"
Runkit.warn "  Runkit::RubyProcessServer renamed to Runkit::RubyTasks::ProcessManager"
Runkit.warn "  Runkit::RubyDeployment    renamed to Runkit::RubyTasks::Process"
Runkit.warn "Backtrace"
caller.each do |line|
    Runkit.warn "  #{line}"
end

require "runkit/ruby_tasks"
require "runkit/ruby_tasks/process_manager"

module Runkit
    RubyProcessServer = RubyTasks::ProcessManager
    RubyDeployment    = RubyTasks::Process
    RubyTaskContext = RubyTasks::TaskContext
    LocalInputPort  = RubyTasks::LocalInputPort
    LocalOutputPort = RubyTasks::LocalOutputPort
end
