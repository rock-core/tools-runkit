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
end
