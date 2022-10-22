# frozen_string_literal: true

require "runkit/test"

describe Runkit::Namespace do
    attr_reader :object

    before do
        @object = Object.new
        object.extend Runkit::Namespace
    end
    describe "#split_name" do
        it "returns an empty string for the root namespace" do
            ns, name = object.split_name("/bla")
            assert_equal "", ns
        end
        it "returns the namespace without the leading slash for full names" do
            ns, name = object.split_name("/myns/bla")
            assert_equal "/myns", ns
        end
    end
end
