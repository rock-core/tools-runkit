#ifndef RTT_CORBA_HH
#define RTT_CORBA_HH

#include <boost/tuple/tuple.hpp>
#include <rtt/transports/corba/CorbaTypeTransporter.hpp>
#include <rtt/typelib/TypelibMarshallerBase.hpp>

// !!! ruby.h must be included LAST. It defines macros that break
// !!! omniORB code
// !!! also breaks boost nowadays, so keep it from substituting
#define RUBY_DONT_SUBST
#include <ruby.h>

// if RTT_VERSION_GTE is not defined by above includes (RTT versions below 2.9)
#ifndef RTT_VERSION_GTE
#define RTT_VERSION_GTE(major, minor, patch) false
#endif

namespace RTT {
    namespace types {
        class TypeInfo;
    }
}

namespace runkit {
    struct RInputPort {};
    struct ROutputPort {};
    struct RTaskContext;

    VALUE task_context_create(int argc, VALUE* argv, VALUE klass);

    RTT::types::TypeInfo* get_type_info(std::string const& name, bool do_check = true);
    orogen_transports::TypelibMarshallerBase* get_typelib_transport(
        RTT::types::TypeInfo* type,
        bool do_check = true);
    orogen_transports::TypelibMarshallerBase* get_typelib_transport(
        std::string const& name,
        bool do_check = true);
    RTT::corba::CorbaTypeTransporter* get_corba_transport(RTT::types::TypeInfo* type,
        bool do_check = true);
    RTT::corba::CorbaTypeTransporter* get_corba_transport(std::string const& name,
        bool do_check = true);
    boost::tuple<RTaskContext*, VALUE, VALUE> get_port_reference(VALUE port);

    extern VALUE mRoot;
    extern VALUE mCORBA;
    extern VALUE eComError;
    extern VALUE eCORBA;
    extern VALUE eCORBAComError;
    extern VALUE eCORBATimeoutError;
    extern VALUE cNameService;
    extern VALUE cTaskContext;
    extern VALUE eNotFound;
    extern VALUE eNotInitialized;
    extern VALUE eBlockingCallInForbiddenThread;
    extern VALUE threadInterdiction;
    extern VALUE corbaAccess;

    inline VALUE verify_thread_interdiction()
    {
        if (threadInterdiction == rb_thread_current()) {
            rb_raise(eBlockingCallInForbiddenThread,
                "network-accessing method called from forbidden thread");
        }
        return Qnil;
    }

    template <typename T> T& get_wrapped(VALUE self)
    {
        void* object = 0;
        Data_Get_Struct(self, void, object);
        return *reinterpret_cast<T*>(object);
    }
    template <typename T> T& get_iv(VALUE self, char const* name)
    {
        VALUE iv = rb_iv_get(self, name);
        return get_wrapped<T>(iv);
    }
    inline std::string get_str_iv(VALUE self, char const* name)
    {
        VALUE iv = rb_iv_get(self, name);
        return StringValuePtr(iv);
    }

    template <typename T> void delete_object(void* obj)
    {
        delete ((T*)obj);
    }
    template <typename T> VALUE simple_wrap(VALUE klass, T* obj = 0)
    {
        if (!obj)
            obj = new T;

        VALUE robj = Data_Wrap_Struct(klass, 0, delete_object<T>, obj);
        rb_iv_set(robj, "@corba", corbaAccess);
        return robj;
    }

    void rtt_corba_init_ruby_task_context(VALUE mRoot,
        VALUE cTaskContext,
        VALUE cOutputPort,
        VALUE cInputPort);
    void rtt_corba_init_CORBA(VALUE mRoot, VALUE mCORBA, VALUE mNameServices);
    void rtt_corba_init_data_handling(VALUE cTaskContext);
    void rtt_corba_init_operations(VALUE mRoot, VALUE cTaskContext);
}

#endif
