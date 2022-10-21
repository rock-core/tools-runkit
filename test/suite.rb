# frozen_string_literal: true

require "orocos/test"

Orocos.warn_for_missing_default_loggers = false
ENV["ORO_LOGLEVEL"] = "3"
require "./test/test_base"
require "./test/test_configurations"
require "./test/test_corba"
require "./test/test_nameservice"
require "./test/test_operations"
require "./test/test_ports"
require "./test/test_process"
require "./test/test_properties"
require "./test/test_task"
require "./test/test_uri"
require "./test/test_namespace"
require "./test/test_remote_processes"
require "./test/suite_ruby_tasks"
require "./test/suite_async"
require "./test/suite_ros" if Orocos::ROS.enabled?

require "./test/suite_async"
