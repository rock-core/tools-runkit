#include "sink.hpp"
#include <iostream>

using namespace simple_sink;

sink::sink(std::string const& name)
    : sinkBase(name) {}

void sink::updateHook()
{
    int value;
    if (_cycle.connected())
    {
        _cycle.Get(value);
        std::cout << "got " << value << std::endl;
    }
    else
        std::cout << "not connected" << value << std::endl;
}







