$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'orocos'
require 'orocos/test'
require 'orocos/nameservice'
require 'minitest/spec'

MiniTest::Unit.autorun

TEST_DIR = File.expand_path(File.dirname(__FILE__))
DATA_DIR = File.join(TEST_DIR, 'data')
WORK_DIR = File.join(TEST_DIR, 'working_copy')

include Orocos

avahi_options = { :searchdomains => [ "_orocosrbtest._tcp" ] }

describe "Nameservice" do
    include Orocos::Spec

    it "throws on enabling unknown type" do
        assert_raises(NameError) { Nameservice::Provider::get_instance_of("foo", {}) }
    end

    it "throws on resolve without providers" do
        Nameservice::reset
        assert_raises(Orocos::NotFound) { Nameservice::resolve("foo") }
    end

    it "throws if resolve is not implemented" do
        Nameservice::reset
        Nameservice::enable(:Provider)     
        assert_raises(NotImplementedError) { Nameservice::resolve("foo") }
    end

    it "throws if resolve_by_type is not supported" do
        Nameservice::reset
        Nameservice::enable(:Provider)     
        assert(Nameservice::resolve_by_type("foo"))
    end

    it "throws if resolve fails for AVAHI" do
        Nameservice::reset
        Nameservice::enable(:AVAHI, avahi_options)     
        assert_raises(Orocos::NotFound) { Nameservice::resolve("foo") }
    end

    it "retrieves nameservice instance when available" do
        Nameservice::reset
        assert(!Nameservice::get(:AVAHI))
        Nameservice::enable(:AVAHI, avahi_options)     
        assert(Nameservice::get(:AVAHI))
    end

    it "retrieves options for available type" do
        Nameservice::reset
        assert_raises(NameError) { Nameservice::options(:BLA) }
        Nameservice::enable(:AVAHI, avahi_options)
        options = Nameservice::options(:AVAHI)
        assert(options[:searchdomains])
    end

    it "allows checking if enabled" do
        Nameservice::reset
        assert(!Nameservice.enabled?(:AVAHI))
        Nameservice::enable(:AVAHI, avahi_options)
        assert(Nameservice::enabled?(:AVAHI))
    end

    it "check on required option in AVAHI" do
        Nameservice::reset
        assert_raises(ArgumentError) { Nameservice::enable(:AVAHI) }
    end
        
end
