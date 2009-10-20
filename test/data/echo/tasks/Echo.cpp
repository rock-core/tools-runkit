#include "Echo.hpp"
#include <iostream>

using namespace echo;

Echo::Echo(std::string const& name, TaskCore::TaskState initial_state)
    : EchoBase(name, initial_state)
    , async(false)
{
}

int Echo::write(int value)
{
    _output.write(value);
    return value;
}



bool Echo::asyncWrite(int value, int stop)
{
    if (value == 0)
	return false;
    if (async)
	return false;

    async     = true;
    async_old = value;
    _output.write(value);
    return true;
}

bool Echo::isAsyncWriteCompleted(int value, int stop)
{
    int current_input;
    if (_input.read(current_input))
    {
	if (current_input == stop)
	{
	    async = false;
	    return true;
	}
	return false;
    }
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

void Echo::updateHook(std::vector<RTT::PortInterface*> const& updated_ports)
{
    int val;
    Int str;
    if (_input.read(val))
        _output.write(val);
    else if (_input_struct.read(str))
        _output.write(str.value);
    else
	_output.write(++async_old);

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

