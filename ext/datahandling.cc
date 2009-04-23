#include "rorocos.hh"
#include "datahandling.hh"
#include <rtt/Types.hpp>
#include <rtt/TypeTransporter.hpp>
#include <rtt/corba/CorbaLib.hpp>
#include <rtt/PortInterface.hpp>

using namespace RTT;

// Unmarshals the data that is included in the given any into the memory held in
// +dest+. +dest+ must be holding a memory zone that is valid to hold a value of
// the given type.
VALUE corba_to_ruby(std::string const& type_name, Typelib::Value dest, CORBA::Any& src)
{
    TypeInfo* ti = get_type_info(type_name);
    detail::TypeTransporter* transport = ti->getProtocol(ORO_CORBA_PROTOCOL_ID);
    if (! transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());

    DataSourceBase::shared_ptr data_source = ti->buildReference(dest.getData());
    if (!transport->updateBlob(&src, data_source))
        rb_raise(eCORBA, "failed to unmarshal %s", type_name.c_str());

    return Qnil;
}

// Marshals the data that is held by +src+ into a CORBA::Any
CORBA::Any* ruby_to_corba(std::string const& type_name, Typelib::Value src)
{
    TypeInfo* ti = get_type_info(type_name);
    detail::TypeTransporter* transport = ti->getProtocol(ORO_CORBA_PROTOCOL_ID);
    if (! transport)
        rb_raise(rb_eArgError, "trying to unmarshal %s, but it is not supported by the CORBA transport", type_name.c_str());

    DataSourceBase::shared_ptr data_source = ti->buildReference(src.getData());
    CORBA::Any* result = static_cast<CORBA::Any*>(transport->createBlob(data_source));
    if (! result)
        rb_raise(eCORBA, "failed to marshal %s", type_name.c_str());

    return result;
}

static VALUE attribute_do_read(VALUE attr, VALUE type_name, VALUE rb_typelib_value)
{
    RAttribute& attribute = get_wrapped<RAttribute>(attr);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = attribute.expr->get();
        corba_to_ruby(StringValuePtr(type_name), value, corba_value);
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE attribute_do_write(VALUE attr, VALUE type_name, VALUE rb_typelib_value)
{
    RAttribute& attribute = get_wrapped<RAttribute>(attr);
    Typelib::Value value = typelib_get(rb_typelib_value);

    try {
        CORBA::Any_var corba_value = ruby_to_corba(StringValuePtr(type_name), value);
        RTT::Corba::AssignableExpression_var corba_writer =
            RTT::Corba::AssignableExpression::_narrow(attribute.expr);
        corba_writer->set(corba_value);
        return Qnil;
    }
    catch(RTT::Corba::NoSuchPortException&) { rb_raise(eNotFound, ""); }
    CORBA_EXCEPTION_HANDLERS
}

void Orocos_init_data_handling()
{
    // Unfortunately, we must redefine this here to make RDoc happy
    VALUE mOrocos    = rb_define_module("Orocos");
    VALUE mCORBA     = rb_define_module_under(mOrocos, "CORBA");
    VALUE cAttribute = rb_define_class_under(mOrocos, "Attribute", rb_cObject);

    rb_define_method(cAttribute, "do_read", RUBY_METHOD_FUNC(attribute_do_read), 2);
    rb_define_method(cAttribute, "do_write", RUBY_METHOD_FUNC(attribute_do_write), 2);
}

