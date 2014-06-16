require 'orocos/test'

describe Orocos::ROS::OutputTopic do
    attr_reader :port, :topic, :name_service
    before do
        Orocos.load_typekit 'base'
        @name_service = Orocos::ROS::NameService.new
        task = new_ruby_task_context 'ros_test'
        @port = task.create_output_port('out', '/base/Time')
        port.publish_on_ros
        sleep 0.1
        node = name_service.get Orocos::ROS.caller_id
        @topic = node.output_port('/ros_test/out')
    end

    describe "connect_to" do
        it "should be able to connect to an input port" do
            task = new_ruby_task_context 'rock_test'
            input_port = task.create_input_port('in', '/base/Time')
            policy = Object.new
            flexmock(input_port).should_receive(:subscribe_to_ros).once.
                with('/ros_test/out', policy)
            topic.connect_to input_port, policy
        end
    end

    it "should be able to create a functional reader object" do
        reader = topic.reader
        sample = port.new_sample
        sample.microseconds = 342235
        port.write sample
        # Account for latency in the communication channel
        100.times do
            if data = reader.read_new
                assert_equal sample, data
                return
            end
            sleep 0.05
        end
    end
end

describe Orocos::ROS::InputTopic do
    attr_reader :port, :topic, :name_service
    before do
        @name_service = Orocos::ROS::NameService.new
        Orocos.load_typekit 'base'
        task = new_ruby_task_context 'ros_test'
        @port = task.create_input_port('in', '/base/Time')
        port.subscribe_to_ros
        sleep 0.1 # publication on ROS is asynchronous
        node = name_service.get Orocos::ROS.caller_id
        @topic = node.input_port('/ros_test/in')
    end

    describe "connect_to" do
        it "should be able to connect to an output port" do
            task = new_ruby_task_context 'rock_test'
            output_port = task.create_output_port('out', '/base/Time')
            policy = Object.new
            flexmock(output_port).should_receive(:publish_on_ros).once.
                with('/ros_test/in', policy)
            output_port.connect_to topic, policy
        end
    end

    it "should be able to create a writer object" do
        writer = topic.writer
        sample = port.new_sample
        sample.microseconds = 342235
        writer.write sample
        # Account for latency in the communication channel
        100.times do
            if data = port.read_new
                assert_equal sample, data
                return
            end
            sleep 0.05
        end
    end

end


