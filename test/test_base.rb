# frozen_string_literal: true

require "runkit/test"

describe "the Runkit module" do
    describe ".loaded?" do
        it "returns false after #clear" do
            assert Runkit.loaded? # setup() calls Runkit.initialize
            Runkit.clear
            assert !Runkit.loaded?
        end
        it "returns true after #load" do
            assert Runkit.loaded? # setup() calls Runkit.initialize
            Runkit.clear
            Runkit.load
            assert Runkit.loaded?
        end
    end

    describe "thread interdiction" do
        after do
            Runkit.allow_blocking_calls
        end

        it "raises if a CORBA-accessing method is called within the forbidden thread" do
            Runkit.forbid_blocking_calls
            assert_raises(Runkit::BlockingCallInForbiddenThread) do
                Runkit.name_service.get("test")
            end
        end
        it "returns false in #allow_blocking_calls if no thread was registered" do
            refute Runkit.allow_blocking_calls
        end
        it "returns the thread that was blocked in #allow_blocking_calls" do
            Runkit.forbid_blocking_calls
            assert_same Thread.current, Runkit.allow_blocking_calls
        end
        it "allows to disable the check once it has been enabled" do
            Runkit.forbid_blocking_calls
            Runkit.allow_blocking_calls
            assert_raises(Runkit::NotFound) do
                Runkit.name_service.get("test")
            end
        end
    end
end
end
