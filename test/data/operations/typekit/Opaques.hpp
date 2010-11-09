/* Generated from orogen/lib/orogen/templates/typekit/Opaques.hpp */

#ifndef operations_USER_MARSHALLING_HH
#define operations_USER_MARSHALLING_HH

#include <operations/Types.hpp>

namespace operations
{
    
    /** Converts \c real_type into \c intermediate */
    void to_intermediate(::Test::Parameters& intermediate, ::Test::Opaque const& real_type);
    /** Converts \c intermediate into \c real_type */
    void from_intermediate(::Test::Opaque& real_type, ::Test::Parameters const& intermediate);
        
    
}

#endif

