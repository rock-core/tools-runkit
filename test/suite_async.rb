require './test/test_helper'
start_simple_cov("suite")

ENV['ORO_LOGLEVEL'] = '3'
require './test/async/test_attributes'
require './test/async/test_name_service'
require './test/async/test_object'
require './test/async/test_ports'
require './test/async/test_task'
require './test/async/test_task_proxy'

