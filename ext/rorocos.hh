#ifndef OROCOS_EXT_RB_ROROCOS_HH
#define OROCOS_EXT_RB_ROROCOS_HH

#include "ControlTaskC.h"
#include "DataFlowC.h"
#include "corba.hh"
#include <boost/tuple/tuple.hpp>

extern VALUE eNotFound;

struct RTaskContext
{
    RTT::Corba::ControlTask_var        task;
    RTT::Corba::DataFlowInterface_var  ports;
    RTT::Corba::AttributeInterface_var attributes;
    RTT::Corba::MethodInterface_var    methods;
    RTT::Corba::CommandInterface_var   commands;
};

struct RInputPort { };
struct ROutputPort { };

struct RAttribute
{
    RTT::Corba::Expression_var expr;
};

namespace RTT
{
    class TypeInfo;
}
extern RTT::TypeInfo* get_type_info(std::string const& name);
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

