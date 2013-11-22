require './test/test_helper'
start_simple_cov("suite")

require 'orocos'
Orocos.warn_for_missing_default_loggers = false
ENV['ORO_LOGLEVEL'] = '3'
require './test/test_base'
require './test/test_configurations'
require './test/test_corba'
require './test/test_nameservice'
require './test/test_operations'
require './test/test_ports'
require './test/test_process'
require './test/test_properties'
require './test/test_ruby_task_context'
require './test/test_task'
require './test/test_uri'
require './test/test_namespace'
require './test/suite_async'
if Orocos::ROS.enabled?
require './test/suite_ros'
end

require './test/suite_async'
