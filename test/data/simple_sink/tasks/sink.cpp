#include "sink.hpp"
#include <iostream>

using namespace simple_sink;

sink::sink(std::string const& name, TaskCore::TaskState initial_state)
    : sinkBase(name, initial_state) {}

void sink::updateHook()
{
    int value;
    if (_cycle.connected())
    {
        _cycle.read(value);
        std::cout << "got " << value << std::endl;
    }
    else
        std::cout << "not connected" << value << std::endl;
}







