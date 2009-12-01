#ifndef UNCAUGHT_UNCAUGHT_TASK_HPP
#define UNCAUGHT_UNCAUGHT_TASK_HPP

#include "uncaught/UncaughtBase.hpp"


namespace RTT
{
    class NonPeriodicActivity;
}


namespace uncaught {
    class Uncaught : public UncaughtBase
    {
	friend class UncaughtBase;
    protected:
    
	void do_runtime_error();
    
    

    public:
        Uncaught(std::string const& name = "uncaught::Uncaught", TaskCore::TaskState initial_state = Stopped);

        RTT::NonPeriodicActivity* getNonPeriodicActivity();

        bool configureHook();

        bool startHook();

        void updateHook();
        
        void errorHook();

        void stopHook();

        void cleanupHook();
    };
}

#endif

