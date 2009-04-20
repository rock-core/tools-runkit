#include "corba.hh"
#include <list>
#include "misc.hh"
#include <typeinfo>
using namespace CORBA;
using namespace std;

VALUE mCORBA;
VALUE eCORBA;
VALUE corba_access = Qnil;
extern VALUE eNotFound;

CORBA::ORB_var               CorbaAccess::orb;
CosNaming::NamingContext_var CorbaAccess::rootContext;

CorbaAccess::CorbaAccess(int argc, char** argv)
{
    // First initialize the ORB, that will remove some arguments...
    orb = CORBA::ORB_init (argc, const_cast<char**>(argv), "omniORB4");
    if (CORBA::is_nil(orb))
        rb_raise(eCORBA, "failed to initialize the ORB");

    CORBA::Object_var rootObj = orb->resolve_initial_references("NameService");
    rootContext = CosNaming::NamingContext::_narrow(rootObj.in());
    if (CORBA::is_nil(rootContext))
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
        if (CORBA::is_nil(binding_it))
            return names;

        while(binding_it->next_n(10, binding_list))
        {
            CosNaming::BindingList list = binding_list.in();
            for (int i = 0; i < list.length(); ++i)
                names.push_back(list[i].binding_name[0].id.in());
        }
    }
    catch(CosNaming::NamingContext::NotFound) { }
    catch(CORBA::Exception& e)
    { rb_raise(eCORBA, "error talking to the CORBA name server: %s", typeid(e).name()); }

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
    if ( !CORBA::is_nil( mtask ) )
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

void CorbaAccess::unbind(std::string const& name)
{
    CosNaming::Name serverName;
    serverName.length(2);
    serverName[0].id = CORBA::string_dup("ControlTasks");
    serverName[1].id = CORBA::string_dup( name.c_str() );
    rootContext->unbind(serverName);
}

/* call-seq:
 *  Orocos::CORBA.unregister(name)
 *
 * Remove this name from the list of task contexts registered on the name server
 */
static VALUE corba_unregister(VALUE mod, VALUE name)
{
    string task_name = StringValuePtr(name);
    CorbaAccess::unbind(task_name);
    return Qnil;
}

static VALUE corba_set_call_timeout(VALUE mod, VALUE duration)
{
    omniORB::setClientCallTimeout(NUM2INT(duration));
    return Qnil;
}

static VALUE corba_set_connect_timeout(VALUE mod, VALUE duration)
{
    omniORB::setClientConnectTimeout(NUM2INT(duration));
    return Qnil;
}

/* call-seq:
 *   Orocos::CORBA.init => true or false
 *
 * Initializes the CORBA ORB and gets a reference to the local name server.
 * Returns true if a new connection has been made and false if the CORBA layer
 * was already initialized.
 *
 * It raises Orocos::CORBAError if either the ORB failed to initialize or the
 * name server cannot be found.
 */
static VALUE corba_init(VALUE mod)
{
    // Initialize only once ...
    if (!NIL_P(corba_access))
        return Qfalse;

    char const* argv[2] = { "bla", 0 };
    corba_access = Data_Wrap_Struct(rb_cObject, 0, delete_object<CorbaAccess>, new CorbaAccess(1, (char**)argv));
    rb_iv_set(mCORBA, "@corba", corba_access);
    return Qtrue;
}

void Orocos_CORBA_init()
{
    VALUE mOrocos = rb_define_module("Orocos");
    mCORBA = rb_define_module_under(mOrocos, "CORBA");
    eCORBA = rb_define_class_under(mOrocos, "CORBAError", rb_eRuntimeError);

    rb_define_singleton_method(mCORBA, "init", RUBY_METHOD_FUNC(corba_init), 0);
    rb_define_singleton_method(mCORBA, "unregister", RUBY_METHOD_FUNC(corba_unregister), 1);
    rb_define_singleton_method(mCORBA, "do_call_timeout", RUBY_METHOD_FUNC(corba_set_call_timeout), 1);
    rb_define_singleton_method(mCORBA, "do_connect_timeout", RUBY_METHOD_FUNC(corba_set_connect_timeout), 1);
}

