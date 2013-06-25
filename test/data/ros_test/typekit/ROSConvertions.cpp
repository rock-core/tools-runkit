/* Generated from orogen/lib/orogen/templates/typekit/ros/Convertions.cpp */

#include "ROSConvertions.hpp"


void ros_convertions::toROS( ros::Time& ros, ::ros_test::Time const& value )
{
    ros.fromNSec(value.milliseconds * 1000000);
}
void ros_convertions::fromROS( ::ros_test::Time& value, ros::Time const& ros )
{
    value.milliseconds = ros.toNSec() / 1000000;
}

