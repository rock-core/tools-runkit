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
static VALUE cPort;
static VALUE eNotFound;

using namespace RTT::Corba;

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
    RTT::Corba::AttributeInterface_var attributes;
    RTT::Corba::MethodInterface_var    methods;
    RTT::Corba::CommandInterface_var   commands;
};

struct RPortBase
{
    DataFlowInterface::PortType type;
};

struct RBufferPort : RPortBase
{
    BufferChannel_var channel;
};
struct RDataPort : RPortBase
{
    RTT::Corba::AssignableExpression_var channel;
};

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
        new_context->task       = CorbaAccess::findByName(StringValuePtr(name));
        new_context->ports      = new_context->task->ports();
        new_context->attributes = new_context->task->attributes();
        new_context->methods    = new_context->task->methods();
        new_context->commands   = new_context->task->commands();

        VALUE obj = simple_wrap<RTaskContext>(cTaskContext, new_context.release());
        rb_iv_set(obj, "@name", rb_str_dup(name));
        return obj;
    }
    catch(...) {
        rb_raise(eNotFound, "task context %s not found", StringValuePtr(name));
    }
}

static VALUE task_context_port(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    RTT::Corba::DataFlowInterface::ConnectionModel port_model = context.ports->getConnectionModel(StringValuePtr(name));

    DataFlowInterface::PortType type = context.ports->getPortType(StringValuePtr(name));

    VALUE obj;
    if (port_model == RTT::Corba::DataFlowInterface::Buffered)
    {
        auto_ptr<RBufferPort> rport( new RBufferPort );
        if (type != DataFlowInterface::ReadPort)
        {
            rport->channel = context.ports->createBufferChannel( StringValuePtr(name) );
            if (CORBA::is_nil(rport->channel))
                rb_raise(rb_eRuntimeError, "cannot get port '%s' from Corba", StringValuePtr(name));
        }
        rport->type = type;

        obj = simple_wrap<RBufferPort>(cBufferPort, rport.release());
    }
    else
    {
        auto_ptr<RDataPort> rport( new RDataPort );
        if (type != DataFlowInterface::ReadPort)
        {
            rport->channel = context.ports->createDataChannel( StringValuePtr(name) );
            if (CORBA::is_nil(rport->channel))
                rb_raise(rb_eRuntimeError, "cannot get port '%s' from Corba", StringValuePtr(name));
        }
        rport->type = type;

        obj = simple_wrap<RDataPort>(cDataPort, rport.release());
    }
    rb_iv_set(obj, "@name", rb_str_dup(name));
    return obj;
}

static VALUE task_context_each_port(VALUE self)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    RTT::Corba::DataFlowInterface::PortNames_var ports = context.ports->getPorts();

    for (int i = 0; i < ports->length(); ++i)
        rb_yield(task_context_port(self, rb_str_new2(ports[i])));

    return self;
}

static VALUE task_context_state(VALUE obj)
{
    RTaskContext& context = get_wrapped<RTaskContext>(obj);
    return INT2FIX(context.task->getTaskState());
}

static VALUE port_read_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type != DataFlowInterface::WritePort;
}

static VALUE port_write_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type != DataFlowInterface::ReadPort;
}

static VALUE port_read_write_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type == DataFlowInterface::ReadWritePort;
}


extern "C" void Init_rorocos_ext()
{
    mOrocos = rb_define_module("Orocos");

    char const* argv[2] = { "bla", 0 };
    Corba   = Data_Wrap_Struct(rb_cObject, 0, delete_object<CorbaAccess>, new CorbaAccess(1, (char**)argv));
    rb_iv_set(mOrocos, "@corba", Corba);

    cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
#define SET_STATE_CONSTANT(ruby, cxx) rb_const_set(cTaskContext, rb_intern(#ruby), INT2FIX(RTT::Corba::cxx));
    SET_STATE_CONSTANT(STATE_INIT, Init);
    SET_STATE_CONSTANT(STATE_PRE_OPERATIONAL, PreOperational);
    SET_STATE_CONSTANT(STATE_FATAL_ERROR, FatalError);
    SET_STATE_CONSTANT(STATE_STOPPED, Stopped);
    SET_STATE_CONSTANT(STATE_ACTIVE, Active);
    SET_STATE_CONSTANT(STATE_RUNNING, Running);
    SET_STATE_CONSTANT(STATE_RUNTIME_WARNING, RunTimeWarning);
    SET_STATE_CONSTANT(STATE_RUNTIME_ERROR, RunTimeError);
#undef SET_STATE_CONSTANT
    
    cPort        = rb_define_class_under(mOrocos, "Port", rb_cObject);
    cBufferPort  = rb_define_class_under(mOrocos, "BufferPort", cPort);
    cDataPort    = rb_define_class_under(mOrocos, "DataPort", cPort);
    eNotFound    = rb_define_class_under(mOrocos, "NotFound", rb_eRuntimeError);

    rb_define_singleton_method(mOrocos, "components", RUBY_METHOD_FUNC(orocos_components), 0);
    rb_define_singleton_method(cTaskContext, "get", RUBY_METHOD_FUNC(task_context_get), 1);
    rb_define_method(cTaskContext, "port", RUBY_METHOD_FUNC(task_context_port), 1);
    rb_define_method(cTaskContext, "each_port", RUBY_METHOD_FUNC(task_context_each_port), 0);
    rb_define_method(cTaskContext, "state", RUBY_METHOD_FUNC(task_context_state), 0);

    rb_define_method(cPort, "read?", RUBY_METHOD_FUNC(port_read_p), 0);
    rb_define_method(cPort, "write?", RUBY_METHOD_FUNC(port_write_p), 0);
    rb_define_method(cPort, "read_write?", RUBY_METHOD_FUNC(port_read_write_p), 0);
}

