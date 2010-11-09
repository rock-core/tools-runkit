/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "Task.hpp"

using namespace operations;

Task::Task(std::string const& name, TaskCore::TaskState initial_state)
    : TaskBase(name, initial_state)
{
}


void Task::empty()
{
    
}

int Task::simple(::Test::Parameters const& b)
{
    return b.set_point;
    
}

::Test::Parameters Task::simple_with_return(::Test::Parameters const& b)
{
    return b;
}

::Test::Opaque Task::with_returned_opaque(::Test::Parameters const& b)
{
    return ::Test::Opaque(b.set_point, b.threshold);
}

::Test::Parameters Task::with_opaque_argument(::Test::Opaque const& b)
{
    Test::Parameters result;
    result.set_point = b.getSetPoint();
    result.threshold = b.getThreshold();
    return result;
}

::Test::Parameters Task::with_returned_parameter(::Test::Parameters& a, ::Test::Opaque const& b)
{
    a.set_point = b.getSetPoint();
    a.threshold = b.getThreshold();
    return a;
    
}

::std::string Task::string_handling(::std::string const& b)
{
    
    return b + "ret";
    
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

