#ifndef SIMPLESOURCE_SOURCE_TASK_HPP
#define SIMPLESOURCE_SOURCE_TASK_HPP

#include "simple_source/sourceBase.hpp"

namespace simple_source {
    class source : public sourceBase
    {
	friend class sourceBase;
    protected:
        void updateHook();

    public:
        source(std::string const& name = "SimpleSource::source");
    };
}

#endif

