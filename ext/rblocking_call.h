#ifndef _BLOCKING_FUNCTION_BASE___H
#define _BLOCKING_FUNCTION_BASE___H

//Helper templates to encapsulate rb_thread_blocking_region
//
#include <boost/function.hpp>
#include <boost/function_types/result_type.hpp>
#include <boost/bind.hpp>
#include <ruby.h>
#include <stdarg.h>

#define EXCEPTION_HANDLERS \
    catch(std::runtime_error &e) { BlockingFunctionBase::raise(rb_eRuntimeError, e.what());}\
    catch(std::exception& e) { BlockingFunctionBase::raise(rb_eException,e.what()); }

class BlockingFunctionBase
{
    protected:
        virtual void processing() = 0;
        virtual void abort() = 0;

        void blockingCall()
        {
            exception_class = Qnil;
#ifdef HAVE_RUBY_INTERN_H
            rb_thread_blocking_region(&BlockingFunctionBase::callProcessing, this,
                    &BlockingFunctionBase::callAbort, this);
#else
            callProcessing(this);
#endif
            if (RTEST(exception_class))
            {
                rb_raise(exception_class, "%s",exception_message.c_str());
            }
        }

        void raise(VALUE exception_class, const char* format, ...)
        {
            char buffer[256];
            va_list args;
            va_start(args, format);
            vsnprintf(buffer,256, format, args);
            va_end (args);

            this->exception_class = exception_class;
            this->exception_message = buffer;
        }

        void raise(VALUE exception_class, std::string const& message)
        {
            this->exception_class = exception_class;
            this->exception_message = message;
        }

        //called if no abort function is 
        //specified. We cannot test on empty() as
        //F and A might be of type boost::_bi::bind_t
        static void abort_default()
        {
        }

    private:
        static VALUE callProcessing(void* ptr)
        {
            reinterpret_cast<BlockingFunctionBase*>(ptr)->processing();
            return Qnil;
        }

        static void callAbort(void* ptr)
        {
            reinterpret_cast<BlockingFunctionBase*>(ptr)->abort();
        }

        VALUE exception_class;               //stores the exception class
        std::string exception_message;       //stores the message of the exeption
};

template<typename F, typename A = boost::function<void()> >
class BlockingFunction : public BlockingFunctionBase
{
    public:
        static void call(F processing, A abort = &BlockingFunction::abort_default)
        {
            BlockingFunction<F, A> bf(processing, abort);
            bf.blockingCall();
        }

    protected:
        BlockingFunction(F processing, A abort)
            :processing_fct(processing),abort_fct(abort)
        { }

        virtual void processing()
        {
            try{processing_fct();}
            EXCEPTION_HANDLERS
        }

        void abort()
        {
            try{ abort_fct();}
            EXCEPTION_HANDLERS
        }

        F processing_fct;
        A abort_fct;
};

template<typename F, typename A = boost::function<void()> >
class BlockingFunctionWithResult : public BlockingFunction<F, A>
{
    public:
        typedef typename F::result_type result_t;
        static result_t call(F processing, A abort = &BlockingFunctionBase::abort_default)
        {
            BlockingFunctionWithResult<F, A> bf(processing, abort);
            bf.blockingCall();
            return bf.return_val;
        }

    protected:
        BlockingFunctionWithResult(F processing, A abort):
            BlockingFunction<F, A>::BlockingFunction(processing, abort)
    { }

        virtual void processing()
        {
            try{ return_val = BlockingFunction<F,A>::processing_fct();}
            EXCEPTION_HANDLERS
        }

    protected:
        result_t return_val;
};

// template functions can automatically pick up their template paramters
template<typename F, typename A>
void blocking_fct_call(F processing, A abort)
{
    BlockingFunction<F,A>::call(processing,abort);
}

template<typename F>
void blocking_fct_call(F processing)
{
    BlockingFunction<F>::call(processing);
}

template<typename F, typename A>
typename F::result_type blocking_fct_call_with_result(F processing, A abort)
{
    return BlockingFunctionWithResult<F,A>::call(processing,abort);
}

template<typename F>
typename F::result_type blocking_fct_call_with_result(F processing)
{
    return BlockingFunctionWithResult<F>::call(processing);
}

#endif
