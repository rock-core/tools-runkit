/* Generated from orogen/lib/orogen/templates/tasks/Task.cpp */

#include "EchoSubmodel.hpp"

using namespace echo;

EchoSubmodel::EchoSubmodel(std::string const& name, TaskCore::TaskState initial_state)
    : EchoSubmodelBase(name, initial_state)
{
}

EchoSubmodel::EchoSubmodel(std::string const& name, RTT::ExecutionEngine* engine, TaskCore::TaskState initial_state)
    : EchoSubmodelBase(name, engine, initial_state)
{
}

EchoSubmodel::~EchoSubmodel()
{
}



/// The following lines are template definitions for the various state machine
// hooks defined by Orocos::RTT. See EchoSubmodel.hpp for more detailed
// documentation about them.

// bool EchoSubmodel::configureHook()
// {
//     if (! EchoSubmodelBase::configureHook())
//         return false;
//     return true;
// }
// bool EchoSubmodel::startHook()
// {
//     if (! EchoSubmodelBase::startHook())
//         return false;
//     return true;
// }
// void EchoSubmodel::updateHook()
// {
//     EchoSubmodelBase::updateHook();
// }
// void EchoSubmodel::errorHook()
// {
//     EchoSubmodelBase::errorHook();
// }
// void EchoSubmodel::stopHook()
// {
//     EchoSubmodelBase::stopHook();
// }
// void EchoSubmodel::cleanupHook()
// {
//     EchoSubmodelBase::cleanupHook();
// }

