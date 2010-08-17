#include "rorocos.hh"
#include <memory>
#include <typeinfo>

using namespace std;
using namespace RTT::corba;

static VALUE cOperation;
static VALUE cSendHandle;

static CAnyArguments* init_corba_args(VALUE type_names, VALUE args)
{
    CAnyArguments_var corba_args = new CAnyArguments;
    corba_args->length(RARRAY_LEN(args));

    size_t len = RARRAY_LEN(args);
    VALUE* value_ptr = RARRAY_PTR(args);
    VALUE* types_ptr = RARRAY_PTR(type_names);
    for (size_t i = 0; i < len; ++i)
    {
        if (rb_obj_is_kind_of(value_ptr[i], rb_cString))
        {
            char const* string = StringValuePtr(value_ptr[i]);
            CORBA::Any_var arg_any = new CORBA::Any;
            arg_any <<= CORBA::string_dup(string);
            corba_args[i] = arg_any;
        }
        else
        {
            Typelib::Value v = typelib_get(value_ptr[i]);
            CORBA::Any_var arg_any = ruby_to_corba(
                    StringValuePtr(types_ptr[i]), v);
            corba_args[i] = arg_any;
        }

    }

    return corba_args._retn();
}

static VALUE operation_call(VALUE task_, VALUE name, VALUE result_type_name, VALUE args_type_names, VALUE args, VALUE result_)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    CAnyArguments_var corba_args = init_corba_args(args_type_names, args);

    try {
	CORBA::Any_var corba_result = task.main_service->callOperation(StringValuePtr(name), corba_args);

        if (RTEST(result_))
        {
            if (rb_obj_is_kind_of(result_, rb_cString))
            {
                char const* result_str;
                corba_result >>= result_str;
                return rb_str_new2(result_str);
            }
            else
            {
                Typelib::Value result = typelib_get(result_);
                corba_to_ruby(StringValuePtr(result_type_name), result, corba_result);
            }
        }
	return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS;
    return Qnil;
}

struct RSendHandle
{
    RSendHandle() {}
    RSendHandle(RTT::corba::CSendHandle_var handle)
	: handle(handle) {}

    RTT::corba::CSendHandle_var handle;
};

static VALUE operation_send(VALUE task_, VALUE name, VALUE args_type_names, VALUE args)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    CAnyArguments_var corba_args = init_corba_args(args_type_names, args);

    try {
	RTT::corba::CSendHandle_var corba_result = task.main_service->sendOperation(StringValuePtr(name), corba_args);
	return simple_wrap(cSendHandle, new RSendHandle(corba_result));
    }
    CORBA_EXCEPTION_HANDLERS;
    return Qnil;
}

static VALUE operation_signature(VALUE task_, VALUE opname)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);

    VALUE result = rb_ary_new();
    try
    {
        CORBA::String_var result_type =
            task.main_service->getResultType(StringValuePtr(opname));
        rb_ary_push(result, rb_str_new2(result_type));

        RTT::corba::CDescriptions_var args =
            task.main_service->getArguments(StringValuePtr(opname));

        for (int i = 0; i < args->length(); ++i)
        {
            RTT::corba::CArgumentDescription arg =
                args[i];
            VALUE tuple = rb_ary_new();
            rb_ary_push(tuple, rb_str_new2(arg.name));
            rb_ary_push(tuple, rb_str_new2(arg.description));
            rb_ary_push(tuple, rb_str_new2(arg.type));
            rb_ary_push(result, tuple);
        }
        return result;
    }
    catch(RTT::corba::CNoSuchNameException)
    { rb_raise(eNotFound, "there is not operation called %s", StringValuePtr(opname)); }
    CORBA_EXCEPTION_HANDLERS;
    return Qnil; // never reached
}

void Orocos_init_methods()
{
    VALUE mOrocos      = rb_define_module("Orocos");
    VALUE cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
    cOperation   = rb_define_class_under(mOrocos, "Operation",  rb_cObject);
    cSendHandle  = rb_define_class_under(mOrocos, "SendHandle", rb_cObject);

    rb_define_method(cTaskContext, "operation_signature", RUBY_METHOD_FUNC(operation_signature), 1);
    rb_define_method(cTaskContext, "do_operation_call", RUBY_METHOD_FUNC(operation_call), 5);
    rb_define_method(cTaskContext, "do_operation_send", RUBY_METHOD_FUNC(operation_send), 3);

    rb_const_set(cSendHandle, rb_intern("SEND_SUCCESS"),       INT2FIX(RTT::corba::CSendSuccess));
    rb_const_set(cSendHandle, rb_intern("SEND_NOT_READY"),     INT2FIX(RTT::corba::CSendNotReady));
    rb_const_set(cSendHandle, rb_intern("SEND_FAILURE"),       INT2FIX(RTT::corba::CSendFailure));
}

