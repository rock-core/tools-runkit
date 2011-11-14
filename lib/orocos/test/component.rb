require 'orocos'
require 'utilrb/module/include'
require 'test/unit'
module Orocos
    module Test
        module Component
            def setup
                if !Orocos.initialized?
                    Orocos.initialize
                end

                @processes = Array.new
                self.class.run_specs.each do |name, task_name|
                    @processes.concat(Orocos.run(task_name => name))
                    instance_variable_set("@#{name}", Orocos::TaskContext.get(name))
                end

                self.class.reader_specs.each do |task_name, port_name, reader_name|
                    instance_variable_set("@#{reader_name}", send("#{task_name}").port(port_name).reader)
                end
                self.class.writer_specs.each do |task_name, port_name, writer_name|
                    instance_variable_set("@#{writer_name}", send("#{task_name}").port(port_name).writer)
                end
                super if defined? super
            end

            def teardown
                @processes.each { |p| p.kill }
                @processes.clear
                super if defined? super
            end

            # Verify that no sample arrives on +reader+ within +timeout+ seconds
            def assert_has_no_new_sample(reader, timeout = 0.2)
                sleep timeout
                assert(!reader.read_new, "#{reader} has one new sample, but none was expected")
            end

            # Verifies that +reader+ gets one sample within +timeout+ seconds
            def assert_has_one_new_sample(reader, timeout = 3, poll_period = 0.01)
                Integer(timeout / poll_period).times do
                    if sample = reader.read_new
                        return sample
                    end
                    sleep poll_period
                end
                flunk("expected to get one new sample out of #{reader}, but got none")
            end

            # Support module for declarations in tests
            module ClassExtension
                attribute(:run_specs) { Array.new }
                attribute(:reader_specs) { Array.new }
                attribute(:writer_specs) { Array.new }

                # call-seq:
                #   run 'task_name', 'model_name'
                #
                # Require the test to start a task of model +model_name+ at
                # setup, and shut it down during teardown.
                #
                # The task is registered with the name +task_name+. It is
                # accessible in the tests using the #task_name attribute
                #
                # For instance:
                #
                #   class TC_Component < Test::Unit::TestCase
                #       include Orocos::Test::Component
                #       run 'task', 'xsens_imu::Task'
                #
                #       def test_configure_fails_if_no_device_is_present
                #         task.device = ""
                #         assert_raises(Orocos::StateTransitionFailed) { task.configure }
                #       end
                #   end
                #
                def run(task_name, model_name)
                    attr_reader task_name
                    run_specs << [task_name, model_name]
                end

                def reader(name, port_name, reader_name = "#{name}_#{port_name}")
                    attr_reader reader_name
                    reader_specs << [name, port_name, reader_name]
                end

                def writer(name, port_name, writer_name = "#{name}_#{port_name}")
                    attr_reader writer_name
                    writer_specs << [name, port_name, writer_name]
                end
            end
        end
    end
end
