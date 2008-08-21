#include "corba_access.hh"
#include <list>
using namespace CORBA;
using namespace std;

CORBA::ORB_var               CorbaAccess::orb;
CosNaming::NamingContext_var CorbaAccess::rootContext;

IllegalServer::IllegalServer() : reason("This server does not exist or has the wrong type.") {}
IllegalServer::~IllegalServer() throw() {}
const char* IllegalServer::what() const throw() { return reason.c_str(); }

CorbaAccess::CorbaAccess(int argc, char** argv)
{
    // First initialize the ORB, that will remove some arguments...
    orb = CORBA::ORB_init (argc, const_cast<char**>(argv), "omniORB4");

    CORBA::Object_var rootObj = orb->resolve_initial_references("NameService");
    rootContext = CosNaming::NamingContext::_narrow(rootObj.in());
    if (CORBA::is_nil(rootObj.in() )) {
        cerr << "CorbaAccess could not acquire NameService."<<endl;
        throw IllegalServer();
    }
    cout << "found CORBA NameService."<<endl;
}

CorbaAccess::~CorbaAccess()
{
    orb->shutdown(true);
    orb->destroy();
    std::cerr <<"Orb destroyed."<<std::endl;
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
    } catch(CosNaming::NamingContext::NotFound) { }

    return names;
}

RTT::Corba::ControlTask_ptr CorbaAccess::findByName(std::string const& name)
{
    try {
        CosNaming::Name serverName;
        serverName.length(2);
        serverName[0].id = CORBA::string_dup("ControlTasks");
        serverName[1].id = CORBA::string_dup( name.c_str() );

        // Get object reference
        CORBA::Object_var task_object = rootContext->resolve(serverName);
        RTT::Corba::ControlTask_var mtask = RTT::Corba::ControlTask::_narrow (task_object.in ());
        if ( CORBA::is_nil( mtask.in() ) ) {
            cerr << "Failed to acquire ControlTaskServer '"+name+"'."<<endl;
            throw IllegalServer();
        }
        cout << "Found '" << name << "'. Connecting ..." <<endl;
        CORBA::String_var nm = mtask->getName(); // force connect to object.
        cout << "Successfully connected to ControlTaskServer '" << nm << "'." <<endl;
        return mtask._retn();
    }
    catch (CORBA::Exception &e) {
        cerr<< "CORBA exception raised when resolving Object !" << endl;
        cerr << e._name() << endl;
        throw IllegalServer();
    }
    catch (...) {
        cerr <<"Unknown Exception in CorbaAccess construction!"<<endl;
        throw;
    }
}

