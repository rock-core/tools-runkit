# frozen_string_literal: true

module Runkit
    # Implementation of task interfaces that live inside the Ruby code
    #
    # It allows to create RTT tasks controlled by Ruby
    module RubyTasks
    end
end

require "runkit/ruby_tasks/task_context"
require "runkit/ruby_tasks/ports"
