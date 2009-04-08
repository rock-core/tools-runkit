#include "source.hpp"

using namespace simple_source;

source::source(std::string const& name, TaskCore::TaskState initial_state)
    : sourceBase(name, initial_state) {}

void source::updateHook()
{
    static int cycle = 0;
    _cycle.write(++cycle);
}







