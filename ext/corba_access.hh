#ifndef EXEC_CLIENT_CONTROL_TASK_HPP
#define EXEC_CLIENT_CONTROL_TASK_HPP

#ifdef CORBA_IS_TAO
#include <tao/corba.h>
#include <orbsvcs/CosNamingC.h>
#else
#include <omniORB4/CORBA.h>
#endif

#include <exception>
#include "ControlTaskC.h"
#include <iostream>
#include <string>
#include <stack>
#include <list>

using namespace std;

/**
 * Thrown if a server does not exist or has the wrong type.
 */
struct IllegalServer 
    : public std::exception
{
    std::string reason;
    IllegalServer();
    ~IllegalServer() throw();
    const char* what() const throw();
};

/**
 * This class locates and connects to a Corba ControlTask.
 * It can do that through an IOR or through the NameService.
 */
class CorbaAccess
{
    static CORBA::ORB_var orb;
    static CosNaming::NamingContext_var rootContext;

public:
    CorbaAccess(int argc, char* argv[] );
    ~CorbaAccess();

    static CORBA::ORB_var getOrb();
    static CosNaming::NamingContext_var getRootContext();
    static std::list<std::string> knownTasks();
    static RTT::Corba::ControlTask_ptr findByName(std::string const& name);
};

#endif

