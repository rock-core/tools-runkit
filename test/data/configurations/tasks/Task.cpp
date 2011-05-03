/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "Task.hpp"

using namespace configurations;

Task::Task(std::string const& name, TaskCore::TaskState initial_state)
    : TaskBase(name, initial_state)
{
    {
        std::vector<int> default_value;
        default_value.resize(10, 5);
        for (int i = 0; i < 10; ++i)
            default_value[i] = i;
        _simple_container.set(default_value);
    }

    {
        ComplexStructure str;
        str.enm = First;
        str.simple_container.resize(10);
        str.compound.simple_container.resize(10);
        for (int i = 0; i < 10; ++i)
        {
            str.simple_container.push_back(i);
            str.simple_array[i] = 10 + i;
            str.compound.simple_array[i] = 100 + i;
            str.compound.simple_container[i] = 200 + i;
            str.array_of_compound[i].intg = 300 + i;
            str.array_of_vector_of_compound[i].resize(10);
            str.array_of_vector_of_compound[i][i].intg = 3000 + i;
            str.compound.complex_array[i].intg = 1000 + i;
            str.compound.complex_container.push_back(ArrayOfArrayElement());
            str.compound.complex_container.back().intg = 2000 + i;
        }
        _compound.set(str);
    }
}

Task::~Task()
{
}



/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See Task.hpp for more detailed
// documentation about them.

// bool Task::configureHook()
// {
//     if (! TaskBase::configureHook())
//         return false;
//     return true;
// }
// bool Task::startHook()
// {
//     if (! TaskBase::startHook())
//         return false;
//     return true;
// }
// void Task::updateHook()
// {
//     TaskBase::updateHook();
// }
// void Task::errorHook()
// {
//     TaskBase::errorHook();
// }
// void Task::stopHook()
// {
//     TaskBase::stopHook();
// }
// void Task::cleanupHook()
// {
//     TaskBase::cleanupHook();
// }

