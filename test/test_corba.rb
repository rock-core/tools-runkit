# frozen_string_literal: true

require "orocos/test"

describe "the Orocos::CORBA module" do
    it "should be able to list types that can be transported through CORBA" do
        types = Orocos::CORBA.transportable_type_names
        assert(types.include?("/double"), "'double' is not part of #{types.join(', ')}")
    end

    it "should be able to load typekit plugins" do
        Orocos.load_typekit "process"
        types = Orocos::CORBA.transportable_type_names
        assert(types.include?("/process/Simple"))
    end

    it "should load type registries associated with the plugins" do
        assert_raises(Typelib::NotFound) { Orocos.registry.get("/process/Simple") }
        Orocos.load_typekit "process"
        assert(Orocos.registry.get("/process/Simple"))
    end
end
