# frozen_string_literal: true

require "runkit/test"

describe "behaviour when CORBA is not initialized" do
    it "the name service accesses raise Runkit::NotInitialized" do
        service = Runkit::CORBA::NameService.new
        assert_raises(Runkit::NotInitialized) do
            service.names
        end
        assert_raises(Runkit::NotInitialized) do
            service.ior("bla")
        end
        assert_raises(Runkit::NotInitialized) do
            service.deregister("bla")
        end
    end
end
