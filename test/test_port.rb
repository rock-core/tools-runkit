require 'orocos/test'

describe Orocos::Port do
    include Orocos::Spec

    it "should not be possible to create an instance directly" do
	assert_raises(NoMethodError) { Orocos::Port.new }
    end

    it "should check equality based on CORBA reference" do
        task = new_ruby_task_context 'task'
        task.create_output_port 'out', '/double'
        task = Orocos.get 'task'
        p1 = task.port 'out'
        # Remove p1 from source's port cache
        task.instance_variable_get("@ports").delete("out")
        p2 = task.port 'out'
        refute_same(p1, p2)
        assert_equal(p1, p2)
    end

    describe ".validate_policy" do
        it "should raise if a buffer is given without a size" do
            assert_raises(ArgumentError) { Orocos::Port.validate_policy :type => :buffer }
        end
        it "should raise if a data is given with a size" do
            assert_raises(ArgumentError) { Orocos::Port.validate_policy :type => :data, :size => 10 }
        end
    end
end
