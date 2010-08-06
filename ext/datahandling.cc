#include "rorocos.hh"
#include "datahandling.hh"
#include <rtt/types/Types.hpp>
#include <rtt/types/TypeTransporter.hpp>
#include <rtt/base/PortInterface.hpp>
#include <rtt/transports/corba/CorbaLib.hpp>
#include <rtt/transports/corba/CorbaTypeTransporter.hpp>

using namespace RTT;
using namespace RTT::base;
using namespace RTT::types;

// Unmarshals the data that is included in the given any into the memory held in
// +dest+. +dest+ must be holding a memory zone that is valid to hold a value of
// the given type.
VALUE corba_to_ruby(std::string const& type_name, Typelib::Value dest, CORBA::Any& src)
{
    TypeInfo* ti = get_type_info(type_name);
    RTT::corba::CorbaTypeTransporter* transport =
        dynamic_cast<RTT::corba::CorbaTypeTransporter*>(ti->getProtocol(ORO_CORBA_PROTOCOL_ID));
    if (! transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());

    DataSourceBase::shared_ptr data_source = ti->buildReference(dest.getData());
    if (!transport->updateAny(data_source, src))
        rb_raise(eCORBA, "failed to unmarshal %s", type_name.c_str());

    return Qnil;
}

// Marshals the data that is held by +src+ into a CORBA::Any
CORBA::Any* ruby_to_corba(std::string const& type_name, Typelib::Value src)
{
    TypeInfo* ti = get_type_info(type_name);
    RTT::corba::CorbaTypeTransporter* transport =
        dynamic_cast<RTT::corba::CorbaTypeTransporter*>(ti->getProtocol(ORO_CORBA_PROTOCOL_ID));
    if (! transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());

    DataSourceBase::shared_ptr data_source = ti->buildReference(src.getData());
    CORBA::Any* result = transport->createAny(data_source);
    if (! result)
        rb_raise(eCORBA, "failed to marshal %s", type_name.c_str());

    return result;
}

static VALUE property_do_read_string(VALUE rbtask, VALUE property_name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    try {
        CORBA::Any_var corba_value = task.main_service->getProperty(StringValuePtr(property_name));
        char const* result = 0;
        if (!(corba_value >>= result))
            rb_raise(rb_eArgError, "no such property");
        VALUE rb_result = rb_str_new2(result);
        return rb_result;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE property_do_read(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = task.main_service->getProperty(StringValuePtr(property_name));
        corba_to_ruby(StringValuePtr(type_name), value, corba_value);
        return rb_typelib_value;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE property_do_write_string(VALUE rbtask, VALUE property_name, VALUE rb_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    try {
        CORBA::Any_var corba_value = new CORBA::Any;
        corba_value <<= StringValuePtr(rb_value);
        if (!task.main_service->setProperty(StringValuePtr(property_name), corba_value))
            rb_raise(rb_eArgError, "failed to write the property");

        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE property_do_write(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = ruby_to_corba(StringValuePtr(type_name), value);
        if (!task.main_service->setProperty(StringValuePtr(property_name), corba_value))
            rb_raise(rb_eArgError, "failed to write the property");
        return Qnil;
    }
    catch(RTT::corba::CNoSuchPortException&) { rb_raise(eNotFound, "no such port"); }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE attribute_do_read_string(VALUE rbtask, VALUE property_name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    try {
        CORBA::Any_var corba_value = task.main_service->getAttribute(StringValuePtr(property_name));
        char const* result = 0;
        if (!(corba_value >>= result))
            rb_raise(rb_eArgError, "no such attribute");
        VALUE rb_result = rb_str_new2(result);
        return rb_result;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE attribute_do_read(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = task.main_service->getAttribute(StringValuePtr(property_name));
        corba_to_ruby(StringValuePtr(type_name), value, corba_value);
        return rb_typelib_value;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE attribute_do_write_string(VALUE rbtask, VALUE property_name, VALUE rb_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);

    try {
        CORBA::Any_var corba_value = new CORBA::Any;
        corba_value <<= StringValuePtr(rb_value);
        if (!task.main_service->setAttribute(StringValuePtr(property_name), corba_value))
            rb_raise(rb_eArgError, "failed to write the property");

        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE attribute_do_write(VALUE rbtask, VALUE property_name, VALUE type_name, VALUE rb_typelib_value)
{
    RTaskContext& task = get_wrapped<RTaskContext>(rbtask);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = ruby_to_corba(StringValuePtr(type_name), value);
        if (!task.main_service->setAttribute(StringValuePtr(property_name), corba_value))
            rb_raise(rb_eArgError, "failed to write the property");
        return Qnil;
    }
    catch(RTT::corba::CNoSuchPortException&) { rb_raise(eNotFound, "no such port"); }
    CORBA_EXCEPTION_HANDLERS
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

