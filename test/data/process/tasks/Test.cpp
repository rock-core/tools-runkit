#include "Test.hpp"

using namespace process;

Test::Test(std::string const& name, TaskCore::TaskState initial_state)
    : TestBase(name, initial_state)
{
    Simple val;
    val.a = 21;
    val.b = 42;
    _prop1.set(val);

    _prop2.set(84);
}







/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See Test.hpp for more detailed
// documentation about them.

// bool Test::configureHook() { return true; }
// bool Test::startHook() { return true; }

// void Test::updateHook() {}

// void Test::errorHook() {}
// void Test::stopHook() {}
// void Test::cleanupHook() {}

