require 'orocos/test'

describe "behaviour when CORBA is not initialized" do
    it "the name service accesses raise Orocos::NotInitialized" do 
        service = Orocos::CORBA::NameService.new
        assert_raises(Orocos::NotInitialized) do
            service.names
        end
        assert_raises(Orocos::NotInitialized) do
            service.ior("bla")
        end
        assert_raises(Orocos::NotInitialized) do
            service.deregister("bla")
        end
    end
end
