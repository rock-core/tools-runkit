#ifndef OROCOS_RB_EXT_CORBA_HH
#define OROCOS_RB_EXT_CORBA_HH

#include <omniORB4/CORBA.h>

#include <exception>
#include "TaskContextC.h"
#include "DataFlowC.h"
#include <iostream>
#include <string>
#include <stack>
#include <list>
#include <ruby.h>
#include <typelib_ruby.hh>

using namespace std;

extern VALUE corba_access;
extern VALUE eCORBA;
extern VALUE eComError;
extern VALUE mCORBA;
extern VALUE eNotFound;
extern VALUE eNotInitialized;

namespace RTT
{
    class TaskContext;
    namespace base {
        class PortInterface;
    }
    namespace corba
    {
        class TaskContextServer;
    }
}

class InvalidIORError :public std::runtime_error
{
    public:
        InvalidIORError(const std::string& what_arg):
            std::runtime_error(what_arg)
    {
    };
};

struct RTaskContext
{
    RTT::corba::CTaskContext_var         task;
    RTT::corba::CService_var     main_service;
    RTT::corba::CDataFlowInterface_var   ports;
    std::string name;
};

/**
 * This class locates and connects to a Corba TaskContext.
 * It can do that through an IOR.
 */
class CorbaAccess
{
private:
    RTT::TaskContext* m_task;
    RTT::corba::TaskContextServer* m_task_server;
    RTT::corba::CTaskContext_ptr m_corba_task;
    RTT::corba::CDataFlowInterface_ptr m_corba_dataflow;

    CorbaAccess(std::string const& name, int argc, char* argv[] );
    ~CorbaAccess();

    RTT::corba::CTaskContext_var getCTaskContext(std::string const& ior);

    static CorbaAccess* the_instance;
    // This counter is used to generate local port names that are unique
    int64_t port_id_counter;

public:
    static void init(std::string const& name, int argc, char* argv[]);
    static void deinit();
    static CorbaAccess* instance() { return the_instance; }

    /** Returns a new RTaskContext for the given IOR or throws an exception
     *  if the remote task context cannot be reached.
     */
    RTaskContext* createRTaskContext(std::string const& ior);

    /** Returns an automatic name for a port used to access the given remote
     * port
     */
    std::string getLocalPortName(VALUE remote_port);

    /** Returns the CORBA object that is a representation of our dataflow
     * interface
     */
    RTT::corba::CDataFlowInterface_ptr getDataFlowInterface() const;

    /** Adds a local port to the RTT interface for this Ruby process
     */
    void addPort(RTT::base::PortInterface* local_port);

    /** De-references a port that had been added by addPort
     */
    void removePort(RTT::base::PortInterface* local_port);
};

extern VALUE corba_to_ruby(std::string const& type_name, Typelib::Value dest, CORBA::Any& src);
extern CORBA::Any* ruby_to_corba(std::string const& type_name, Typelib::Value src);

#define CORBA_EXCEPTION_HANDLERS \
    catch(CosNaming::NamingContext::NotFound& e) { rb_raise(eNotFound, "cannot find naming context %s",e.rest_of_name[0].id.in()); } \
    catch(CORBA::COMM_FAILURE&) { rb_raise(eComError, "CORBA communication failure"); } \
    catch(CORBA::TRANSIENT&) { rb_raise(eComError, "CORBA transient exception"); } \
    catch(CORBA::INV_OBJREF&) { rb_raise(eCORBA, "CORBA invalid obj reference"); } \
    catch(CORBA::SystemException&) { rb_raise(eCORBA, "CORBA system exception"); } \
    catch(CORBA::Exception& e) { rb_raise(eCORBA, "unspecified error in the CORBA layer: %s", typeid(e).name()); }
#endif

