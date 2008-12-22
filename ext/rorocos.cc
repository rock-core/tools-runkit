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
static VALUE cAttribute;
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
{ DataFlowInterface::PortType type; };

struct RBufferPort : RPortBase
{ BufferChannel_var channel; };
struct RDataPort : RPortBase
{ RTT::Corba::AssignableExpression_var channel; };

struct RAttribute
{
    RTT::Corba::Expression_var expr;
};

/* call-seq:
 *  Orocos.components => [name1, name2, name3, ...]
 *
 * Returns the names of the task contexts registered with Corba
 */
static VALUE orocos_components(VALUE mod)
{
    VALUE result = rb_ary_new();

    list<string> names = CorbaAccess::knownTasks();
    for (list<string>::const_iterator it = names.begin(); it != names.end(); ++it)
        rb_ary_push(result, rb_str_new2(it->c_str()));

    return result;
}

/* call-seq:
 *  TaskContext.get(name) => task
 *
 * Returns the TaskContext instance representing the remote task context
 * with the given name. Raises Orocos::NotFound if the task name does
 * not exist.
 */
static VALUE task_context_get(VALUE klass, VALUE name)
{
    try {
        std::auto_ptr<RTaskContext> new_context( new RTaskContext );
        new_context->task       = CorbaAccess::findByName(StringValuePtr(name));
        new_context->ports      = new_context->task->ports();
        new_context->attributes = new_context->task->attributes();
        new_context->methods    = new_context->task->methods();
        new_context->commands   = new_context->task->commands();

        VALUE obj = simple_wrap(cTaskContext, new_context.release());
        rb_iv_set(obj, "@name", rb_str_dup(name));
        return obj;
    }
    catch(...) {
        rb_raise(eNotFound, "task context '%s' not found", StringValuePtr(name));
    }
}

/* call-seq:
 *   task.port(name) => port
 *
 * Returns the Orocos::DataPort or Orocos::BufferPort object representing the
 * remote port +name+. Raises RuntimeError if the port does not exist.
 */
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
                rb_raise(eNotFound, "cannot get port '%s' from Corba", StringValuePtr(name));
        }
        rport->type = type;

        obj = simple_wrap(cBufferPort, rport.release());
    }
    else
    {
        auto_ptr<RDataPort> rport( new RDataPort );
        if (type != DataFlowInterface::ReadPort)
        {
            rport->channel = context.ports->createDataChannel( StringValuePtr(name) );
            if (CORBA::is_nil(rport->channel))
                rb_raise(eNotFound, "cannot get port '%s' from Corba", StringValuePtr(name));
        }
        rport->type = type;

        obj = simple_wrap(cDataPort, rport.release());
    }
    rb_iv_set(obj, "@name", rb_str_dup(name));
    rb_iv_set(obj, "@task", self);
    VALUE type_name = rb_str_new2(context.ports->getDataType( StringValuePtr(name) ));
    rb_iv_set(obj, "@typename", type_name);
    return obj;
}

/* call-seq:
 *  task.each_port { |p| ... } => task
 *
 * Enumerates the ports available on this task. This yields instances of either
 * Orocos::BufferPort or Orocos::DataPort
 */
static VALUE task_context_each_port(VALUE self)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    RTT::Corba::DataFlowInterface::PortNames_var ports = context.ports->getPorts();

    for (int i = 0; i < ports->length(); ++i)
        rb_yield(task_context_port(self, rb_str_new2(ports[i])));

    return self;
}

/* call-seq:
 *  task.attribute(name) => attribute
 *
 * Returns the Attribute object which represents the remote task's
 * Attribute or Property of the given name
 */
static VALUE task_context_attribute(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    std::auto_ptr<RAttribute> rattr(new RAttribute);
    rattr->expr = context.attributes->getProperty( StringValuePtr(name) );
    if (CORBA::is_nil(rattr->expr))
        rattr->expr = context.attributes->getAttribute( StringValuePtr(name) );
    if (CORBA::is_nil(rattr->expr))
        rb_raise(eNotFound, "no attribute or property named '%s'", StringValuePtr(name));

    VALUE type_name = rb_str_new2(rattr->expr->getTypeName());
    VALUE obj = simple_wrap(cAttribute, rattr.release());
    rb_iv_set(obj, "@name", rb_str_dup(name));
    rb_iv_set(obj, "@typename", type_name);
    return obj;
}

/* call-seq:
 *  task.each_attribute { |a| ... } => task
 *
 * Enumerates the attributes and properties that are available on
 * this task, as instances of Orocos::Attribute
 */
static VALUE task_context_each_attribute(VALUE self)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);

    {
        RTT::Corba::AttributeInterface::AttributeNames_var
            attributes = context.attributes->getAttributeList();
        for (int i = 0; i < attributes->length(); ++i)
            rb_yield(task_context_attribute(self, rb_str_new2(attributes[i])));
    }

    {
        RTT::Corba::AttributeInterface::PropertyNames_var
            properties = context.attributes->getPropertyList();
        for (int i = 0; i < properties->length(); ++i)
            rb_yield(task_context_attribute(self, rb_str_new2(properties[i].name)));
    }
}

/* call-seq:
 *  task.state => value
 *
 * Returns the state of the task, as an integer value. The possible values are
 * represented by the various +STATE_+ constants:
 * 
 *   STATE_PRE_OPERATIONAL
 *   STATE_STOPPED
 *   STATE_ACTIVE
 *   STATE_RUNNING
 *   STATE_RUNTIME_WARNING
 *   STATE_RUNTIME_ERROR
 *   STATE_FATAL_ERROR
 *
 * See Orocos own documentation for their meaning
 */
static VALUE task_context_state(VALUE obj)
{
    RTaskContext& context = get_wrapped<RTaskContext>(obj);
    return INT2FIX(context.task->getTaskState());
}

/* call-seq:
 *  port.connect(remote_port) => nil
 *
 * Connects the given output port to the specified remote port
 */
static VALUE port_do_connect(VALUE self, VALUE remote_port)
{
    VALUE src_task_r = rb_iv_get(self, "@task");
    VALUE src_name   = rb_iv_get(self, "@name");
    RTaskContext& src_task = get_wrapped<RTaskContext>(src_task_r);
    VALUE dst_task_r = rb_iv_get(remote_port, "@task");
    VALUE dst_name   = rb_iv_get(remote_port, "@name");
    RTaskContext& dst_task = get_wrapped<RTaskContext>(dst_task_r);

    if (!src_task.ports->connectPorts(StringValuePtr(src_name), dst_task.ports, StringValuePtr(dst_name)))
    {
        VALUE src_task_name = rb_iv_get(src_task_r, "@name");
        VALUE dst_task_name = rb_iv_get(dst_task_r, "@name");
        rb_raise(rb_eArgError, "cannot connect %s.%s to %s.%s",
                StringValuePtr(src_task_name),
                StringValuePtr(src_name),
                StringValuePtr(dst_task_name),
                StringValuePtr(dst_name));
    }
    return Qnil;
}

/* call-seq:
 *   port.disconnect => nil
 *
 * Remove all connections that go to or come from this port
 */
static VALUE port_disconnect(VALUE self)
{

    VALUE task_r = rb_iv_get(self, "@task");
    VALUE name   = rb_iv_get(self, "@name");
    RTaskContext& task = get_wrapped<RTaskContext>(task_r);
    task.ports->disconnect(StringValuePtr(name));
    return Qnil;
}

/* call-seq:
 *  port.connected? => true or false
 *
 * Tests if this port is already part of a connection or not
 */
static VALUE port_connected_p(VALUE self)
{

    VALUE task_r = rb_iv_get(self, "@task");
    VALUE name   = rb_iv_get(self, "@name");
    RTaskContext& task = get_wrapped<RTaskContext>(task_r);
    return task.ports->isConnected(StringValuePtr(name)) ? Qtrue : Qfalse;
}

/* call-seq:
 *   port.read? => true or false
 *
 * True if the port can be read, and false otherwise
 */
static VALUE port_read_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type != DataFlowInterface::WritePort;
}

/* call-seq:
 *   port.write? => true or false
 *
 * True if the port can be written, and false otherwise
 */
static VALUE port_write_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type != DataFlowInterface::ReadPort;
}

/* call-seq:
 *   port.read_write? => true or false
 *
 * True if the port can be read and written, and false otherwise
 */
static VALUE port_read_write_p(VALUE obj)
{
    RPortBase& port = get_wrapped<RPortBase>(obj);
    return port.type == DataFlowInterface::ReadWritePort;
}

/* Document-class: Orocos::TaskContext
 *
 * TaskContext in Orocos are the representation of the component: access to its
 * inputs and outputs (#each_port) and to its execution state (#state).
 *
 */
/* Document-class: Orocos::Port
 *
 * Ports are in Orocos the representation of the task's dynamic input and
 * output. Port instances are never used. The task's ports are either represented
 * by instances of Orocos::DataPort or Orocos::BufferPort.
 */
/* Document-class: Orocos::DataPort
 *
 * Ports are in Orocos the representation of the task's dynamic input and
 * output. In data ports, the data you read from the port is the last sample
 * ever written to it.
 *
 * See also Orocos::Port and Orocos::BufferPort
 */
/* Document-class: Orocos::BufferPort
 *
 * Ports are in Orocos the representation of the task's dynamic input and
 * output. In buffered ports, the data is kept as long as it is not read, meaning
 * that the target of the data link should be able to get all the samples ever
 * written on the wire.
 *
 * In Orocos, this is limited to a fixed number of samples (the size of the
 * buffer), so if the buffer is full, samples are still lost.
 *
 * See also Orocos::Port and Orocos::DataPort
 */
/* Document-class: Orocos::NotFound
 *
 * This exception is raised every time an Orocos object is required by name,
 * but the object does not exist.
 *
 * See for instance Orocos::TaskContext.get or Orocos::TaskContext#port
 */
/* Document-class: Orocos::Attribute
 *
 * Attributes and properties are in Orocos ways to parametrize the task contexts.
 * Instances of Orocos::Attribute actually represent both at the same time.
 */
/* Document-module: Orocos
 */
extern "C" void Init_rorocos_ext()
{
    mOrocos = rb_define_module("Orocos");

    char const* argv[2] = { "bla", 0 };
    Corba   = Data_Wrap_Struct(rb_cObject, 0, delete_object<CorbaAccess>, new CorbaAccess(1, (char**)argv));
    rb_iv_set(mOrocos, "@corba", Corba);

    cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
    rb_const_set(cTaskContext, rb_intern("STATE_PRE_OPERATIONAL"),      INT2FIX(RTT::Corba::PreOperational));
    rb_const_set(cTaskContext, rb_intern("STATE_FATAL_ERROR"),          INT2FIX(RTT::Corba::FatalError));
    rb_const_set(cTaskContext, rb_intern("STATE_STOPPED"),              INT2FIX(RTT::Corba::Stopped));
    rb_const_set(cTaskContext, rb_intern("STATE_ACTIVE"),               INT2FIX(RTT::Corba::Active));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNNING"),              INT2FIX(RTT::Corba::Running));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNTIME_WARNING"),      INT2FIX(RTT::Corba::RunTimeWarning));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNTIME_ERROR"),        INT2FIX(RTT::Corba::RunTimeError));
    
    cPort        = rb_define_class_under(mOrocos, "Port", rb_cObject);
    cBufferPort  = rb_define_class_under(mOrocos, "BufferPort", cPort);
    cDataPort    = rb_define_class_under(mOrocos, "DataPort", cPort);
    cAttribute   = rb_define_class_under(mOrocos, "Attribute", rb_cObject);
    eNotFound    = rb_define_class_under(mOrocos, "NotFound", rb_eRuntimeError);

    rb_define_singleton_method(mOrocos, "components", RUBY_METHOD_FUNC(orocos_components), 0);
    rb_define_singleton_method(cTaskContext, "get", RUBY_METHOD_FUNC(task_context_get), 1);
    rb_define_method(cTaskContext, "state", RUBY_METHOD_FUNC(task_context_state), 0);
    rb_define_method(cTaskContext, "port", RUBY_METHOD_FUNC(task_context_port), 1);
    rb_define_method(cTaskContext, "each_port", RUBY_METHOD_FUNC(task_context_each_port), 0);
    rb_define_method(cTaskContext, "attribute", RUBY_METHOD_FUNC(task_context_attribute), 1);
    rb_define_method(cTaskContext, "each_attribute", RUBY_METHOD_FUNC(task_context_each_attribute), 0);

    rb_define_method(cPort, "do_connect", RUBY_METHOD_FUNC(port_do_connect), 1);
    rb_define_method(cPort, "disconnect", RUBY_METHOD_FUNC(port_disconnect), 0);
    rb_define_method(cPort, "connected?", RUBY_METHOD_FUNC(port_connected_p), 0);
    rb_define_method(cPort, "read?", RUBY_METHOD_FUNC(port_read_p), 0);
    rb_define_method(cPort, "write?", RUBY_METHOD_FUNC(port_write_p), 0);
    rb_define_method(cPort, "read_write?", RUBY_METHOD_FUNC(port_read_write_p), 0);
}

