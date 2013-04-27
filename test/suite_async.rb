require './test_helper'
start_simple_cov("suite")

ENV['ORO_LOGLEVEL'] = '3'
require './async/test_attributes'
require './async/test_name_service'
require './async/test_object'
require './async/test_ports'
require './async/test_task'
require './async/test_task_proxy'

