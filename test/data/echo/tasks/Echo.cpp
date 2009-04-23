#include "Echo.hpp"

using namespace echo;

Echo::Echo(std::string const& name, TaskCore::TaskState initial_state)
    : EchoBase(name, initial_state)
{
}

int Echo::write(int value)
{
    _output.write(value);
    return value;
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
    if (_input.read(val))
        _output.write(val);

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

