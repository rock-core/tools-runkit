#include "rorocos.hh"
#include <typeinfo>

#include <memory>
#include <boost/tuple/tuple.hpp>

#include <rtt/Types.hpp>
#include <rtt/Toolkit.hpp>
#include <rtt/RealTimeToolkit.hpp>
#include <rtt/PortInterface.hpp>

#include <typelib_ruby.hh>

using namespace std;
using namespace boost;
using namespace RTT::Corba;

static VALUE mOrocos;
static VALUE cTaskContext;
static VALUE cInputPort;
static VALUE cOutputPort;
static VALUE cPortAccess;
static VALUE cInputWriter;
static VALUE cOutputReader;
static VALUE cPort;
static VALUE cAttribute;
VALUE eNotFound;
static VALUE eConnectionFailed;
static VALUE eStateTransitionFailed;

extern void Orocos_init_CORBA();
extern void Orocos_init_data_handling();
extern void Orocos_init_methods();
static RTT::Corba::ConnPolicy policyFromHash(VALUE options);

extern RTT::TypeInfo* get_type_info(std::string const& name)
{
    RTT::TypeInfoRepository::shared_ptr type_registry = RTT::types();
    RTT::TypeInfo* ti = type_registry->type(name);
    if (! ti)
        rb_raise(rb_eArgError, "type '%s' is not registered in the RTT type system", name.c_str());
    return ti;
}

tuple<RTaskContext*, VALUE, VALUE> getPortReference(VALUE port)
{
    VALUE task = rb_iv_get(port, "@task");
    VALUE task_name = rb_iv_get(task, "@name");
    VALUE port_name = rb_iv_get(port, "@name");

    RTaskContext& task_context = get_wrapped<RTaskContext>(task);
    return make_tuple(&task_context, task_name, port_name);
}

/* call-seq:
 *  Orocos.components => [name1, name2, name3, ...]
 *
 * Returns the names of the task contexts registered with Corba
 */
static VALUE orocos_task_names(VALUE mod)
{
    VALUE result = rb_ary_new();

    list<string> names = CorbaAccess::instance()->knownTasks();
    for (list<string>::const_iterator it = names.begin(); it != names.end(); ++it)
        rb_ary_push(result, rb_str_new2(it->c_str()));

    return result;
}

// call-seq:
//  TaskContext.get(name) => task
//
// Returns the TaskContext instance representing the remote task context
// with the given name. Raises Orocos::NotFound if the task name does
// not exist.
///
static VALUE task_context_get(VALUE klass, VALUE name)
{
    try {
        std::auto_ptr<RTaskContext> new_context( new RTaskContext );
        new_context->task       = CorbaAccess::instance()->findByName(StringValuePtr(name));
        new_context->ports      = new_context->task->ports();
        new_context->attributes = new_context->task->attributes();
        new_context->methods    = new_context->task->methods();
        new_context->commands   = new_context->task->commands();

        VALUE obj = simple_wrap(cTaskContext, new_context.release());
        rb_funcall(obj, rb_intern("initialize"), 0);
        rb_iv_set(obj, "@name", rb_str_dup(name));
        return obj;
    }
    CORBA_EXCEPTION_HANDLERS;
}

static VALUE task_context_equal_p(VALUE self, VALUE other)
{
    if (!rb_obj_is_kind_of(other, cTaskContext))
        return Qfalse;

    RTaskContext& self_  = get_wrapped<RTaskContext>(self);
    RTaskContext& other_ = get_wrapped<RTaskContext>(other);
    return self_.task->_is_equivalent(other_.task) ? Qtrue : Qfalse;
}

// call-seq:
//   task.has_port?(name) => true or false
//
// Returns true if the given name is the name of a port on this task context,
// and false otherwise
///
static VALUE task_context_has_port_p(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    try {
        context.ports->getPortType(StringValuePtr(name));
    }
    catch(RTT::Corba::NoSuchPortException) { return Qfalse; }
    CORBA_EXCEPTION_HANDLERS
    return Qtrue;
}

// call-seq:
//   task.do_port(name) => port
//
// Returns the Orocos::DataPort or Orocos::BufferPort object representing the
// remote port +name+. Raises NotFound if the port does not exist. This is an
// internal method. Use TaskContext#port to get a port object.
///
static VALUE task_context_do_port(VALUE self, VALUE name)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    RTT::Corba::PortType port_type;
    CORBA::String_var    type_name;
    try {
        port_type = context.ports->getPortType(StringValuePtr(name));
        type_name = context.ports->getDataType(StringValuePtr(name));
    }
    catch(RTT::Corba::NoSuchPortException)
    { 
        VALUE task_name = rb_iv_get(self, "@name");
        rb_raise(eNotFound, "task %s does not have a '%s' port",
                StringValuePtr(task_name),
                StringValuePtr(name));
    }
    CORBA_EXCEPTION_HANDLERS

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
    rb_iv_set(obj, "@type_name", rb_str_new2(type_name));
    rb_funcall(obj, rb_intern("initialize"), 0);
    return obj;
}

static VALUE task_context_each_port(VALUE self)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);
    try {
        RTT::Corba::DataFlowInterface::PortNames_var ports = context.ports->getPorts();

        for (int i = 0; i < ports->length(); ++i)
            rb_yield(task_context_do_port(self, rb_str_new2(ports[i])));
    }
    CORBA_EXCEPTION_HANDLERS

    return self;
}

static void delete_port(RTT::PortInterface* port)
{
    port->disconnect();
    CorbaAccess::instance()->removePort(port);
    delete port;
}

static VALUE do_input_port_writer(VALUE port, VALUE type_name, VALUE policy)
{
    CorbaAccess* corba = CorbaAccess::instance();

    // Get the port and create an anti-clone of it
    RTaskContext* task; VALUE port_name;
    tie(task, tuples::ignore, port_name) = getPortReference(port);
    RTT::TypeInfo* ti = get_type_info(StringValuePtr(type_name));

    std::string local_name = corba->getLocalPortName(port);
    RTT::PortInterface* local_port = ti->outputPort(local_name);

    // Register this port on our data flow interface, and call CORBA to connect
    // both ports
    corba->addPort(local_port);
    try {
	bool result = corba->getDataFlowInterface()->createConnection(local_name.c_str(),
		task->ports, StringValuePtr(port_name),
		policyFromHash(policy));
        if (!local_port->connected() || !result)
        {
            corba->removePort(local_port);
            rb_raise(eConnectionFailed, "failed to connect the writer object to its remote port");
        }
    }
    CORBA_EXCEPTION_HANDLERS

    // Finally, wrap the new port in a Ruby object
    VALUE robj = Data_Wrap_Struct(cInputWriter, 0, delete_port, local_port);
    rb_iv_set(robj, "@port", port);
    return robj;
}

static VALUE do_output_port_reader(VALUE port, VALUE type_name, VALUE policy)
{
    CorbaAccess* corba = CorbaAccess::instance();

    // Get the port and create an anti-clone of it
    RTaskContext* task; VALUE port_name;
    tie(task, tuples::ignore, port_name) = getPortReference(port);
    RTT::TypeInfo* ti = get_type_info(StringValuePtr(type_name));

    std::string local_name = corba->getLocalPortName(port);
    RTT::PortInterface* local_port = ti->inputPort(local_name);

    // Register this port on our data flow interface, and call CORBA to connect
    // both ports
    corba->addPort(local_port);
    try {
        bool result = task->ports->createConnection(StringValuePtr(port_name),
                corba->getDataFlowInterface(), local_name.c_str(),
                policyFromHash(policy));
        if (!result)
        {
            corba->removePort(local_port);
            rb_raise(eConnectionFailed, "failed to connect specified ports");
        }
    }
    CORBA_EXCEPTION_HANDLERS

    // Finally, wrap the new port in a Ruby object
    VALUE robj = Data_Wrap_Struct(cOutputReader, 0, delete_port, local_port);
    rb_iv_set(robj, "@port", port);
    return robj;
}

// call-seq:
//  task.attribute(name) => attribute
//
// Returns the Attribute object which represents the remote task's
// Attribute or Property of the given name. There is no difference on the CORBA
// side (and honestly I don't know the difference on the C++ side either).
///
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
    rb_iv_set(obj, "@task", self);
    rb_iv_set(obj, "@type_name", type_name);
    rb_funcall(obj, rb_intern("initialize"), 0);
    return obj;
}

// call-seq:
//  task.each_attribute { |a| ... } => task
//
// Enumerates the attributes and properties that are available on
// this task, as instances of Orocos::Attribute
///
static VALUE task_context_each_attribute(VALUE self)
{
    RTaskContext& context = get_wrapped<RTaskContext>(self);

    try
    {
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
    CORBA_EXCEPTION_HANDLERS
}

// call-seq:
//  task.state => value
//
// Returns the state of the task, as an integer value. The possible values are
// represented by the various +STATE_+ constants:
// 
//   STATE_PRE_OPERATIONAL
//   STATE_STOPPED
//   STATE_ACTIVE
//   STATE_RUNNING
//   STATE_RUNTIME_WARNING
//   STATE_RUNTIME_ERROR
//   STATE_FATAL_ERROR
//
// See Orocos own documentation for their meaning
///
static VALUE task_context_state(VALUE task)
{
    RTaskContext& context = get_wrapped<RTaskContext>(task);
    try { return INT2FIX(context.task->getTaskState()); }
    CORBA_EXCEPTION_HANDLERS
}

// Do the transition between STATE_PRE_OPERATIONAL and STATE_STOPPED
static VALUE task_context_configure(VALUE task)
{
    RTaskContext& context = get_wrapped<RTaskContext>(task);
    try
    {
        if (!context.task->configure())
            rb_raise(eStateTransitionFailed, "failed to configure");
        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

// Do the transition between STATE_STOPPED and STATE_RUNNING
static VALUE task_context_start(VALUE task)
{
    RTaskContext& context = get_wrapped<RTaskContext>(task);
    try
    {
        if (!context.task->start())
            rb_raise(eStateTransitionFailed, "failed to start");
        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

// Do the transition between STATE_RUNNING and STATE_STOPPED
static VALUE task_context_stop(VALUE task)
{
    RTaskContext& context = get_wrapped<RTaskContext>(task);
    try
    { return context.task->stop() ? Qtrue : Qfalse; }
    CORBA_EXCEPTION_HANDLERS
}

// Do the transition between STATE_STOPPED and STATE_PRE_OPERATIONAL
static VALUE task_context_cleanup(VALUE task)
{
    RTaskContext& context = get_wrapped<RTaskContext>(task);
    try
    { return context.task->cleanup() ? Qtrue : Qfalse; }
    CORBA_EXCEPTION_HANDLERS
}

/* call-seq:
 *  port.connected? => true or false
 *
 * Tests if this port is already part of a connection or not
 */
static VALUE port_connected_p(VALUE self)
{
    RTaskContext* task; VALUE name;
    tie(task, tuples::ignore, name) = getPortReference(self);

    try
    { return task->ports->isConnected(StringValuePtr(name)) ? Qtrue : Qfalse; }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); } // is refined on the Ruby side
    CORBA_EXCEPTION_HANDLERS
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
    RTaskContext* out_task; VALUE out_name;
    tie(out_task, tuples::ignore, out_name) = getPortReference(routput_port);
    RTaskContext* in_task; VALUE in_name;
    tie(in_task, tuples::ignore, in_name) = getPortReference(rinput_port);

    RTT::Corba::ConnPolicy policy = policyFromHash(options);

    try
    {
        if (!out_task->ports->createConnection(StringValuePtr(out_name),
                in_task->ports, StringValuePtr(in_name),
                policy))
            rb_raise(eConnectionFailed, "failed to connect ports");
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); } // should be refined on the Ruby side
    CORBA_EXCEPTION_HANDLERS
    return Qnil; // never reached
}

static VALUE do_port_disconnect_all(VALUE port)
{
    RTaskContext* task; VALUE name;
    tie(task, tuples::ignore, name) = getPortReference(port);

    try
    {
        task->ports->disconnect(StringValuePtr(name));
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    CORBA_EXCEPTION_HANDLERS
    return Qnil; // never reached
}

static VALUE do_port_disconnect_from(VALUE self, VALUE other)
{
    RTaskContext* self_task; VALUE self_name;
    tie(self_task, tuples::ignore, self_name) = getPortReference(self);
    RTaskContext* other_task; VALUE other_name;
    tie(other_task, tuples::ignore, other_name) = getPortReference(other);

    try
    {
        self_task->ports->disconnectPort(StringValuePtr(self_name), other_task->ports, StringValuePtr(other_name));
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    CORBA_EXCEPTION_HANDLERS
    return Qnil; // never reached
}

static VALUE do_output_reader_read(VALUE port_access, VALUE type_name, VALUE rb_typelib_value)
{
    RTT::InputPortInterface& local_port = get_wrapped<RTT::InputPortInterface>(port_access);
    Typelib::Value value = typelib_get(rb_typelib_value);
    RTT::TypeInfo* ti = get_type_info(StringValuePtr(type_name));

    RTT::DataSourceBase::shared_ptr ds =
        ti->buildReference(value.getData());
    return local_port.read(ds) ? Qtrue : Qfalse;
}
static VALUE output_reader_clear(VALUE port_access)
{
    RTT::InputPortInterface& local_port = get_wrapped<RTT::InputPortInterface>(port_access);
    local_port.clear();
    return Qnil;
}

static VALUE do_input_writer_write(VALUE port_access, VALUE type_name, VALUE rb_typelib_value)
{
    RTT::OutputPortInterface& local_port = get_wrapped<RTT::OutputPortInterface>(port_access);
    Typelib::Value value = typelib_get(rb_typelib_value);
    RTT::TypeInfo* ti = get_type_info(StringValuePtr(type_name));

    RTT::DataSourceBase::shared_ptr ds =
        ti->buildReference(value.getData());

    local_port.write(ds);
    return local_port.connected() ? Qtrue : Qfalse;
}

static VALUE do_local_port_disconnect(VALUE port_access)
{
    RTT::PortInterface& local_port = get_wrapped<RTT::PortInterface>(port_access);
    local_port.disconnect();
    return Qnil;
}

static VALUE do_local_port_connected(VALUE port_access)
{
    RTT::PortInterface& local_port = get_wrapped<RTT::PortInterface>(port_access);
    return local_port.connected() ? Qtrue : Qfalse;
}

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
namespace RTT
{
    namespace Corba
    {
        extern int loadCorbaLib();
    }
}

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
    
    cPort         = rb_define_class_under(mOrocos, "Port", rb_cObject);
    cOutputPort   = rb_define_class_under(mOrocos, "OutputPort", cPort);
    cInputPort    = rb_define_class_under(mOrocos, "InputPort", cPort);
    cPortAccess   = rb_define_class_under(mOrocos, "PortAccess", rb_cObject);
    cOutputReader = rb_define_class_under(mOrocos, "OutputReader", cPortAccess);
    cInputWriter  = rb_define_class_under(mOrocos, "InputWriter", cPortAccess);
    cAttribute    = rb_define_class_under(mOrocos, "Attribute", rb_cObject);
    eNotFound     = rb_define_class_under(mOrocos, "NotFound", rb_eRuntimeError);
    eStateTransitionFailed = rb_define_class_under(mOrocos, "StateTransitionFailed", rb_eRuntimeError);
    eConnectionFailed = rb_define_class_under(mOrocos, "ConnectionFailed", rb_eRuntimeError);

    rb_define_singleton_method(mOrocos, "task_names", RUBY_METHOD_FUNC(orocos_task_names), 0);
    rb_define_singleton_method(cTaskContext, "do_get", RUBY_METHOD_FUNC(task_context_get), 1);
    rb_define_method(cTaskContext, "==", RUBY_METHOD_FUNC(task_context_equal_p), 1);
    rb_define_method(cTaskContext, "do_state", RUBY_METHOD_FUNC(task_context_state), 0);
    rb_define_method(cTaskContext, "do_configure", RUBY_METHOD_FUNC(task_context_configure), 0);
    rb_define_method(cTaskContext, "do_start", RUBY_METHOD_FUNC(task_context_start), 0);
    rb_define_method(cTaskContext, "do_stop", RUBY_METHOD_FUNC(task_context_stop), 0);
    rb_define_method(cTaskContext, "do_cleanup", RUBY_METHOD_FUNC(task_context_cleanup), 0);
    rb_define_method(cTaskContext, "do_has_port?", RUBY_METHOD_FUNC(task_context_has_port_p), 1);
    rb_define_method(cTaskContext, "do_port", RUBY_METHOD_FUNC(task_context_do_port), 1);
    rb_define_method(cTaskContext, "do_each_port", RUBY_METHOD_FUNC(task_context_each_port), 0);
    rb_define_method(cTaskContext, "do_attribute", RUBY_METHOD_FUNC(task_context_attribute), 1);
    rb_define_method(cTaskContext, "do_each_attribute", RUBY_METHOD_FUNC(task_context_each_attribute), 0);

    rb_define_method(cPort, "connected?", RUBY_METHOD_FUNC(port_connected_p), 0);
    rb_define_method(cPort, "do_disconnect_from", RUBY_METHOD_FUNC(do_port_disconnect_from), 1);
    rb_define_method(cPort, "do_disconnect_all", RUBY_METHOD_FUNC(do_port_disconnect_all), 0);
    rb_define_method(cOutputPort, "do_connect_to", RUBY_METHOD_FUNC(do_port_connect_to), 2);
    rb_define_method(cOutputPort, "do_reader", RUBY_METHOD_FUNC(do_output_port_reader), 2);
    rb_define_method(cInputPort, "do_writer", RUBY_METHOD_FUNC(do_input_port_writer), 2);

    rb_define_method(cPortAccess, "disconnect", RUBY_METHOD_FUNC(do_local_port_disconnect), 0);
    rb_define_method(cPortAccess, "connected?", RUBY_METHOD_FUNC(do_local_port_connected), 0);
    rb_define_method(cOutputReader, "do_read", RUBY_METHOD_FUNC(do_output_reader_read), 2);
    rb_define_method(cOutputReader, "clear", RUBY_METHOD_FUNC(output_reader_clear), 0);
    rb_define_method(cInputWriter, "do_write", RUBY_METHOD_FUNC(do_input_writer_write), 2);

    // load the default toolkit and the CORBA transport
    RTT::Toolkit::Import(RTT::RealTimeToolkit);
    loadCorbaLib();

    Orocos_init_CORBA();
    Orocos_init_data_handling();
    Orocos_init_methods();
}

