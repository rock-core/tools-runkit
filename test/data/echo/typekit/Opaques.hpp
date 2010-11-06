#ifndef echo_USER_MARSHALLING_HH
#define echo_USER_MARSHALLING_HH

#include <echo/Types.hpp>

namespace echo
{
    
    /** Converts \c real_type into \c intermediate */
    void to_intermediate(echo::Point& intermediate, OpaquePoint const& real_type);
    /** Converts \c intermediate into \c real_type */
    void from_intermediate(OpaquePoint& real_type, echo::Point const& intermediate);
        
    
}

#endif

