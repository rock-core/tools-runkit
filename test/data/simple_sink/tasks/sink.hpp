#ifndef SIMPLESINK_SINK_TASK_HPP
#define SIMPLESINK_SINK_TASK_HPP

#include "simple_sink/sinkBase.hpp"

namespace simple_sink {
    class sink : public sinkBase
    {
	friend class sinkBase;
    protected:
        void updateHook();
    
    

    public:
        sink(std::string const& name = "simple_sink::sink", TaskCore::TaskState initial_state = Stopped);
    };
}

#endif

