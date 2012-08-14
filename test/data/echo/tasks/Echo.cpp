#include "Echo.hpp"
#include <iostream>

using namespace echo;

Echo::Echo(std::string const& name, TaskCore::TaskState initial_state)
    : EchoBase(name, initial_state)
    , async(false)
{
    _ondemand.keepLastWrittenValue(true);
}

Echo::Echo(std::string const& name, RTT::ExecutionEngine* engine, TaskCore::TaskState initial_state)
    : EchoBase(name, engine, initial_state)
    , async(false)
{
    _ondemand.keepLastWrittenValue(true);
}

int Echo::write(int value)
{
    _output.write(value);
    _ondemand.write(value);
    return value;
}

void Echo::write_opaque(int value)
{
    OpaquePoint p(value, 2 * value);
    _output_opaque.write(p);
}

void Echo::kill()
{
    while(true)
        *((int*)0) = 0;
}




/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See Echo.hpp for more detailed
// documentation about them.

// bool Echo::configureHook()
// {
//     return true;
// }
// bool Echo::startHook()
// {
//     return true;
// }

void Echo::updateHook()
{
    int val;
    Int str;

    if (_input.read(val) == RTT::NewData)
        _output.write(val);
    else if (_input_struct.read(str) == RTT::NewData)
        _output.write(str.value);
    else if (async)
	_output.write(++async_old);

    OpaquePoint point;
    if (_input_opaque.read(point) == RTT::NewData)
        _output_opaque.write(point);

}

// void Echo::errorHook()
// {
// }
// void Echo::stopHook()
// {
// }
// void Echo::cleanupHook()
// {
// }

