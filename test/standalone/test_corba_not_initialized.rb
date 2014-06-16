require 'orocos/test'

class TC_CORBA_Standalone < Minitest::Test
    def test_taskcontext_get_fails_if_corba_is_not_initialized
        assert_raises(Orocos::NotInitialized) { Orocos::TaskContext.get 'bla' }
        assert_raises(Orocos::NotInitialized) { Orocos::TaskContext.do_get 'bla' }
        assert_raises(Orocos::NotInitialized) { Orocos::TaskContext.do_get_from_ior 'bla' }
        assert_raises(Orocos::NotInitialized) { Orocos::TaskContext.reachable? 'bla' }
        Orocos.initialize
        assert_raises(Orocos::NotFound) { Orocos::TaskContext.get 'bla' }
        assert_raises(Orocos::NotFound) { Orocos::TaskContext.do_get 'bla' }
        assert_raises(Orocos::NotFound) { Orocos::TaskContext.do_get_from_ior 'bla' }
        assert(!Orocos::TaskContext.reachable?('bla'))
    end
end
