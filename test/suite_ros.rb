require './test_helper'
start_simple_cov("suite")

ENV['ORO_LOGLEVEL'] = '3'
require './ros/test_async'
require './ros/test_name_service'
require './ros/test_node'
require './ros/test_ros'
require './ros/test_topic'
