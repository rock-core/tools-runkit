#ifndef OROCOS_RB_EXT_CORBA_HH
#define OROCOS_RB_EXT_CORBA_HH

#include <omniORB4/CORBA.h>

#include <exception>
#include "ControlTaskC.h"
#include <iostream>
#include <string>
#include <stack>
#include <list>
#include <ruby.h>

using namespace std;

extern VALUE mCORBA;
extern VALUE corba_access;
extern VALUE eCORBA;
extern VALUE eConn;
extern void Orocos_CORBA_init();

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
    static void unbind(std::string const& name);
};

#endif

