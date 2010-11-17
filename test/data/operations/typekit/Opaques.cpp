/* Generated from orogen/lib/orogen/templates/typekit/Opaques.cpp */

#include "Opaques.hpp"

    /** Returns the intermediate value that is contained in \c real_type */
    /** Stores \c intermediate into \c real_type. \c intermediate is owned by \c
     * real_type afterwards. */
    /** Release ownership of \c real_type on the corresponding intermediate
     * pointer.
     */


void orogen_typekits::toIntermediate(::Test::Parameters& intermediate, ::Test::Opaque const& real_type)
{
    intermediate.set_point = real_type.getSetPoint();
    intermediate.threshold = real_type.getThreshold();
}

void orogen_typekits::fromIntermediate(::Test::Opaque& real_type, ::Test::Parameters const& intermediate)
{
    real_type = Test::Opaque(intermediate.set_point, intermediate.threshold);
}



