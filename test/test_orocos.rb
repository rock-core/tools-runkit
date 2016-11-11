require 'orocos/test'

describe Orocos do
    describe "thread interdiction" do
        after do
            Orocos.allow_blocking_calls
        end

        it "raises if a CORBA-accessing method is called within the forbidden thread" do
            Orocos.forbid_blocking_calls
            assert_raises(Orocos::BlockingCallInForbiddenThread) do
                Orocos.name_service.get('test')
            end
        end
        it "returns false in #allow_blocking_calls if no thread was registered" do
            refute Orocos.allow_blocking_calls
        end
        it "returns the thread that was blocked in #allow_blocking_calls" do
            Orocos.forbid_blocking_calls
            assert_same Thread.current, Orocos.allow_blocking_calls
        end
        it "allows to disable the check once it has been enabled" do
            Orocos.forbid_blocking_calls
            Orocos.allow_blocking_calls
            assert_raises(Orocos::NotFound) do
                Orocos.name_service.get('test')
            end
        end
    end
end
