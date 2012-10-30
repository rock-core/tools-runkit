#include "rorocos.hh"
#include "lib/corba_name_service_client.hh"

#include <list>
#include <typeinfo>
#include <rtt/types/Types.hpp>

#include <rtt/transports/corba/TransportPlugin.hpp>
#include <rtt/transports/corba/CorbaLib.hpp>
#include <rtt/transports/corba/TaskContextServer.hpp>
#include <rtt/transports/corba/TaskContextProxy.hpp>
#include <rtt/transports/corba/CorbaDispatcher.hpp>

#include <rtt/Activity.hpp>

#include <boost/lexical_cast.hpp>
using namespace CORBA;
using namespace std;
using namespace boost;
using namespace corba;

extern VALUE mCORBA;
extern VALUE mOrocos;
extern VALUE eCORBA;
extern VALUE eComError;
extern VALUE corba_access;
extern VALUE eNotFound;
extern VALUE eNotInitialized;

static VALUE cNameService;

CorbaAccess* CorbaAccess::the_instance = NULL;
void CorbaAccess::init(std::string const& name, int argc, char* argv[])
{
    if (the_instance)
        return;
    the_instance = new CorbaAccess(name, argc, argv);
}
void CorbaAccess::deinit()
{
    delete the_instance;
    the_instance = NULL;
}

CorbaAccess::CorbaAccess(std::string const& name, int argc, char* argv[])
    : port_id_counter(0)
{
    // First initialize the ORB. We use TaskContextProxy::InitORB as we will
    // have to create a servant for our local DataFlowInterface object.
    RTT::corba::TaskContextServer::InitOrb(argc, argv);

    // Finally, create a dataflow interface and export it to CORBA. This is
    // needed to use the port interface. Since we're lazy, we just create a
    // normal TaskContext and use TaskContextServer to create the necessary
    // interfaces.
    std::string task_name;
    if (name.empty())
        task_name = std::string("orocosrb_") + boost::lexical_cast<std::string>(getpid());
    else
        task_name = name;

    m_task   = new RTT::TaskContext(task_name);
    RTT::corba::CorbaDispatcher::Instance(m_task->ports(), ORO_SCHED_OTHER, RTT::os::LowestPriority);

    // NOTE: should not be deleted by us, RTT's shutdown will do it
    m_task_server = RTT::corba::TaskContextServer::Create(m_task);
    m_corba_task = m_task_server->server();
    m_corba_dataflow = m_corba_task->ports();
}

CorbaAccess::~CorbaAccess()
{
    m_corba_task     = RTT::corba::CTaskContext::_nil();
    m_corba_dataflow = RTT::corba::CDataFlowInterface::_nil();

    RTT::corba::TaskContextServer::ShutdownOrb(true);

    // DON'T DELETE m_task_server: shutdown() will do it for us
    delete m_task;
}

RTaskContext* CorbaAccess::createRTaskContext(std::string const& ior)
{
    std::auto_ptr<RTaskContext> new_context( new RTaskContext );
    // check if ior is a valid IOR if not an exception is thrown
    new_context->task = getCTaskContext(ior);
    new_context->main_service = new_context->task->getProvider("this");
    new_context->ports      = new_context->task->ports();
    CORBA::String_var nm =  new_context->task->getName();
    new_context->name = std::string(nm.in());
    return new_context.release();
}

RTT::corba::CTaskContext_var CorbaAccess::getCTaskContext(std::string const& ior)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        throw std::runtime_error("Corba is not initialized. Call Orocos.initialize first.");

    // Use the ior to create the task object reference,
    CORBA::Object_var task_object;
    try
    {
        task_object = RTT::corba::ApplicationServer::orb->string_to_object ( ior.c_str() );
    }
    catch(CORBA::SystemException &e)
    {
        throw InvalidIORError("given IOR " + ior + " is not valid");
    }

    // Then check we can actually access it
    RTT::corba::CTaskContext_var mtask;
    // Now downcast the object reference to the appropriate type
    mtask = RTT::corba::CTaskContext::_narrow (task_object.in());

    if(CORBA::is_nil( mtask ))
        throw std::runtime_error("cannot narrorw task context.");
    return mtask;
}

RTT::corba::CDataFlowInterface_ptr CorbaAccess::getDataFlowInterface() const
{ return m_corba_dataflow; }

string CorbaAccess::getLocalPortName(VALUE port)
{
    RTaskContext* task; VALUE task_name, port_name;
    tie(task, task_name, port_name) = getPortReference(port);
    return std::string(StringValuePtr(task_name)) + "." + StringValuePtr(port_name) + "." + boost::lexical_cast<string>(++port_id_counter);
}

void CorbaAccess::addPort(RTT::base::PortInterface* local_port)
{
    m_task->ports()->addPort(*local_port);
}

void CorbaAccess::removePort(RTT::base::PortInterface* local_port)
{
    m_task->ports()->removePort(local_port->getName());
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
    CorbaAccess::deinit();
    rb_iv_set(mCORBA, "@corba", Qnil);
    corba_access = Qnil;
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
static VALUE corba_init(VALUE mod, VALUE name)
{
    // Initialize only once ...
    if (!NIL_P(corba_access))
        return Qfalse;

    try {
        char const* argv[2] = { "bla", 0 };
        CorbaAccess::init(StringValuePtr(name), 1, const_cast<char**>(argv));
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
    RTT::types::TypeInfoRepository::shared_ptr rtt_types =
        RTT::types::TypeInfoRepository::Instance();

    VALUE result = rb_ary_new();
    vector<string> all_types = rtt_types->getTypes();
    for (vector<string>::iterator it = all_types.begin(); it != all_types.end(); ++it)
    {
        RTT::types::TypeInfo* ti = rtt_types->type(*it);
        vector<int> transports = ti->getTransportNames();
        if (find(transports.begin(), transports.end(), ORO_CORBA_PROTOCOL_ID) != transports.end())
            rb_ary_push(result, rb_str_new2(it->c_str()));
    }
    return result;
}

static VALUE name_service_create(int argc, VALUE *argv,VALUE klass)
{
    // all parametes are forwarded to ruby initialize
    std::string ip;
    std::string port;

    if(argc > 0)
    {
        if(TYPE(argv[0]) == T_STRING)
            ip = StringValueCStr(argv[0]);
    }
    if(argc > 1)
    {
        if(TYPE(argv[1]) == T_STRING)
            port = StringValueCStr(argv[1]);
    }

    std::auto_ptr<NameServiceClient> new_name_service(new NameServiceClient(ip,port));
    VALUE obj = simple_wrap(cNameService, new_name_service.release());
    rb_obj_call_init(obj,argc,argv);
    return obj;
}

static VALUE name_service_ip(VALUE self)
{
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    return rb_str_new2(name_service.getIp().c_str());
}

static VALUE name_service_port(VALUE self)
{
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    return rb_str_new2(name_service.getPort().c_str());
}

static VALUE name_service_reset(VALUE self,VALUE ip, VALUE port)
{
    std::string sip = StringValueCStr(ip);
    std::string sport = StringValueCStr(port);
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    name_service.reset(sip,sport);
    return self;
}

enum error_code_t
{
    NO_ERROR,
    ERROR,
    NOT_FOUND_ERROR
};

#ifdef HAVE_RUBY_INTERN_H
struct NameServiceBlockingMsg
{
    NameServiceClient *name_service;   // pointer to the nameservice object
    void *return_value;          // must be initialized by the caller with the right type
    void *para;                  // parameter
    void *para2;                 // parameter
    std::string error_message;   // empty or string with the error message
    error_code_t error_code;

    NameServiceBlockingMsg():
        name_service(NULL),
        return_value(NULL),
        para(NULL),
        para2(NULL),
        error_code(NO_ERROR)
    {}
};

void processErrors(NameServiceBlockingMsg &msg)
{
    if(!msg.error_message.empty() || msg.error_code)
    {
        switch(msg.error_code)
        {
        case NOT_FOUND_ERROR:
            rb_raise(eNotFound,"%s", msg.error_message.c_str());
            break;
        case ERROR:
        default:
            rb_raise(eComError,"%s", msg.error_message.c_str());
        }
    }
}


static VALUE name_service_ior_blocking(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    std::string &ior = *(std::string *) msg.return_value;
    std::string &name = *(std::string *) msg.para;
    try
    {
        ior = msg.name_service->getIOR(name);
    }
    catch(CosNaming::NamingContext::NotFound &e)
    {
        msg.error_message = "NamingContex::NotFound";
        msg.error_code = NOT_FOUND_ERROR;
    }
    catch(CORBA::Exception &e)
    {
        msg.error_message = "Corba error " + std::string(e._name());
    }
    catch(std::runtime_error &e)
    {
        msg.error_message = e.what();
    }
    catch(...)
    {
        msg.error_message = "Unspecific exception in NameServiceClient::getIOR";
    }
    return Qnil;
}

static VALUE name_service_unbind_blocking(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    bool &result = *(bool *) msg.return_value;
    std::string &name = *(std::string *) msg.para;
    try
    {
        result = msg.name_service->unbind(name);
    }
    catch(CORBA::Exception &e)
    {
        msg.error_message = "Corba error " + std::string(e._name());
    }
    catch(std::runtime_error &e)
    {
        msg.error_message = e.what();
    }
    catch(...)
    {
        msg.error_message = "Unspecific exception in NameServiceClient::unbind";
    }
    return Qnil;
}

static VALUE name_service_validate_blocking(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    try
    {
        msg.name_service->validate();
    }
    catch(CORBA::Exception &e)
    {
        msg.error_message = "Corba error " + std::string(e._name());
    }
    catch(std::runtime_error &e)
    {
        msg.error_message = e.what();
    }
    catch(...)
    {
        msg.error_message = "Unspecific exception in NameServiceClient::unbind";
    }
    return Qnil;
}

static VALUE name_service_bind_blocking(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    RTaskContext &task = *(RTaskContext *) msg.para;
    std::string &name = *(std::string *) msg.para2;
    try
    {
        CORBA::Object_var obj = CORBA::Object::_duplicate(task.task);
        msg.name_service->bind(obj,name);
    }
    catch(CORBA::Exception &e)
    {
        msg.error_message = "Corba error " + std::string(e._name());
    }
    catch(std::runtime_error &e)
    {
        msg.error_message = e.what();
    }
    catch(...)
    {
        msg.error_message = "Unspecific exception in NameServiceClient::bind";
    }
    return Qnil;
}

static void name_service_task_context_names_abort(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    msg.name_service->abort();
}

static VALUE name_service_task_context_names_blocking(void *ptr)
{
    NameServiceBlockingMsg &msg = *(NameServiceBlockingMsg*)ptr;
    std::vector<std::string> &names = *(std::vector<std::string>*)msg.return_value;
    try
    {
        names = msg.name_service->getTaskContextNames();
    }
    catch(CORBA::Exception &e)
    {
        msg.error_message = "Corba error " + std::string(e._name());
    }
    catch(std::runtime_error &e)
    {
        msg.error_message = e.what();
    }
    catch(...)
    {
        msg.error_message = "Unspecific exception in NameServiceClient::getTaskContextNames";
    }
    return Qnil;
}
#endif

static VALUE name_service_task_context_names(VALUE self)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        rb_raise(eNotInitialized,"Corba is not initialized. Call Orocos.initialize first.");

    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    std::vector<std::string> names;

#ifdef HAVE_RUBY_INTERN_H
    NameServiceBlockingMsg msg;
    msg.name_service = &name_service;
    msg.return_value = &names;
    msg.para = NULL;
    msg.para2 = NULL;
    //rb_thread_call_without_gvl
    rb_thread_blocking_region(name_service_task_context_names_blocking,(void*)&msg,
                              name_service_task_context_names_abort, (void*)&msg);
    processErrors(msg);
#else
    try
    {
        names = name_service.getTaskContextNames();
    }
    catch(NameServiceClientError &e)
    {
        rb_raise(eComError,"%s", e.what());
    }
    CORBA_EXCEPTION_HANDLERS
#endif

    VALUE result = rb_ary_new();
    for (vector<string>::const_iterator it = names.begin(); it != names.end(); ++it)
        rb_ary_push(result, rb_str_new2(it->c_str()));
    return result;
}


static VALUE name_service_unbind(VALUE self,VALUE task_name)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        rb_raise(eNotInitialized,"Corba is not initialized. Call Orocos.initialize first.");
    
    std::string name = StringValueCStr(task_name);
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    bool result = false;

#ifdef HAVE_RUBY_INTERN_H
    NameServiceBlockingMsg msg;
    msg.name_service = &name_service;
    msg.return_value = &result;
    msg.para = &name;
    msg.para2 = NULL;
    rb_thread_blocking_region(name_service_unbind_blocking,(void*)&msg,NULL,NULL);
    processErrors(msg);
#else
    try
    {
        result = name_service.unbind(name);
    }
    catch(NameServiceClientError &e)
    {
        rb_raise(eComError,"%s",e.what());
    }
    CORBA_EXCEPTION_HANDLERS
#endif
    return result ? Qtrue : Qfalse;
}

static VALUE name_service_validate(VALUE self)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        rb_raise(eNotInitialized,"Corba is not initialized. Call Orocos.initialize first.");
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);

#ifdef HAVE_RUBY_INTERN_H
    NameServiceBlockingMsg msg;
    msg.name_service = &name_service;
    msg.return_value = NULL;
    msg.para = NULL;
    msg.para2 = NULL;
    rb_thread_blocking_region(name_service_validate_blocking,(void*)&msg,NULL,NULL);
    processErrors(msg);
#else
    try
    {
        name_service.validate();
    }
    catch(NameServiceClientError &e)
    {
        rb_raise(eComError, "%s",e.what());
    }
    CORBA_EXCEPTION_HANDLERS
#endif
    return Qnil;
}

static VALUE name_service_bind(VALUE self,VALUE task,VALUE task_name)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        rb_raise(eNotInitialized,"Corba is not initialized. Call Orocos.initialize first.");
    
    std::string name = StringValueCStr(task_name);
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);
    RTaskContext& context = get_wrapped<RTaskContext>(task);

#ifdef HAVE_RUBY_INTERN_H
    NameServiceBlockingMsg msg;
    msg.name_service = &name_service;
    msg.return_value = NULL;
    msg.para = &context;
    msg.para2 = &name;
    rb_thread_blocking_region(name_service_bind_blocking,(void*)&msg,NULL,NULL);
    processErrors(msg);
#else
    try
    {
        CORBA::Object_var obj = CORBA::Object::_duplicate(context.task);
        name_service.bind(obj,name);
    }
    catch(NameServiceClientError &e)
    {
        rb_raise(eComError,"%s", e.what());
    }
    CORBA_EXCEPTION_HANDLERS
#endif
    return Qnil;
}

static VALUE name_service_ior(VALUE self,VALUE task_name)
{
    if(CORBA::is_nil(RTT::corba::ApplicationServer::orb))
        rb_raise(eNotInitialized,"Corba is not initialized. Call Orocos.initialize first.");

    std::string ior;
    std::string name = StringValueCStr(task_name);
    NameServiceClient& name_service = get_wrapped<NameServiceClient>(self);

#ifdef HAVE_RUBY_INTERN_H
    NameServiceBlockingMsg msg;
    msg.name_service = &name_service;
    msg.para = &name;
    msg.para2 = NULL;
    msg.return_value = &ior;
    rb_thread_blocking_region(name_service_ior_blocking,(void*)&msg,NULL,NULL);
    processErrors(msg);
#else
    try
    {
        ior = name_service.getIOR(name);
    }
    catch(NameServiceClientError &e)
    {
        rb_raise(eComError,"%s", e.what());
    }
    CORBA_EXCEPTION_HANDLERS
#endif

    return rb_str_new2(ior.c_str());
}


void Orocos_init_CORBA()
{
    rb_define_singleton_method(mCORBA, "initialized?", RUBY_METHOD_FUNC(corba_is_initialized), 0);
    rb_define_singleton_method(mCORBA, "do_init", RUBY_METHOD_FUNC(corba_init), 1);
    rb_define_singleton_method(mCORBA, "do_deinit", RUBY_METHOD_FUNC(corba_deinit), 0);
    rb_define_singleton_method(mCORBA, "do_call_timeout", RUBY_METHOD_FUNC(corba_set_call_timeout), 1);
    rb_define_singleton_method(mCORBA, "do_connect_timeout", RUBY_METHOD_FUNC(corba_set_connect_timeout), 1);
    rb_define_singleton_method(mCORBA, "transportable_type_names", RUBY_METHOD_FUNC(corba_transportable_type_names), 0);

    VALUE cNameServiceBase = rb_define_class_under(mOrocos, "NameServiceBase",rb_cObject);
    cNameService = rb_define_class_under(mCORBA, "NameService",cNameServiceBase);
    rb_define_singleton_method(cNameService, "new", RUBY_METHOD_FUNC(name_service_create), -1);
    rb_define_method(cNameService, "do_task_context_names", RUBY_METHOD_FUNC(name_service_task_context_names), 0);
    rb_define_method(cNameService, "do_ior", RUBY_METHOD_FUNC(name_service_ior), 1);
    rb_define_method(cNameService, "do_ip", RUBY_METHOD_FUNC(name_service_ip), 0);
    rb_define_method(cNameService, "do_port", RUBY_METHOD_FUNC(name_service_port), 0);
    rb_define_method(cNameService, "do_validate", RUBY_METHOD_FUNC(name_service_validate), 0);
    rb_define_method(cNameService, "do_reset", RUBY_METHOD_FUNC(name_service_reset), 2);
    rb_define_method(cNameService, "do_unbind", RUBY_METHOD_FUNC(name_service_unbind), 1);
    rb_define_method(cNameService, "do_bind", RUBY_METHOD_FUNC(name_service_bind), 2);
}
