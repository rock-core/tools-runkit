#include "rorocos.hh"
#include "datahandling.hh"
#include <rtt/types/Types.hpp>
#include <rtt/types/TypeTransporter.hpp>
#include <rtt/base/PortInterface.hpp>
#include <rtt/transports/corba/CorbaLib.hpp>

using namespace RTT;
using namespace RTT::base;
using namespace RTT::types;
using namespace RTT::corba;

// Unmarshals the data that is included in the given any into the memory held in
// +dest+. +dest+ must be holding a memory zone that is valid to hold a value of
// the given type (i.e. either directly of type type_name, or if type_name is
// opaque, to the type used to represent this particular opaque)
VALUE corba_to_ruby(std::string const& type_name, Typelib::Value dest, CORBA::Any& src)
{
    // First, get both the CORBA and typelib transports
    TypeInfo* ti = get_type_info(type_name);
    RTT::corba::CorbaTypeTransporter* corba_transport = get_corba_transport(ti, false);
    if (! corba_transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());
    orogen_transports::TypelibMarshallerBase* typelib_transport = get_typelib_transport(ti, false);

    // Fall back to normal typelib behaviour if there is not typelib transport.
    // Do it for plain types as well, as it requires less operations
    if (!typelib_transport || typelib_transport->isPlainTypelibType())
    {
        RTT::base::DataSourceBase::shared_ptr ds =
            ti->buildReference(dest.getData());
        if (!corba_transport->updateFromAny(&src, ds))
            rb_raise(eCORBA, "failed to unmarshal %s", type_name.c_str());
    }
    else
    {
        orogen_transports::TypelibMarshallerBase::Handle* handle = typelib_transport->createHandle();
        // Set the typelib sample but don't copy it to the orocos sample as we
        // will copy back anyway
        typelib_transport->setTypelibSample(handle, dest, false);
        RTT::base::DataSourceBase::shared_ptr ds =
            typelib_transport->getDataSource(handle);
        if (!corba_transport->updateFromAny(&src, ds))
            rb_raise(eCORBA, "failed to unmarshal %s", type_name.c_str());
        typelib_transport->refreshTypelibSample(handle);

        Typelib::copy(dest, Typelib::Value(typelib_transport->getTypelibSample(handle), dest.getType()));
        typelib_transport->deleteHandle(handle);
    }

    return Qnil;
}

// Marshals the data that is held by +src+ into a CORBA::Any
CORBA::Any* ruby_to_corba(std::string const& type_name, Typelib::Value src)
{
    TypeInfo* ti = get_type_info(type_name);
    RTT::corba::CorbaTypeTransporter* corba_transport = get_corba_transport(ti, false);
    if (! corba_transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());
    orogen_transports::TypelibMarshallerBase* typelib_transport = get_typelib_transport(ti, false);

    CORBA::Any* result;
    if (!typelib_transport || typelib_transport->isPlainTypelibType())
    {
        DataSourceBase::shared_ptr data_source = ti->buildReference(src.getData());
        result = corba_transport->createAny(data_source);
        if (! result)
            rb_raise(eCORBA, "failed to marshal %s", type_name.c_str());
    }
    else
    {
        orogen_transports::TypelibMarshallerBase::Handle* handle = typelib_transport->createHandle();
        try { typelib_transport->setTypelibSample(handle, src); }
        catch(std::exception& e)
        {
            rb_raise(eCORBA, "failed to marshal %s: %s", type_name.c_str(), e.what());
        }

        RTT::base::DataSourceBase::shared_ptr ds =
            typelib_transport->getDataSource(handle);
        result = corba_transport->createAny(ds);
        typelib_transport->deleteHandle(handle);
    }

    return result;
}

static VALUE property_do_read_string(VALUE rbtask, VALUE property_name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    CORBA::Any_var corba_value = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::getProperty,
                                                                    (_objref_CConfigurationInterface*)task.main_service,
                                                                    StringValuePtr(property_name)));
    char const* result = 0;
    if (!(corba_value >>= result))
        rb_raise(rb_eArgError, "no such property");
    VALUE rb_result = rb_str_new2(result);
    return rb_result;
}

static VALUE property_do_read(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    CORBA::Any_var corba_value = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::getProperty,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name)));
    corba_to_ruby(StringValuePtr(type_name), value, corba_value);
    return rb_typelib_value;
}

static VALUE property_do_write_string(VALUE rbtask, VALUE property_name, VALUE rb_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    CORBA::Any_var corba_value = new CORBA::Any;
    corba_value <<= StringValuePtr(rb_value);
    bool result = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::setProperty,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name),corba_value));
    if(!result)
        rb_raise(rb_eArgError, "failed to write the property");
    return Qnil;
}

static VALUE property_do_write(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    CORBA::Any_var corba_value = ruby_to_corba(StringValuePtr(type_name), value);
    bool result = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::setProperty,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name),corba_value));
    if(!result)
        rb_raise(rb_eArgError, "failed to write the property");
    return Qnil;
}

static VALUE attribute_do_read_string(VALUE rbtask, VALUE property_name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    CORBA::Any_var corba_value = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::getAttribute,
                                                                    (_objref_CConfigurationInterface*)task.main_service,
                                                                    StringValuePtr(property_name)));
    char const* result = 0;
    if (!(corba_value >>= result))
        rb_raise(rb_eArgError, "no such attribute");
    VALUE rb_result = rb_str_new2(result);
    return rb_result;
}

static VALUE attribute_do_read(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    CORBA::Any_var corba_value = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::getAttribute,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name)));
    corba_to_ruby(StringValuePtr(type_name), value, corba_value);
    return rb_typelib_value;
}

static VALUE attribute_do_write_string(VALUE rbtask, VALUE property_name, VALUE rb_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    CORBA::Any_var corba_value = new CORBA::Any;
    corba_value <<= StringValuePtr(rb_value);
    bool result = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::setAttribute,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name),corba_value));
    if(!result)
        rb_raise(rb_eArgError, "failed to write the attribute");
    return Qnil;
}

static VALUE attribute_do_write(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    CORBA::Any_var corba_value = ruby_to_corba(StringValuePtr(type_name), value);
    bool result = corba_blocking_fct_call_with_result(boost::bind(&_objref_CConfigurationInterface::setAttribute,
                (_objref_CConfigurationInterface*)task.main_service,
                StringValuePtr(property_name),corba_value));
    if(!result)
        rb_raise(rb_eArgError, "failed to write the attribute");
    return Qnil;
}

void Orocos_init_data_handling(VALUE cTaskContext)
{
    rb_define_method(cTaskContext, "do_property_read_string",   RUBY_METHOD_FUNC(property_do_read_string),   1);
    rb_define_method(cTaskContext, "do_property_write_string",  RUBY_METHOD_FUNC(property_do_write_string),  2);
    rb_define_method(cTaskContext, "do_property_read",          RUBY_METHOD_FUNC(property_do_read),          3);
    rb_define_method(cTaskContext, "do_property_write",         RUBY_METHOD_FUNC(property_do_write),         3);
    rb_define_method(cTaskContext, "do_attribute_read_string",  RUBY_METHOD_FUNC(attribute_do_read_string),  1);
    rb_define_method(cTaskContext, "do_attribute_write_string", RUBY_METHOD_FUNC(attribute_do_write_string), 2);
    rb_define_method(cTaskContext, "do_attribute_read",         RUBY_METHOD_FUNC(attribute_do_read),         3);
    rb_define_method(cTaskContext, "do_attribute_write",        RUBY_METHOD_FUNC(attribute_do_write),        3);
}

