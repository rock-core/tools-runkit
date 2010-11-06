#include "Task.hpp"

using namespace states;


Task::Task(std::string const& name)
    : TaskBase(name)
{
}


void Task::do_runtime_error()
{
    error();
}

void Task::do_exception()
{
    exception();
}

void Task::do_nominal_running()
{
    state(RUNNING);
}

void Task::do_fatal_error()
{
    fatal();
}

void Task::do_custom_runtime()
{
    state(CUSTOM_RUNTIME);
}

void Task::do_custom_error()
{
    error(CUSTOM_ERROR);
}

void Task::do_custom_exception()
{
    exception(CUSTOM_EXCEPTION);
}

void Task::do_custom_fatal()
{
    fatal(CUSTOM_FATAL);
}

void Task::do_recover()
{
    recover();
}




/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See Task.hpp for more detailed
// documentation about them.

// bool Task::configureHook()
// {
//     return true;
// }
// bool Task::startHook()
// {
//     return true;
// }

// void Task::updateHook()
// {
// }

// void Task::errorHook()
// {
// }
// void Task::stopHook()
// {
// }
// void Task::cleanupHook()
// {
// }

