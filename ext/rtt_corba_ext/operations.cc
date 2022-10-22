#include "corba.hh"
#include "rtt-corba.hh"
#include <memory>
#include <typeinfo>
#include <typelib_ruby.hh>

using namespace std;
using namespace RTT::corba;

static VALUE cSendHandle;

static void corba_args_to_ruby(VALUE type_names, VALUE result, CAnyArguments& args)
{
    size_t len = RARRAY_LEN(result);
    VALUE* value_ptr = RARRAY_PTR(result);
    VALUE* types_ptr = RARRAY_PTR(type_names);

    if (len != args.length())
        rb_raise(rb_eArgError,
            "size mismatch in demarshalling of returned values (internal error), got %i "
            "elements but the CORBA array has %i",
            static_cast<int>(len),
            static_cast<int>(args.length()));

    for (size_t i = 0; i < len; ++i) {
        if (rb_obj_is_kind_of(value_ptr[i], rb_cString)) {
            char const* string;
            (args[i]) >>= string;
            rb_str_cat2(value_ptr[i], string);
        }
        else {
            Typelib::Value v = typelib_get(value_ptr[i]);
            corba_to_ruby(StringValuePtr(types_ptr[i]), v, args[i]);
        }
    }
}

static CAnyArguments* corba_args_from_ruby(VALUE type_names, VALUE args)
{
    CAnyArguments_var corba_args = new CAnyArguments;
    corba_args->length(RARRAY_LEN(args));

    size_t len = RARRAY_LEN(args);
    VALUE* value_ptr = RARRAY_PTR(args);
    VALUE* types_ptr = RARRAY_PTR(type_names);
    for (size_t i = 0; i < len; ++i) {
        if (rb_obj_is_kind_of(value_ptr[i], rb_cString)) {
            char const* string = StringValuePtr(value_ptr[i]);
            CORBA::Any_var arg_any = new CORBA::Any;
            arg_any <<= CORBA::string_dup(string);
            corba_args[i] = arg_any;
        }
        else {
            Typelib::Value v = typelib_get(value_ptr[i]);
            CORBA::Any_var arg_any = ruby_to_corba(StringValuePtr(types_ptr[i]), v);
            corba_args[i] = arg_any;
        }
    }

    return corba_args._retn();
}

static VALUE operation_call(VALUE task_,
    VALUE name,
    VALUE result_type_name,
    VALUE result,
    VALUE args_type_names,
    VALUE args)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    CAnyArguments_var corba_args = corba_args_from_ruby(args_type_names, args);

    CORBA::Any_var corba_result = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::callOperation,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(name),
            corba_args));

    if (!NIL_P(result)) {
        Typelib::Value v = typelib_get(result);
        corba_to_ruby(StringValuePtr(result_type_name), v, corba_result);
    }
    corba_args_to_ruby(args_type_names, args, corba_args);
    return result;
}

struct RSendHandle {
    RSendHandle()
    {
    }
    RSendHandle(RTT::corba::CSendHandle_var handle)
        : handle(handle)
    {
    }

    ~RSendHandle()
    {
        if (!CORBA::is_nil(handle)) {
            try {
                handle->dispose();
            }
            catch (...) {
            }
        }
    }

    RTT::corba::CSendHandle_var handle;
};

static VALUE operation_send(VALUE task_, VALUE name, VALUE args_type_names, VALUE args)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    CAnyArguments_var corba_args = corba_args_from_ruby(args_type_names, args);

    RTT::corba::CSendHandle_var corba_result = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::sendOperation,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(name),
            corba_args));
    return simple_wrap(cSendHandle, new RSendHandle(corba_result));
}

static VALUE send_handle_collect_if_done(VALUE handle_,
    VALUE result_type_names,
    VALUE results)
{
    RSendHandle& handle = get_wrapped<RSendHandle>(handle_);
    CAnyArguments_var corba_result = new CAnyArguments;

    CSendStatus ss = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_CSendHandle::collectIfDone,
            (CSendHandle_ptr)handle.handle,
            (CAnyArguments_out)corba_result));
    if (ss == RTT::corba::CSendSuccess)
        corba_args_to_ruby(result_type_names, results, corba_result);
    return INT2FIX(ss);
}

static VALUE send_handle_collect(VALUE handle_, VALUE result_type_names, VALUE results)
{
    RSendHandle& handle = get_wrapped<RSendHandle>(handle_);
    CAnyArguments_var corba_result = new CAnyArguments;

    CSendStatus ss =
        corba_blocking_fct_call_with_result(boost::bind(&_objref_CSendHandle::collect,
            (CSendHandle_ptr)handle.handle,
            (CAnyArguments_out)corba_result));
    if (ss == RTT::corba::CSendSuccess)
        corba_args_to_ruby(result_type_names, results, corba_result);
    return INT2FIX(ss);
}

static VALUE operation_return_types(VALUE task_, VALUE opname)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);

    VALUE result = rb_ary_new();
    int retcount = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::getCollectArity,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(opname)));

    CORBA::String_var type_name = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::getResultType,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(opname)));
    rb_ary_push(result, rb_str_new2(type_name));

    for (int i = 0; i < retcount - 1; ++i) {
        type_name = corba_blocking_fct_call_with_result(
            boost::bind(&_objref_COperationInterface::getCollectType,
                (_objref_COperationInterface*)task.main_service,
                StringValuePtr(opname),
                i + 1));
        rb_ary_push(result, rb_str_new2(type_name));
    }
    return result;
}

static VALUE operation_argument_types(VALUE task_, VALUE opname)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);

    VALUE result = rb_ary_new();

#if RTT_VERSION_GTE(2, 8, 99)
    RTT::corba::CArgumentDescriptions_var args = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::getArguments,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(opname)));
#else
    RTT::corba::CDescriptions_var args = corba_blocking_fct_call_with_result(
        boost::bind(&_objref_COperationInterface::getArguments,
            (_objref_COperationInterface*)task.main_service,
            StringValuePtr(opname)));
#endif

    for (unsigned int i = 0; i < args->length(); ++i) {
        RTT::corba::CArgumentDescription arg = args[i];
        VALUE tuple = rb_ary_new();
        rb_ary_push(tuple, rb_str_new2(arg.name));
        rb_ary_push(tuple, rb_str_new2(arg.description));
        rb_ary_push(tuple, rb_str_new2(arg.type));
        rb_ary_push(result, tuple);
    }
    return result;
    return Qnil; // never reached
}

void rtt_corba_init_operations(VALUE mRoot, VALUE cTaskContext)
{
    VALUE cOperation = rb_define_class_under(mRoot, "Operation", rb_cObject);
    cSendHandle = rb_define_class_under(mRoot, "SendHandle", rb_cObject);

    rb_define_method(cTaskContext,
        "operation_return_types",
        RUBY_METHOD_FUNC(operation_return_types),
        1);
    rb_define_method(cTaskContext,
        "operation_argument_types",
        RUBY_METHOD_FUNC(operation_argument_types),
        1);
    rb_define_method(cTaskContext,
        "do_operation_call",
        RUBY_METHOD_FUNC(operation_call),
        5);
    rb_define_method(cTaskContext,
        "do_operation_send",
        RUBY_METHOD_FUNC(operation_send),
        3);
    rb_define_method(cSendHandle,
        "do_operation_collect",
        RUBY_METHOD_FUNC(send_handle_collect),
        2);
    rb_define_method(cSendHandle,
        "do_operation_collect_if_done",
        RUBY_METHOD_FUNC(send_handle_collect_if_done),
        2);

    rb_const_set(mRoot, rb_intern("SEND_SUCCESS"), INT2FIX(RTT::corba::CSendSuccess));
    rb_const_set(mRoot, rb_intern("SEND_NOT_READY"), INT2FIX(RTT::corba::CSendNotReady));
    rb_const_set(mRoot, rb_intern("SEND_FAILURE"), INT2FIX(RTT::corba::CSendFailure));
    rb_const_set(cSendHandle,
        rb_intern("SEND_SUCCESS"),
        INT2FIX(RTT::corba::CSendSuccess));
    rb_const_set(cSendHandle,
        rb_intern("SEND_NOT_READY"),
        INT2FIX(RTT::corba::CSendNotReady));
    rb_const_set(cSendHandle,
        rb_intern("SEND_FAILURE"),
        INT2FIX(RTT::corba::CSendFailure));
}
