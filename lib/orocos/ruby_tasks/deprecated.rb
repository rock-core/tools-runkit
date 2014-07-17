Orocos.warn "orocos/ruby_process_server and orocos/ruby_task_context are deprecated."
Orocos.warn "The new class and file layouts are:"
Orocos.warn "require 'orocos/ruby_tasks'"
Orocos.warn "  Orocos::RubyTaskContext renamed to Orocos::RubyTasks::TaskContext"
Orocos.warn "  Orocos::LocalInputPort  renamed to Orocos::RubyTasks::LocalInputPort"
Orocos.warn "  Orocos::LocalOutputPort renamed to Orocos::RubyTasks::LocalOutputPort"
Orocos.warn "require 'orocos/ruby_tasks/process_manager'"
Orocos.warn "  Orocos::RubyProcessServer renamed to Orocos::RubyTasks::ProcessManager"
Orocos.warn "  Orocos::RubyDeployment    renamed to Orocos::RubyTasks::Process"
Orocos.warn "Backtrace"
caller.each do |line|
    Orocos.warn "  #{line}"
end

require 'orocos/ruby_tasks'
require 'orocos/ruby_tasks/process_manager'

module Orocos
    RubyProcessServer = RubyTasks::ProcessManager
    RubyDeployment    = RubyTasks::Process
    RubyTaskContext = RubyTasks::TaskContext
    LocalInputPort  = RubyTasks::LocalInputPort
    LocalOutputPort = RubyTasks::LocalOutputPort
end

