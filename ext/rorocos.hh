#ifndef OROCOS_EXT_RB_ROROCOS_HH
#define OROCOS_EXT_RB_ROROCOS_HH

#include "TaskContextC.h"
#include "DataFlowC.h"
#include "corba.hh"
#include <boost/tuple/tuple.hpp>

#include <TypelibMarshallerBase.hpp>
#include <rtt/transports/corba/CorbaTypeTransporter.hpp>

extern VALUE eNotFound;

struct RTaskContext
{
    RTT::corba::CTaskContext_var         task;
    RTT::corba::CService_var     main_service;
    RTT::corba::CDataFlowInterface_var   ports;
};

struct RInputPort { };
struct ROutputPort { };

namespace RTT
{
    namespace types {
        class TypeInfo;
    }
}
extern RTT::types::TypeInfo* get_type_info(std::string const& name, bool do_check = true);
extern orogen_transports::TypelibMarshallerBase* get_typelib_transport(RTT::types::TypeInfo* type, bool do_check = true);
extern orogen_transports::TypelibMarshallerBase* get_typelib_transport(std::string const& name, bool do_check = true);
extern RTT::corba::CorbaTypeTransporter* get_corba_transport(RTT::types::TypeInfo* type, bool do_check = true);
extern RTT::corba::CorbaTypeTransporter* get_corba_transport(std::string const& name, bool do_check = true);
extern boost::tuple<RTaskContext*, VALUE, VALUE> getPortReference(VALUE port);

namespace
{
    template<typename T>
    T& get_wrapped(VALUE self)
    {
        void* object = 0;
        Data_Get_Struct(self, void, object);
        return *reinterpret_cast<T*>(object);
    }
    template<typename T>
    T& get_iv(VALUE self, char const* name)
    {
        VALUE iv = rb_iv_get(self, name);
        return get_wrapped<T>(iv);
    }
    std::string get_str_iv(VALUE self, char const* name)
    {
        VALUE iv = rb_iv_get(self, name);
        return StringValuePtr(iv);
    }

    template<typename T>
    void delete_object(void* obj) { delete( (T*)obj ); }
    template<typename T>
    VALUE simple_wrap(VALUE klass, T* obj = 0)
    {
        if (! obj)
            obj = new T;

        VALUE robj = Data_Wrap_Struct(klass, 0, delete_object<T>, obj);
        rb_iv_set(robj, "@corba", corba_access);
        return robj;
    }
}

#endif

