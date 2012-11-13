#include "rorocos.hh"

#include <rtt/types/Types.hpp>
#include <rtt/types/TypekitPlugin.hpp>
#include <rtt/types/TypekitRepository.hpp>
#include <rtt/base/PortInterface.hpp>
#include <rtt/transports/corba/TransportPlugin.hpp>

#include <rtt/base/OutputPortInterface.hpp>
#include <rtt/base/InputPortInterface.hpp>

#include <typelib_ruby.hh>
#include <rtt/transports/corba/CorbaLib.hpp>

#include <rtt/TaskContext.hpp>
#include <rtt/transports/corba/TaskContextServer.hpp>
#include <rtt/transports/corba/CorbaDispatcher.hpp>

static VALUE cRubyTaskContext;
static VALUE cLocalTaskContext;
static VALUE cLocalOutputPort;
static VALUE cLocalInputPort;

class LocalTaskContext : public RTT::TaskContext
{
public:
    LocalTaskContext(std::string const& name)
        : RTT::TaskContext(name) {}
};

LocalTaskContext& local_task_context(VALUE obj)
{
    return get_wrapped<LocalTaskContext>(obj);
}

static void delete_local_task_context(LocalTaskContext* task)
{
    RTT::corba::TaskContextServer::CleanupServer(task);

    // Ruby GC does not give any guarantee about the ordering of garbage
    // collection. Reset the dataflowinterface to NULL on all ports so that
    // delete_rtt_ruby_port does not try to access task->ports() while it is
    // deleted
    RTT::DataFlowInterface::Ports ports = task->ports()->getPorts();
    for (RTT::DataFlowInterface::Ports::const_iterator it = ports.begin();
            it != ports.end(); ++it)
    {
        (*it)->setInterface(0);
    }
    delete task;
}

static VALUE local_task_context_new(VALUE klass, VALUE _name)
{
    std::string name = StringValuePtr(_name);
    LocalTaskContext* ruby_task = new LocalTaskContext(name);
    RTT::corba::CorbaDispatcher::Instance(ruby_task->ports(), ORO_SCHED_OTHER, RTT::os::LowestPriority);

    RTT::corba::TaskContextServer::Create(ruby_task);

    VALUE rlocal_task = Data_Wrap_Struct(cLocalTaskContext, 0, delete_local_task_context, ruby_task);
    rb_obj_call_init(rlocal_task, 1, &_name);
    return rlocal_task;
}

static VALUE local_task_context_dispose(VALUE obj)
{
    RTT::corba::TaskContextServer::CleanupServer(&get_wrapped<LocalTaskContext>(obj));
    return Qnil;
}

static VALUE local_task_context_ior(VALUE _task)
{
    LocalTaskContext& task = local_task_context(_task);
    std::string ior = RTT::corba::TaskContextServer::getIOR(&task);
    return rb_str_new(ior.c_str(), ior.length());
}

static void delete_rtt_ruby_port(RTT::base::PortInterface* port)
{
    if (port->getInterface())
        port->getInterface()->removePort(port->getName());
    delete port;
}

/** call-seq:
 *     do_create_port(klass, port_name, orocos_type_name)
 *
 */
static VALUE local_task_context_create_port(VALUE _task, VALUE _is_output, VALUE _klass, VALUE _port_name, VALUE _type_name)
{
    std::string port_name = StringValuePtr(_port_name);
    std::string type_name = StringValuePtr(_type_name);
    RTT::types::TypeInfo* ti = get_type_info(type_name);
    if (!ti)
        rb_raise(rb_eArgError, "type %s is not registered on the RTT type system", type_name.c_str());

    RTT::base::PortInterface* port;
    VALUE ruby_port;
    if (RTEST(_is_output))
        port = ti->outputPort(port_name);
    else
        port = ti->inputPort(port_name);

    ruby_port = Data_Wrap_Struct(_klass, 0, delete_rtt_ruby_port, port);
    local_task_context(_task).ports()->addPort(*port);

    VALUE args[4] = { rb_iv_get(_task, "@remote_task"), _port_name, _type_name, Qnil };
    rb_obj_call_init(ruby_port, 4, args);
    return ruby_port;
}

static VALUE local_task_context_remove_port(VALUE obj, VALUE _port_name)
{
    std::string port_name = StringValuePtr(_port_name);
    local_task_context(obj).ports()->removePort(port_name);
    return Qnil;
}

static VALUE local_input_port_read(VALUE _local_port, VALUE type_name, VALUE rb_typelib_value, VALUE copy_old_data)
{
    RTT::base::InputPortInterface& local_port = get_wrapped<RTT::base::InputPortInterface>(_local_port);
    Typelib::Value value = typelib_get(rb_typelib_value);

    RTT::types::TypeInfo* ti = get_type_info(StringValuePtr(type_name));
    orogen_transports::TypelibMarshallerBase* typelib_transport =
        get_typelib_transport(ti, false);

    if (!typelib_transport || typelib_transport->isPlainTypelibType())
    {
        RTT::base::DataSourceBase::shared_ptr ds =
            ti->buildReference(value.getData());
        switch(local_port.read(ds))
        {
            case RTT::NoData:  return Qfalse;
            case RTT::OldData: return INT2FIX(0);
            case RTT::NewData: return INT2FIX(1);
        }
    }
    else
    {
        orogen_transports::TypelibMarshallerBase::Handle* handle =
            typelib_transport->createHandle();
        // Set the typelib sample using the value passed from ruby to avoid
        // unnecessary convertions. Don't touch the orocos sample though.
        typelib_transport->setTypelibSample(handle, value, false);
        RTT::base::DataSourceBase::shared_ptr ds =
            typelib_transport->getDataSource(handle);
        RTT::FlowStatus did_read = local_port.read(ds, RTEST(copy_old_data));

        if (did_read == RTT::NewData || (did_read == RTT::OldData && RTEST(copy_old_data)))
        {
            typelib_transport->refreshTypelibSample(handle);
            Typelib::copy(value, Typelib::Value(typelib_transport->getTypelibSample(handle), value.getType()));
        }

        typelib_transport->deleteHandle(handle);
        switch(did_read)
        {
            case RTT::NoData:  return Qfalse;
            case RTT::OldData: return INT2FIX(0);
            case RTT::NewData: return INT2FIX(1);
        }
    }
    return Qnil; // Never reached
}
static VALUE local_input_port_clear(VALUE _local_port)
{
    RTT::base::InputPortInterface& local_port = get_wrapped<RTT::base::InputPortInterface>(_local_port);
    local_port.clear();
    return Qnil;
}

static VALUE local_output_port_write(VALUE _local_port, VALUE type_name, VALUE rb_typelib_value)
{
    RTT::base::OutputPortInterface& local_port = get_wrapped<RTT::base::OutputPortInterface>(_local_port);
    Typelib::Value value = typelib_get(rb_typelib_value);

    orogen_transports::TypelibMarshallerBase* transport = 0;
    RTT::types::TypeInfo* ti = get_type_info(StringValuePtr(type_name));
    if (ti && ti->hasProtocol(orogen_transports::TYPELIB_MARSHALLER_ID))
    {
        transport =
            dynamic_cast<orogen_transports::TypelibMarshallerBase*>(ti->getProtocol(orogen_transports::TYPELIB_MARSHALLER_ID));
    }

    if (!transport)
    {
        RTT::base::DataSourceBase::shared_ptr ds =
            ti->buildReference(value.getData());

        local_port.write(ds);
    }
    else
    {
        orogen_transports::TypelibMarshallerBase::Handle* handle =
            transport->createSample();

        transport->setTypelibSample(handle, static_cast<uint8_t*>(value.getData()));
        RTT::base::DataSourceBase::shared_ptr ds =
            transport->getDataSource(handle);
        local_port.write(ds);
        transport->deleteHandle(handle);
    }
    return local_port.connected() ? Qtrue : Qfalse;
}

void Orocos_init_ruby_task_context(VALUE mOrocos, VALUE cTaskContext, VALUE cOutputPort, VALUE cInputPort)
{
    cRubyTaskContext = rb_define_class_under(mOrocos, "RubyTaskContext", cTaskContext);
    cLocalTaskContext = rb_define_class_under(cRubyTaskContext, "LocalTaskContext", rb_cObject);
    rb_define_singleton_method(cLocalTaskContext, "new", RUBY_METHOD_FUNC(local_task_context_new), 1);
    rb_define_method(cLocalTaskContext, "dispose", RUBY_METHOD_FUNC(local_task_context_dispose), 0);
    rb_define_method(cLocalTaskContext, "ior", RUBY_METHOD_FUNC(local_task_context_ior), 0);
    rb_define_method(cLocalTaskContext, "do_create_port", RUBY_METHOD_FUNC(local_task_context_create_port), 4);
    rb_define_method(cLocalTaskContext, "do_remove_port", RUBY_METHOD_FUNC(local_task_context_remove_port), 1);

    cLocalOutputPort = rb_define_class_under(mOrocos, "LocalOutputPort", cOutputPort);
    rb_define_method(cLocalOutputPort, "do_write", RUBY_METHOD_FUNC(local_output_port_write), 2);
    cLocalInputPort = rb_define_class_under(mOrocos, "LocalInputPort", cInputPort);
    rb_define_method(cLocalInputPort, "do_read", RUBY_METHOD_FUNC(local_input_port_read), 3);
    rb_define_method(cLocalInputPort, "do_clear", RUBY_METHOD_FUNC(local_input_port_clear), 0);
}

