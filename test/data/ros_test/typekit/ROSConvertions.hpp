/* Generated from orogen/lib/orogen/templates/typekit/ros/ROSConvertions.hpp */

#ifndef __OROGEN_GENERATED_ROS_TEST_ROS_CONVERTIONS_USER_HPP
#define __OROGEN_GENERATED_ROS_TEST_ROS_CONVERTIONS_USER_HPP

#include "Types.hpp"
#include <boost/cstdint.hpp>
#include <string>


#include <time.h>
#include <std_msgs/Time.h>



namespace ros_convertions {
    /** Converted types: */
    
    void toROS( ros::Time& ros, ::ros_test::Time const& value );
    void fromROS( ::ros_test::Time& value, ros::Time const& ros );
    
}

#endif


