# frozen_string_literal: true

require "runkit/test"

describe "the Runkit::CORBA module" do
    it "should be able to list types that can be transported through CORBA" do
        types = Runkit::CORBA.transportable_type_names
        assert(types.include?("/double"), "'double' is not part of #{types.join(', ')}")
    end

    it "should be able to load typekit plugins" do
        Runkit.load_typekit "process"
        types = Runkit::CORBA.transportable_type_names
        assert(types.include?("/process/Simple"))
    end

    it "should load type registries associated with the plugins" do
        assert_raises(Typelib::NotFound) { Runkit.registry.get("/process/Simple") }
        Runkit.load_typekit "process"
        assert(Runkit.registry.get("/process/Simple"))
    end
end
