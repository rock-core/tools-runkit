require './test_helper'
start_simple_cov("suite")

ENV['ORO_LOGLEVEL'] = '3'
require './test_base'
require './test_corba'
require './test_orocos'
require './test_process'
require './test_properties'
require './test_task'
require './test_ports'
require './test_operations'
require './test_nameservice'
require './test_nameservice_deprecated'
