# frozen_string_literal: true

require "runkit/test"

describe "the Runkit::CORBA module" do
    it "lists types that can be transported through CORBA" do
        types = Runkit::CORBA.transportable_type_names
        assert(types.include?("/double"), "'double' is not part of #{types.join(', ')}")
    end

    it "loads typekit plugins" do
        Runkit.load_typekit "base"
        types = Runkit::CORBA.transportable_type_names
        assert(types.include?("/base/geometry/Spline<3>"))
    end
end
