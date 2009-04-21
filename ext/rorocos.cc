#include "ControlTaskC.h"
#include "DataFlowC.h"
#include <ruby.h>
#include <typeinfo>

#include "corba.hh"
#include "misc.hh"
#include <memory>
#include <boost/tuple/tuple.hpp>

using namespace std;
using boost::tie;
static VALUE mOrocos;
static VALUE cTaskContext;
static VALUE cInputPort;
static VALUE cOutputPort;
static VALUE cPort;
static VALUE cAttribute;
VALUE eNotFound;

using namespace RTT::Corba;


struct RTaskContext
{
    RTT::Corba::ControlTask_var        task;
    RTT::Corba::DataFlowInterface_var  ports;
    RTT::Corba::AttributeInterface_var attributes;
    RTT::Corba::MethodInterface_var    methods;
    RTT::Corba::CommandInterface_var   commands;
};

struct RInputPort { };
struct ROutputPort { };

std::pair<RTaskContext*, std::string> getPortReference(VALUE port)
{
    VALUE task = rb_iv_get(port, "@task");
    VALUE name = rb_iv_get(port, "@name");

    RTaskContext& task_context = get_wrapped<RTaskContext>(task);
    return make_pair(&task_context, string(StringValuePtr(name)));
}

struct RAttribute
{
    RTT::Corba::Expression_var expr;
};

/* call-seq:
 *  Orocos.components => [name1, name2, name3, ...]
 *
 * Returns the names of the task contexts registered with Corba
 */
static VALUE orocos_task_names(VALUE mod)
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
        rb_funcall(obj, rb_intern("initialize"), 0);
        rb_iv_set(obj, "@name", rb_str_dup(name));
        return obj;
    }
    catch(...) {
        rb_raise(eNotFound, "task context '%s' not found", StringValuePtr(name));
    }
}

static VALUE task_context_equal_p(VALUE self, VALUE other)
{
    if (!rb_obj_is_kind_of(other, cTaskContext))
        return Qfalse;

    RTaskContext& self_  = get_wrapped<RTaskContext>(self);
    RTaskContext& other_ = get_wrapped<RTaskContext>(other);
    return self_.task->_is_equivalent(other_.task) ? Qtrue : Qfalse;
}

/* call-seq:
 *   task.has_port?(name) => true or false
 *
 * Returns true if the given name is the name of a port on this task context,
 * and false otherwise
 */
static VALUE task_context_has_port_p(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    try {
        context.ports->getPortType(StringValuePtr(name));
    }
    catch(RTT::Corba::NoSuchPortException)
    { return Qfalse; }
    return Qtrue;
}

/* call-seq:
 *   task.do_port(name) => port
 *
 * Returns the Orocos::DataPort or Orocos::BufferPort object representing the
 * remote port +name+. Raises NotFound if the port does not exist. This is an
 * internal method. Use TaskContext#port to get a port object.
 */
static VALUE task_context_do_port(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    RTT::Corba::PortType port_type;
    try {
        port_type      = context.ports->getPortType(StringValuePtr(name));
    }
    catch(RTT::Corba::NoSuchPortException)
    { 
        VALUE task_name = rb_iv_get(self, "@name");
        rb_raise(eNotFound, "task %s does not have a '%s' port",
                StringValuePtr(task_name),
                StringValuePtr(name));
    }

    VALUE obj = Qnil;
    if (port_type == RTT::Corba::Input)
    {
        auto_ptr<RInputPort> rport( new RInputPort );
        obj = simple_wrap(cInputPort, rport.release());
    }
    else if (port_type == RTT::Corba::Output)
    {
        auto_ptr<ROutputPort> rport( new ROutputPort );
        obj = simple_wrap(cOutputPort, rport.release());
    }

    rb_iv_set(obj, "@name", rb_str_dup(name));
    rb_iv_set(obj, "@task", self);
    VALUE type_name = rb_str_new2(context.ports->getDataType( StringValuePtr(name) ));
    rb_iv_set(obj, "@type_name", type_name);
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
        rb_yield(task_context_do_port(self, rb_str_new2(ports[i])));

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
 *
 */

/* call-seq:
 *  port.connected? => true or false
 *
 * Tests if this port is already part of a connection or not
 */
static VALUE port_connected_p(VALUE self)
{
    RTaskContext* task; string name;
    tie(task, name) = getPortReference(self);

    try
    { return task->ports->isConnected(name.c_str()) ? Qtrue : Qfalse; }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); } // is refined on the Ruby side
    catch(CORBA::TRANSIENT&) { rb_raise(eConn, ""); } // is refined on the Ruby side
    catch(CORBA::Exception&)
    { rb_raise(eCORBA, "unspecified error in the CORBA layer"); }
    return Qnil; // never reached
}

static RTT::Corba::ConnPolicy policyFromHash(VALUE options)
{
    RTT::Corba::ConnPolicy result;
    VALUE conn_type = SYM2ID(rb_hash_aref(options, ID2SYM(rb_intern("type"))));
    if (conn_type == rb_intern("data"))
        result.type = RTT::Corba::Data;
    else if (conn_type == rb_intern("buffer"))
        result.type = RTT::Corba::Buffer;
    else
    {
        VALUE obj_as_str = rb_funcall(conn_type, rb_intern("inspect"), 0);
        rb_raise(rb_eArgError, "invalid connection type %s", StringValuePtr(obj_as_str));
    }

    if (RTEST(rb_hash_aref(options, ID2SYM(rb_intern("init")))))
        result.init = true;
    else
        result.init = false;

    if (RTEST(rb_hash_aref(options, ID2SYM(rb_intern("pull")))))
        result.pull = true;
    else
        result.pull = false;

    result.size = NUM2INT(rb_hash_aref(options, ID2SYM(rb_intern("size"))));

    VALUE lock_type = SYM2ID(rb_hash_aref(options, ID2SYM(rb_intern("lock"))));
    if (lock_type == rb_intern("locked"))
        result.lock_policy = RTT::Corba::Locked;
    else if (lock_type == rb_intern("lock_free"))
        result.lock_policy = RTT::Corba::LockFree;
    else
    {
        VALUE obj_as_str = rb_funcall(lock_type, rb_intern("to_s"), 0);
        rb_raise(rb_eArgError, "invalid locking type %s", StringValuePtr(obj_as_str));
    }
    return result;
}

/* Actual implementation of #connect_to. Sanity checks are done in Ruby. Just
 * create the connection. 
 */
static VALUE do_port_connect_to(VALUE routput_port, VALUE rinput_port, VALUE options)
{
    RTaskContext* out_task; string out_name;
    tie(out_task, out_name) = getPortReference(routput_port);
    RTaskContext* in_task; string in_name;
    tie(in_task, in_name) = getPortReference(rinput_port);

    RTT::Corba::ConnPolicy policy = policyFromHash(options);

    try
    {
        out_task->ports->createConnection(out_name.c_str(),
                in_task->ports, in_name.c_str(),
                policy);
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); } // should be refined on the Ruby side
    catch(CORBA::TRANSIENT&) { rb_raise(eConn, ""); } // should be refined on the Ruby side
    catch(CORBA::Exception&) { rb_raise(eCORBA, "unspecified error in the CORBA layer"); }
    return Qnil; // never reached
}

static VALUE do_port_disconnect_all(VALUE port)
{
    RTaskContext* task; string name;
    tie(task, name) = getPortReference(port);

    try
    {
        task->ports->disconnect(name.c_str());
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    catch(CORBA::TRANSIENT&) { rb_raise(eConn, ""); }
    catch(CORBA::Exception& e) { rb_raise(eCORBA, "unspecified error in the CORBA layer: %s", typeid(e).name()); }
    return Qnil; // never reached
}

static VALUE do_port_disconnect_from(VALUE self, VALUE other)
{
    RTaskContext* self_task; string self_name;
    tie(self_task, self_name) = getPortReference(self);
    RTaskContext* other_task; string other_name;
    tie(other_task, other_name) = getPortReference(other);

    try
    {
        self_task->ports->disconnectPort(self_name.c_str(), other_task->ports, other_name.c_str());
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    catch(CORBA::TRANSIENT&) { rb_raise(eConn, ""); }
    catch(CORBA::Exception&) { rb_raise(eCORBA, "unspecified error in the CORBA layer"); }
    return Qnil; // never reached
}

/* Document-class: Orocos::TaskContext
 *
 * TaskContext in Orocos are the representation of the component: access to its
 * inputs and outputs (#each_port) and to its execution state (#state).
 *
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
    mCORBA  = rb_define_module_under(mOrocos, "CORBA");

    cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
    rb_const_set(cTaskContext, rb_intern("STATE_PRE_OPERATIONAL"),      INT2FIX(RTT::Corba::PreOperational));
    rb_const_set(cTaskContext, rb_intern("STATE_FATAL_ERROR"),          INT2FIX(RTT::Corba::FatalError));
    rb_const_set(cTaskContext, rb_intern("STATE_STOPPED"),              INT2FIX(RTT::Corba::Stopped));
    rb_const_set(cTaskContext, rb_intern("STATE_ACTIVE"),               INT2FIX(RTT::Corba::Active));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNNING"),              INT2FIX(RTT::Corba::Running));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNTIME_WARNING"),      INT2FIX(RTT::Corba::RunTimeWarning));
    rb_const_set(cTaskContext, rb_intern("STATE_RUNTIME_ERROR"),        INT2FIX(RTT::Corba::RunTimeError));
    
    cPort        = rb_define_class_under(mOrocos, "Port", rb_cObject);
    cOutputPort  = rb_define_class_under(mOrocos, "OutputPort", cPort);
    cInputPort   = rb_define_class_under(mOrocos, "InputPort", cPort);
    cAttribute   = rb_define_class_under(mOrocos, "Attribute", rb_cObject);
    eNotFound    = rb_define_class_under(mOrocos, "NotFound", rb_eRuntimeError);

    rb_define_singleton_method(mOrocos, "task_names", RUBY_METHOD_FUNC(orocos_task_names), 0);
    rb_define_singleton_method(cTaskContext, "get", RUBY_METHOD_FUNC(task_context_get), 1);
    rb_define_method(cTaskContext, "==", RUBY_METHOD_FUNC(task_context_equal_p), 1);
    rb_define_method(cTaskContext, "state", RUBY_METHOD_FUNC(task_context_state), 0);
    rb_define_method(cTaskContext, "has_port?", RUBY_METHOD_FUNC(task_context_has_port_p), 1);
    rb_define_method(cTaskContext, "do_port", RUBY_METHOD_FUNC(task_context_do_port), 1);
    rb_define_method(cTaskContext, "each_port", RUBY_METHOD_FUNC(task_context_each_port), 0);
    rb_define_method(cTaskContext, "attribute", RUBY_METHOD_FUNC(task_context_attribute), 1);
    rb_define_method(cTaskContext, "each_attribute", RUBY_METHOD_FUNC(task_context_each_attribute), 0);

    rb_define_method(cPort, "connected?", RUBY_METHOD_FUNC(port_connected_p), 0);
    rb_define_method(cOutputPort, "do_connect_to", RUBY_METHOD_FUNC(do_port_connect_to), 2);
    rb_define_method(cPort, "do_disconnect_from", RUBY_METHOD_FUNC(do_port_disconnect_from), 1);
    rb_define_method(cPort, "do_disconnect_all", RUBY_METHOD_FUNC(do_port_disconnect_all), 0);

    Orocos_CORBA_init();
//    rb_define_method(cPort, "do_connect", RUBY_METHOD_FUNC(port_do_connect), 1);
//    rb_define_method(cPort, "disconnect", RUBY_METHOD_FUNC(port_disconnect), 0);
//    rb_define_method(cPort, "connected?", RUBY_METHOD_FUNC(port_connected_p), 0);
}

