#include "rorocos.hh"
#include <memory>
#include "OperationsC.h"
#include <typeinfo>

using namespace std;
using namespace RTT::Corba;

static VALUE cCallable;
static VALUE cMethod;
static VALUE cCommand;
static VALUE eNeverCalled;
struct RMethod
{
    RTT::Corba::Method_var method;
    ~RMethod()
    {
        if (!CORBA::is_nil(method))
        {
            try { method->destroyExpression(); }
            catch(CORBA::Exception&) {}
        }
    }
};
struct RCommand
{
    RTT::Corba::Command_var command;
    ~RCommand()
    {
        if (!CORBA::is_nil(command))
        {
            try { command->destroyCommand(); }
            catch(CORBA::Exception&) {}
        }
    }
};

template<typename RemoteInterface>
static void init_method_or_command(VALUE task_, RemoteInterface iface, VALUE name_, VALUE obj)
{
    char const* name = StringValuePtr(name_);
    try {
        CORBA::String_var description = iface->getDescription(name);
        CORBA::String_var return_type = iface->getResultType(name);
        Descriptions_var arguments    = iface->getArguments(name);

        rb_iv_set(obj, "@name", name_);
        rb_iv_set(obj, "@description", rb_str_new2(description));
        rb_iv_set(obj, "@return_spec", rb_str_new2(return_type));

        VALUE arg_spec = rb_ary_new();
        for (int i = 0; i < arguments->length(); ++i)
        {
            VALUE desc = rb_ary_new();
            rb_ary_push(desc, rb_str_new2(arguments[i].name));
            rb_ary_push(desc, rb_str_new2(arguments[i].description));
            rb_ary_push(desc, rb_str_new2(arguments[i].type));
            rb_ary_push(arg_spec, desc);
        }
        rb_iv_set(obj, "@arguments_spec", arg_spec);
        rb_iv_set(obj, "@task", task_);
        rb_funcall(obj, rb_intern("initialize"), 0);
    }
    catch(RTT::Corba::NoSuchNameException&)
    { rb_raise(eNotFound, "no method or command '%s'", name); }
    catch(CORBA::COMM_FAILURE&) { rb_raise(eComError, ""); }
    catch(CORBA::TRANSIENT&)    { rb_raise(eComError, ""); }
    catch(CORBA::Exception& e)
    { rb_raise(eCORBA, "unspecified CORBA error of type %s", typeid(e).name()); }
}

static AnyArguments* init_corba_args(VALUE type_names, VALUE args)
{
    AnyArguments_var corba_args = new AnyArguments;
    corba_args->length(RARRAY_LEN(args));

    size_t len = RARRAY_LEN(args);
    VALUE* value_ptr = RARRAY_PTR(args);
    VALUE* types_ptr = RARRAY_PTR(type_names);
    for (size_t i = 0; i < len; ++i)
    {
        Typelib::Value v = typelib_get(value_ptr[i]);
        CORBA::Any_var to_corba = ruby_to_corba(
                StringValuePtr(types_ptr[i]), v);

        corba_args[i] = to_corba;
    }

    return corba_args._retn();
}

static VALUE task_rtt_method(VALUE task_, VALUE name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    
    // Unfortunately, we have to initialize the method_var lazily, because RTT's
    // CORBA interface requires initial arguments to be given;
    auto_ptr<RMethod> rmethod(new RMethod);
    VALUE obj = simple_wrap(cMethod, rmethod.release());

    init_method_or_command<RTT::Corba::MethodInterface_ptr>(task_, task.methods, name, obj);
    return obj;
}

static VALUE task_rtt_command(VALUE task_, VALUE name)
{
    RTaskContext& task = get_wrapped<RTaskContext>(task_);
    
    // Unfortunately, we have to initialize the method_var lazily, because RTT's
    // CORBA interface requires initial arguments to be given;
    auto_ptr<RCommand> rcommand(new RCommand);
    VALUE obj = simple_wrap(cCommand, rcommand.release());

    init_method_or_command<RTT::Corba::CommandInterface_ptr>(task_, task.commands, name, obj);
    return obj;
}

static VALUE method_recall(VALUE method_, VALUE result_)
{
    RMethod& method = get_wrapped<RMethod>(method_);
    if (CORBA::is_nil(method.method))
        rb_raise(eNeverCalled, "you must call this method at least once before using #recall");

    try
    {
        method.method->execute();
        CORBA::Any_var corba_result = method.method->value();
        Typelib::Value result = typelib_get(result_);
        corba_to_ruby(get_str_iv(method_, "@return_spec"), result, corba_result);
        return result_;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE method_call(VALUE method_, VALUE type_names, VALUE args, VALUE result_)
{
    RMethod& method = get_wrapped<RMethod>(method_);
    AnyArguments_var corba_args = init_corba_args(type_names, args);
    try
    {
        if (CORBA::is_nil(method.method))
        {
            RTaskContext& task = get_iv<RTaskContext>(method_, "@task");
            std::string   name = get_str_iv(method_, "@name");
            method.method = task.methods->createMethodAny(name.c_str(),
                    corba_args);
            method.method->execute();
        }
        else
        {
            method.method->executeAny(corba_args);
        }
        CORBA::Any_var corba_result = method.method->value();
        Typelib::Value result = typelib_get(result_);
        corba_to_ruby(get_str_iv(method_, "@return_spec"), result, corba_result);
        return result_;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE command_call(VALUE command_, VALUE type_names, VALUE args)
{
    RCommand& command = get_wrapped<RCommand>(command_);
    AnyArguments_var corba_args = init_corba_args(type_names, args);
    try
    {
        if (CORBA::is_nil(command.command))
        {
            RTaskContext& task = get_iv<RTaskContext>(command_, "@task");
            std::string   name = get_str_iv(command_, "@name");
            command.command = task.commands->createCommandAny(name.c_str(),
                    corba_args);
            command.command->reset();
            command.command->execute();
        }
        else
        {
            command.command->executeAny(corba_args);
        }
        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE command_state(VALUE command_)
{
    RCommand& command = get_wrapped<RCommand>(command_);
    try
    { return INT2FIX(command.command->status()); }
    CORBA_EXCEPTION_HANDLERS
}

static VALUE command_reset(VALUE command_)
{
    RCommand& command = get_wrapped<RCommand>(command_);
    try
    {
        command.command->reset();
        return Qnil;
    }
    CORBA_EXCEPTION_HANDLERS
}

void Orocos_init_methods()
{
    VALUE mOrocos = rb_define_module("Orocos");
    VALUE cTaskContext = rb_define_class_under(mOrocos, "TaskContext", rb_cObject);
    cCallable    = rb_define_class_under(mOrocos, "Callable", rb_cObject);
    cMethod      = rb_define_class_under(mOrocos, "RTTMethod", cCallable);
    cCommand     = rb_define_class_under(mOrocos, "Command", cCallable);
    eNeverCalled = rb_define_class_under(mOrocos, "NeverCalled", rb_eRuntimeError);
    rb_define_method(cTaskContext, "do_rtt_method",  RUBY_METHOD_FUNC(task_rtt_method), 1);
    rb_define_method(cMethod, "do_call", RUBY_METHOD_FUNC(method_call), 3);
    rb_define_method(cMethod, "do_recall", RUBY_METHOD_FUNC(method_recall), 1);

    rb_define_method(cTaskContext, "do_command", RUBY_METHOD_FUNC(task_rtt_command), 1);
    rb_define_method(cCommand, "do_call", RUBY_METHOD_FUNC(command_call), 2);
    rb_define_method(cCommand, "do_state", RUBY_METHOD_FUNC(command_state), 0);
    rb_define_method(cCommand, "do_reset", RUBY_METHOD_FUNC(command_reset), 0);

    rb_const_set(cCommand, rb_intern("STATE_NOT_READY"),       INT2FIX(RTT::Corba::NotReady));
    rb_const_set(cCommand, rb_intern("STATE_READY"),           INT2FIX(RTT::Corba::Ready));
    rb_const_set(cCommand, rb_intern("STATE_SENT"),            INT2FIX(RTT::Corba::Sent));
    rb_const_set(cCommand, rb_intern("STATE_NOT_ACCEPTED"),    INT2FIX(RTT::Corba::NotAccepted));
    rb_const_set(cCommand, rb_intern("STATE_ACCEPTED"),        INT2FIX(RTT::Corba::Accepted));
    rb_const_set(cCommand, rb_intern("STATE_EXECUTED"),        INT2FIX(RTT::Corba::Executed));
    rb_const_set(cCommand, rb_intern("STATE_NOT_VALID"),       INT2FIX(RTT::Corba::NotValid));
    rb_const_set(cCommand, rb_intern("STATE_VALID"),           INT2FIX(RTT::Corba::Valid));
    rb_const_set(cCommand, rb_intern("STATE_DONE"),            INT2FIX(RTT::Corba::Done));
}

