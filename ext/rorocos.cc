#include "ControlTaskC.h"
#include "DataFlowC.h"
#include <ruby.h>

#include "corba_access.hh"
#include <memory>

using namespace std;
static VALUE mOrocos;
static VALUE Corba;
static VALUE cTaskContext;
static VALUE cBufferPort;
static VALUE cDataPort;
static VALUE eNotFound;

template<typename T>
T& get_wrapped(VALUE self)
{
    void* object = 0;
    Data_Get_Struct(self, void, object);
    return *reinterpret_cast<T*>(object);
}
template<typename T>
void delete_object(void* obj) { delete( (T*)obj ); }
template<typename T>
VALUE simple_wrap(VALUE klass, T* obj = 0)
{
    if (! obj)
        obj = new T;

    VALUE robj = Data_Wrap_Struct(klass, 0, delete_object<T>, obj);
    rb_iv_set(robj, "@corba", Corba);
    return robj;
}


struct RTaskContext
{
    RTT::Corba::ControlTask_var        task;
    RTT::Corba::DataFlowInterface_var  ports;
};

struct RBufferPort
{ RTT::Corba::BufferChannel_var port; };
struct RDataPort
{ RTT::Corba::AssignableExpression_var   port; };

static VALUE orocos_components(VALUE mod)
{
    VALUE result = rb_ary_new();

    list<string> names = CorbaAccess::knownTasks();
    for (list<string>::const_iterator it = names.begin(); it != names.end(); ++it)
        rb_ary_push(result, rb_str_new2(it->c_str()));

    return result;
}

static VALUE task_context_get(VALUE klass, VALUE name)
{
    try {
        std::auto_ptr<RTaskContext> new_context( new RTaskContext );
        new_context->task  = CorbaAccess::findByName(StringValuePtr(name));
        new_context->ports = new_context->task->ports();

        VALUE obj = simple_wrap<RTaskContext>(cTaskContext, new_context.release());
        rb_iv_set(obj, "@name", name);
        return obj;
    }
    catch(...) {
        rb_raise(eNotFound, "task context %s not found", StringValuePtr(name));
    }
}
static VALUE task_context_port(VALUE obj, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(obj);
    RTT::Corba::DataFlowInterface::ConnectionModel port_model = context.ports->getConnectionModel(StringValuePtr(name));

    if (port_model == RTT::Corba::DataFlowInterface::Buffered)
    {
        auto_ptr<RBufferPort> rport( new RBufferPort );
        rport->port = context.ports->createBufferChannel( StringValuePtr(name) );
        return simple_wrap<RBufferPort>(cBufferPort, rport.release());
    }
    else
    {
        auto_ptr<RDataPort> rport( new RDataPort );
        rport->port = context.ports->createDataChannel( StringValuePtr(name) );
        return simple_wrap<RDataPort>(cDataPort, rport.release());
    }
}

static VALUE task_context_state(VALUE obj)
{
    RTaskContext& context = get_wrapped<RTaskContext>(obj);
    return INT2FIX(context.task->getTaskState());
}

extern "C" void Init_rorocos_ext()
{
    mOrocos = rb_define_module("Orocos");

    char const* argv[2] = { "bla", 0 };
    Corba   = Data_Wrap_Struct(rb_cObject, 0, delete_object<CorbaAccess>, new CorbaAccess(1, (char**)argv));
    rb_iv_set(mOrocos, "@corba", Corba);

    cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
#define SET_STATE_CONSTANT(ruby, cxx) rb_const_set(cTaskContext, rb_intern(#ruby), RTT::Corba::cxx);
    SET_STATE_CONSTANT(INIT, Init);
    SET_STATE_CONSTANT(PRE_OPERATIONAL, PreOperational);
    SET_STATE_CONSTANT(FATAL_ERROR, FatalError);
    SET_STATE_CONSTANT(STOPPED, Stopped);
    SET_STATE_CONSTANT(ACTIVE, Active);
    SET_STATE_CONSTANT(RUNNING, Running);
    SET_STATE_CONSTANT(RUNTIME_WARNING, RunTimeWarning);
    SET_STATE_CONSTANT(RUNTIME_ERROR, RunTimeError);
#undef SET_STATE_CONSTANT
    
    cBufferPort  = rb_define_class_under(mOrocos, "BufferPort", rb_cObject);
    cDataPort    = rb_define_class_under(mOrocos, "DataPort", rb_cObject);
    eNotFound    = rb_define_class_under(mOrocos, "NotFound", rb_eRuntimeError);

    rb_define_singleton_method(mOrocos, "components", RUBY_METHOD_FUNC(orocos_components), 0);
    rb_define_singleton_method(cTaskContext, "get", RUBY_METHOD_FUNC(task_context_get), 1);
    rb_define_method(cTaskContext, "port", RUBY_METHOD_FUNC(task_context_port), 1);
    rb_define_method(cTaskContext, "state", RUBY_METHOD_FUNC(task_context_state), 0);
}

