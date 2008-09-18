#include "corba_access.hh"
#include <iostream>

#include "ControlTaskC.h"

int main(int argc, char** argv)
{
    CorbaAccess corba_access(argc, argv);

    list<string> names = CorbaAccess::knownTasks();
    for (list<string>::iterator it = names.begin(); it != names.end(); ++it)
    {
        RTT::Corba::ControlTask_var task = CorbaAccess::findByName(*it);
        std::cout << task->getTaskState() << std::endl;
    }
}

