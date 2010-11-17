#ifndef echo_USER_MARSHALLING_HH
#define echo_USER_MARSHALLING_HH

#include <echo/Types.hpp>

namespace orogen_typekits
{
    
    /** Converts \c real_type into \c intermediate */
    void toIntermediate(echo::Point& intermediate, OpaquePoint const& real_type);
    /** Converts \c intermediate into \c real_type */
    void fromIntermediate(OpaquePoint& real_type, echo::Point const& intermediate);
        
    
}

#endif

