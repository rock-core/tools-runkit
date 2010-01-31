#include "rorocos.hh"
#include <list>
#include <typeinfo>
#include <rtt/Types.hpp>

#include <rtt/corba/CorbaLib.hpp>
#include <rtt/corba/ControlTaskProxy.hpp>
#include <rtt/corba/ControlTaskServer.hpp>
#include <boost/lexical_cast.hpp>
using namespace CORBA;
using namespace std;
using namespace boost;

VALUE mCORBA;
VALUE eCORBA;
VALUE eComError;
VALUE corba_access = Qnil;
extern VALUE eNotFound;

CORBA::ORB_var               CorbaAccess::orb;
CosNaming::NamingContext_var CorbaAccess::rootContext;

CorbaAccess* CorbaAccess::the_instance;
void CorbaAccess::init(int argc, char* argv[])
{
    if (the_instance)
        return;
    the_instance = new CorbaAccess(argc, argv);
}
void CorbaAccess::deinit()
{
    delete the_instance;
    the_instance = NULL;
}

CorbaAccess::CorbaAccess(int argc, char* argv[])
    : port_id_counter(0)
{
    // First initialize the ORB. We use ControlTaskProxy::InitORB as we will
    // have to create a servant for our local DataFlowInterface object.
    RTT::Corba::ControlTaskProxy::InitOrb(argc, argv);
    orb = RTT::Corba::ApplicationServer::orb;

    // Now, get the name service once and for all
    CORBA::Object_var rootObj = orb->resolve_initial_references("NameService");
    rootContext = CosNaming::NamingContext::_narrow(rootObj.in());
    if (CORBA::is_nil(rootContext))
        rb_raise(eCORBA, "cannot find CORBA naming service");

    // Finally, create a dataflow interface and export it to CORBA. This is
    // needed to use the port interface. Since we're lazy, we just create a
    // normal TaskContext and use ControlTaskProxy to create the necessary
    // interfaces.
    m_task   = new RTT::TaskContext("__orocos_rb__");
    m_task_server = RTT::Corba::ControlTaskServer::Create(m_task, false);
    RTT::Corba::ControlTask_var corba_ref = m_task_server->server();
    m_corba_dataflow = corba_ref->ports();
}

CorbaAccess::~CorbaAccess()
{
    m_corba_dataflow = RTT::Corba::DataFlowInterface::_nil();
    delete m_task_server;
    delete m_task;

    orb->shutdown(true);
    orb->destroy();
}

RTT::Corba::DataFlowInterface_ptr CorbaAccess::getDataFlowInterface() const
{ return m_corba_dataflow.in(); }

string CorbaAccess::getLocalPortName(VALUE port)
{
    RTaskContext* task; VALUE task_name, port_name;
    tie(task, task_name, port_name) = getPortReference(port);
    return std::string(StringValuePtr(task_name)) + "/" + StringValuePtr(port_name) + "/" + boost::lexical_cast<string>(++port_id_counter);
}

void CorbaAccess::addPort(RTT::PortInterface* local_port)
{
    m_task->ports()->addPort(local_port);
}

void CorbaAccess::removePort(RTT::PortInterface* local_port)
{
    m_task->ports()->removePort(local_port->getName());
}

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
            for (unsigned int i = 0; i < list.length(); ++i)
                names.push_back(list[i].binding_name[0].id.in());
        }
    }
    catch(CosNaming::NamingContext::NotFound)
    { return names; }
    CORBA_EXCEPTION_HANDLERS 

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
    catch(CosNaming::NamingContext::NotFound&)
    { rb_raise(eNotFound, "task context '%s' does not exist", name.c_str()); }
    CORBA_EXCEPTION_HANDLERS 

    // Then check we can actually access it
    RTT::Corba::ControlTask_var mtask;
    try { mtask = RTT::Corba::ControlTask::_narrow (task_object.in ()); }
    catch(CORBA::Exception&)
    { rb_raise(eNotFound, "task context '%s' is registered but the registered object is of wrong type", name.c_str()); }

    if ( !CORBA::is_nil( mtask ) )
    {
        try {
            CORBA::String_var nm = mtask->getName();
            return mtask._retn();
        }
        catch(CORBA::Exception&)
        {
            rb_raise(eNotFound, "task context '%s' was registered but cannot be contacted", name.c_str());
        }
    }
    rb_raise(eNotFound, "task context '%s' not found", name.c_str());
}

void CorbaAccess::unbind(std::string const& name)
{
    CosNaming::Name serverName;
    try {
        serverName.length(2);
        serverName[0].id = CORBA::string_dup( "ControlTasks" );
        serverName[1].id = CORBA::string_dup( name.c_str() );
        rootContext->unbind(serverName);
    } catch(CosNaming::NamingContext::NotFound) {}
    CORBA_EXCEPTION_HANDLERS
}

/* call-seq:
 *  Orocos::CORBA.unregister(name)
 *
 * Remove this name from the list of task contexts registered on the name server
 */
static VALUE corba_unregister(VALUE mod, VALUE name)
{
    string task_name = StringValuePtr(name);
    CorbaAccess::instance()->unbind(task_name);
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

static void corba_deinit(void*)
{
//    CorbaAccess::deinit();
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

    try {
        char const* argv[2] = { "bla", 0 };
        CorbaAccess::init(1, const_cast<char**>(argv));
        corba_access = Data_Wrap_Struct(rb_cObject, 0, corba_deinit, CorbaAccess::instance());
        rb_iv_set(mCORBA, "@corba", corba_access);
    } catch(CORBA::Exception& e) {
        rb_raise(eCORBA, "failed to contact the name server");
    }
    return Qtrue;
}

static VALUE corba_is_initialized(VALUE mod)
{ return NIL_P(corba_access) ? Qfalse : Qtrue; }

/* call-seq:
 *   Orocos::CORBA.transportable_type_names => name_list
 *
 * Returns an array of string that are the type names which can be transported
 * over the CORBA layer
 */
static VALUE corba_transportable_type_names(VALUE mod)
{
    RTT::TypeInfoRepository::shared_ptr rtt_types =
        RTT::types();

    VALUE result = rb_ary_new();
    vector<string> all_types = rtt_types->getTypes();
    for (vector<string>::iterator it = all_types.begin(); it != all_types.end(); ++it)
    {
        RTT::TypeInfo* ti = rtt_types->type(*it);
        vector<int> transports = ti->getTransportNames();
        if (find(transports.begin(), transports.end(), ORO_CORBA_PROTOCOL_ID) != transports.end())
            rb_ary_push(result, rb_str_new2(it->c_str()));
    }
    return result;
}

void Orocos_init_CORBA()
{
    VALUE mOrocos = rb_define_module("Orocos");
    mCORBA    = rb_define_module_under(mOrocos, "CORBA");
    eCORBA    = rb_define_class_under(mOrocos, "CORBAError", rb_eRuntimeError);
    eComError = rb_define_class_under(mCORBA, "ComError", eCORBA);

    rb_define_singleton_method(mCORBA, "initialized?", RUBY_METHOD_FUNC(corba_is_initialized), 0);
    rb_define_singleton_method(mCORBA, "do_init", RUBY_METHOD_FUNC(corba_init), 0);
    rb_define_singleton_method(mCORBA, "unregister", RUBY_METHOD_FUNC(corba_unregister), 1);
    rb_define_singleton_method(mCORBA, "do_call_timeout", RUBY_METHOD_FUNC(corba_set_call_timeout), 1);
    rb_define_singleton_method(mCORBA, "do_connect_timeout", RUBY_METHOD_FUNC(corba_set_connect_timeout), 1);
    rb_define_singleton_method(mCORBA, "transportable_type_names", RUBY_METHOD_FUNC(corba_transportable_type_names), 0);
}

