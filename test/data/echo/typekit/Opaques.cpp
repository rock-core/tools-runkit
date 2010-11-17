#include "Opaques.hpp"

    /** Returns the intermediate value that is contained in \c real_type */
    /** Stores \c intermediate into \c real_type. \c intermediate is owned by \c
     * real_type afterwards. */
    /** Release ownership of \c real_type on the corresponding intermediate
     * pointer.
     */


void orogen_typekits::toIntermediate(echo::Point& intermediate, OpaquePoint const& real_type)
{
    intermediate.x = real_type.x();
    intermediate.y = real_type.y();
}

void orogen_typekits::fromIntermediate(OpaquePoint& real_type, echo::Point const& intermediate)
{
    real_type = OpaquePoint(intermediate.x, intermediate.y);
}



