#include "sink.hpp"
#include <iostream>

using namespace simple_sink;

sink::sink(std::string const& name, TaskCore::TaskState initial_state)
    : sinkBase(name, initial_state) {}

void sink::updateHook()
{
    int value;
    _cycle.read(value);

    _in0.read(value);
    _in1.read(value);
    _in2.read(value);
    _in3.read(value);
}







