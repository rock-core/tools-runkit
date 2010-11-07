#include "source.hpp"

using namespace simple_source;

source::source(std::string const& name)
    : sourceBase(name) {}

void source::updateHook()
{
    static int cycle = 0;
    _cycle.write(++cycle);

    _out0.write(cycle);
    _out1.write(cycle);
    _out2.write(cycle);
    _out3.write(cycle);

    Int v = { cycle };
    _cycle_struct.write(v);
}







