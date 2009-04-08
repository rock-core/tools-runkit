#include "corba_access.hh"
#include <list>
using namespace CORBA;
using namespace std;

CORBA::ORB_var               CorbaAccess::orb;
CosNaming::NamingContext_var CorbaAccess::rootContext;

CorbaAccess::CorbaAccess(int argc, char** argv)
{
    // First initialize the ORB, that will remove some arguments...
    orb = CORBA::ORB_init (argc, const_cast<char**>(argv), "omniORB4");

    CORBA::Object_var rootObj = orb->resolve_initial_references("NameService");
    rootContext = CosNaming::NamingContext::_narrow(rootObj.in());
    if (CORBA::is_nil(rootObj.in() ))
        rb_raise(eCORBA, "cannot find CORBA naming service");
}

CorbaAccess::~CorbaAccess()
{
    orb->shutdown(true);
    orb->destroy();
}

CORBA::ORB_var               CorbaAccess::getOrb() { return orb; }
CosNaming::NamingContext_var CorbaAccess::getRootContext() { return rootContext; }

list<string> CorbaAccess::knownTasks()
{
    CosNaming::Name serverName;
    serverName.length(1);
    serverName[0].id = CORBA::string_dup("ControlTasks");

    list<string> names;
    try {
        CORBA::Object_var control_tasks_var = rootContext->resolve(serverName);
        CosNaming::NamingContext_var control_tasks = CosNaming::NamingContext::_narrow (control_tasks_var);

        CosNaming::BindingList_var binding_list;
        CosNaming::BindingIterator_var binding_it;
        control_tasks->list(0, binding_list, binding_it);

        while(binding_it->next_n(10, binding_list))
        {
            CosNaming::BindingList list = binding_list.in();
            for (int i = 0; i < list.length(); ++i)
                names.push_back(list[i].binding_name[0].id.in());
        }
    }
    catch(CosNaming::NamingContext::NotFound) { }
    catch(CORBA::Exception&)
    { rb_raise(eCORBA, "error talking to the CORBA name server"); }

    return names;
}

RTT::Corba::ControlTask_ptr CorbaAccess::findByName(std::string const& name)
{
    // First thing, try to get a reference from the name server
    CosNaming::Name serverName;
    serverName.length(2);
    serverName[0].id = CORBA::string_dup("ControlTasks");
    serverName[1].id = CORBA::string_dup( name.c_str() );

    CORBA::Object_var task_object;
    try { task_object = rootContext->resolve(serverName); }
    catch (CORBA::Exception &e) {
        rb_raise(eCORBA, "cannot access CORBA naming service");
    }

    // Then check we can actually access it
    RTT::Corba::ControlTask_var mtask = RTT::Corba::ControlTask::_narrow (task_object.in ());
    if ( !CORBA::is_nil( mtask.in() ) )
    {
        try {
            CORBA::String_var nm = mtask->getName();
            return mtask._retn();
        }
        catch (CORBA::Exception &e) {
            rootContext->unbind(serverName);
        }
    }
    rb_raise(eNotFound, "task context '%s' not found", name.c_str());
}

