# frozen_string_literal: true

require "runkit"
require "benchmark"

Runkit::ROS.initialize
name_service = Runkit::ROS::NameService.new
node_name = ARGV.first
node = name_service.get(node_name)

count = 10
Benchmark.bm do |x|
    x.report("subscriptions (#{count} times)") { count.times { node.server.subscriptions } }
    x.report("publications (#{count} times)") { count.times { node.server.publications } }
    x.report("system_state (#{count} times)") { count.times { name_service.ros_master.system_state } }
end
