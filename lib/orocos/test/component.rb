require 'orocos'
require 'utilrb/module/include'
require 'test/unit'
module Orocos
    module Test
        module Component
            attribute(:processes)  { Array.new }
            attribute(:data_readers)  { Array.new }
            attribute(:data_writers) { Array.new }
            def setup
                if !Orocos.initialized?
                    Orocos.initialize
                end

                self.class.run_specs.each do |name, run_spec|
                    task = start(*run_spec)
                    instance_variable_set("@#{name}", task)
                end

                self.class.reader_specs.each do |task_name, port_name, reader_name, policy|
                    reader = self.reader(send(task_name).port(port_name), policy)
                    instance_variable_set("@#{reader_name}", reader)
                end
                self.class.writer_specs.each do |task_name, port_name, writer_name, policy|
                    writer = self.data_writer(send(task_name).port(port_name), policy)
                    instance_variable_set("@#{writer_name}", writer)
                end
                super if defined? super
            end

            def teardown
                processes.each { |p| p.kill }
                processes.clear
                data_readers.each { |r| r.disconnect }
                data_readers.clear
                data_writers.each { |w| w.disconnect }
                data_writers.clear
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
                flunk("expected to get one new sample out of #{reader.port.name}, but got none")
            end

            # call-seq:
            #   assert_state_change(task, timeout = 1) { |state|   test_if_state_is_the_expected_state }
            #   
            # Tests if the state of +task+ changes to an expected value.  The
            # block should return whether the passed state is the expected state
            # or not.
            def assert_state_change(task, timeout = 1)
                sleep_time = Float(timeout) / 10
                10.times do
                    queued_state_changes = task.peek_state
                    if queued_state_changes.any? { |s| yield(s) }
                        return
                    end
                    sleep sleep_time
                end

                flunk("could not find the expected state change for #{task.name} in #{task.peek_state.inspect}")
            end

            # call-seq:
            #   start 'model_name', 'task_name'
            #   start 'deployment_name', 'task_name'[, 'prefix']
            #
            # Requires the unit test to start a deployment/task at the point of
            # the call, and make sure to shut it down during teardown. In test
            # methods, the task object is made accessible with the
            # 'attribute_name' attribute
            #
            # In the first form, the task is given through its model. The
            # global task name is registered with 'task_name', which defaults
            # to 'attribute_name'
            #
            # In the second form, the task is given through a deployment
            # name / task name pair. If a prefix is given, task_name must
            # include the prefix as well, i.e.:
            #
            #   start 'task', 'rock_logger', 'source_logger', 'source'
            #
            # where 'logger' is a task of the 'rock_logger' deployment.
            #
            # For instance:
            #
            #   class TC_Component < Test::Unit::TestCase
            #       include Orocos::Test::Component
            #
            #       def test_configure_fails_if_no_device_is_present
            #         task = run 'xsens_imu::Task', 'task'
            #         task.device = ""
            #         assert_raises(Orocos::StateTransitionFailed) { task.configure }
            #       end
            #   end
            #
            def start(model_or_deployment, task_name, prefix = nil)
                begin Orocos::TaskContext.get(task_name)
                rescue Orocos::NotFound
                    if model_or_deployment =~ /::/
                        processes.concat(Orocos.run(model_or_deployment => task_name))
                    else
                        processes.concat(Orocos.run(model_or_deployment => prefix))
                    end
                end
                return Orocos::TaskContext.get(task_name)
            end

            # Gets the data reader for this port. It gets disconnected on
            # teardown
            def data_reader(port, policy = Hash.new)
                reader = port.reader(policy)
                data_readers << reader
                reader
            end

            # Gets the data writer for this port. It gets disconnected on
            # teardown
            def data_writer(port, policy = Hash.new)
                writer = port.writer(policy)
                data_writers << writer
                writer
            end

            # Support module for declarations in tests
            module ClassExtension
                attribute(:run_specs) { Array.new }
                attribute(:reader_specs) { Array.new }
                attribute(:writer_specs) { Array.new }

                # call-seq:
                #   start 'attribute_name', 'model_name'[, 'task_name']
                #   start 'attribute_name', 'deployment_name', 'task_name'[, 'prefix']
                #
                # Requires the unit test to start a deployment/task at startup
                # and shut it down during teardown. In test methods, the task
                # object is made accessible with the 'attribute_name' attribute
                #
                # In the first form, the task is given through its model. The
                # global task name is registered with 'task_name', which defaults
                # to 'attribute_name'
                #
                # In the second form, the task is given through a deployment
                # name / task name pair. If a prefix is given, task_name must
                # include the prefix as well, i.e.:
                #
                #   start 'task', 'rock_logger', 'source_logger', 'source'
                #
                # where 'logger' is a task of the 'rock_logger' deployment.
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
                def start(task_name, name0, name1 = task_name)
                    attr_reader task_name
                    run_specs << [task_name, [name0, name1]]
                end

                def reader(name, port_name, options = Hash.new)
                    if options.respond_to?(:to_str)
                        options = { :attr_name => options }
                    end
                    options, policy = Kernel.filter_options options,
                        :attr_name => "#{name}_#{port_name}"
                    attr_reader options[:attr_name]
                    reader_specs << [name, port_name, options[:attr_name], policy]
                end

                def writer(name, port_name, options = Hash.new)
                    if options.respond_to?(:to_str)
                        options = { :attr_name => options }
                    end
                    options, policy = Kernel.filter_options options,
                        :attr_name => "#{name}_#{port_name}"
                    attr_reader options[:attr_name]
                    writer_specs << [name, port_name, options[:attr_name], policy]
                end
            end
        end
    end
end
