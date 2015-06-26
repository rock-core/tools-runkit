cmake_minimum_required(VERSION 2.6)
PROJECT(corba)

SET (CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")
INCLUDE(RubyExtensions)

IF(APPLE)
  set(CMAKE_SHARED_MODULE_SUFFIX ".bundle")
  set(CMAKE_MACOSX_RPATH 1)
ENDIF(APPLE)

if (${CMAKE_SYSTEM_NAME} STREQUAL "Linux")
    message(STATUS "running on Linux, implementing the __orogen_getTID() operation on all tasks")
    add_definitions(-DHAS_GETTID)
else()
    message(STATUS "NOT running on Linux (cmake reports ${CMAKE_SYSTEM_NAME}). The __orogen_getTID() operation will be a dummy")
endif()

ADD_DEFINITIONS(-D_REENTRANT)
MACRO(CMAKE_USE_FULL_RPATH install_rpath)
    # use, i.e. don't skip the full RPATH for the build tree
    SET(CMAKE_SKIP_BUILD_RPATH  FALSE)

    # when building, don't use the install RPATH already
    # (but later on when installing)
    SET(CMAKE_BUILD_WITH_INSTALL_RPATH FALSE) 

    # the RPATH to be used when installing
    SET(CMAKE_INSTALL_RPATH ${install_rpath})

    # add the automatically determined parts of the RPATH
    # which point to directories outside the build tree to the install RPATH
    SET(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
ENDMACRO(CMAKE_USE_FULL_RPATH)
CMAKE_USE_FULL_RPATH("")

include(FindPkgConfig)

pkg_check_modules(RTT_Typelib REQUIRED rtt_typelib-${OROCOS_TARGET})
include_directories( ${RTT_Typelib_INCLUDE_DIRS} )
link_directories( ${RTT_Typelib_LIBRARY_DIRS} )

pkg_check_modules(RTT REQUIRED orocos-rtt-${OROCOS_TARGET})
ADD_DEFINITIONS( ${RTT_CFLAGS} )
INCLUDE_DIRECTORIES( ${RTT_INCLUDE_DIRS} )
LINK_DIRECTORIES( ${RTT_LIBRARY_DIRS} )

pkg_check_modules(RTT_MQUEUE orocos-rtt-mqueue-${OROCOS_TARGET})
if (RTT_MQUEUE_FOUND)
    include_directories( ${RTT_MQUEUE_INCLUDE_DIRS} )
    add_definitions(-DHAS_MQUEUE)
    list(APPEND ADDITIONAL_RTT_PLUGINS rtt-transport-mqueue)
else()
    message(STATUS "could not find the RTT MQueue transport, disabling support in orocos.rb")
endif()

pkg_check_modules(RTT_ROS orocos-rtt-ros-${OROCOS_TARGET} roscpp)
if (RTT_ROS_FOUND)
    include_directories( ${RTT_ROS_INCLUDE_DIRS} )
    add_definitions(-DHAS_ROS)
    list(APPEND ADDITIONAL_RTT_PLUGINS rtt-transport-ros)
    list(APPEND ROS_FILES ros.cc)
else()
    message(STATUS "could not find the RTT ROS transport, disabling support in orocos.rb")
endif()

pkg_check_modules(RTT_CORBA REQUIRED orocos-rtt-corba-${OROCOS_TARGET})
FIND_PATH(IDL_DIR TaskContext.idl ${RTT_CORBA_INCLUDE_DIRS})
if (NOT IDL_DIR)
    message(FATAL_ERROR "cannot find the Orocos/CORBA IDL files")
endif()
FILE(GLOB IDL_FILES ${IDL_DIR}/*.idl)

pkg_check_modules(TYPELIB REQUIRED typelib)
INCLUDE_DIRECTORIES( ${TYPELIB_INCLUDE_DIRS} )
LINK_DIRECTORIES( ${TYPELIB_LIBRARY_DIRS} )

pkg_check_modules(TYPELIB_RUBY REQUIRED typelib_ruby)
INCLUDE_DIRECTORIES( ${TYPELIB_RUBY_INCLUDE_DIRS} )
LINK_DIRECTORIES( ${TYPELIB_RUBY_LIBRARY_DIRS} )

list(APPEND CMAKE_PREFIX_PATH ${RTT_PREFIX})
find_package(RTTPlugin COMPONENTS rtt-typekit rtt-transport-corba ${ADDITIONAL_RTT_PLUGINS})

ADD_DEFINITIONS( -DOROCOS_TARGET=${OROCOS_TARGET} )
INCLUDE_DIRECTORIES( ${RTT_CORBA_INCLUDE_DIRS} )
LINK_DIRECTORIES( ${RTT_CORBA_LIBRARY_DIRS} )

INCLUDE_DIRECTORIES(${CMAKE_CURRENT_BINARY_DIR})
MACRO(TAO_ORB)
    ADD_DEFINITIONS(-DCORBA_IS_TAO)
    INCLUDE_DIRECTORIES(/usr/include/orbsvcs)
    FOREACH(idl_file ${IDL_FILES})
        FILE(RELATIVE_PATH idl_basename ${IDL_DIR} ${idl_file})

        STRING(REGEX REPLACE ".idl$" "C.h"   hdr_file ${idl_basename})
        STRING(REGEX REPLACE ".idl$" "C.inl" inl_file ${idl_basename})
        STRING(REGEX REPLACE ".idl$" "C.cpp" cpp_file ${idl_basename})
        SET(client_hdr "${hdr_file};${inl_file}")
        SET(client_imp ${cpp_file})

        LIST(APPEND ORB_IDL_FILES ${client_imp})
        add_custom_command(OUTPUT ${client_hdr} ${client_imp}
            COMMAND tao_idl -Gt -Gd ${CMAKE_CURRENT_SOURCE_DIR}/${idl_file} -I${CMAKE_CURRENT_SOURCE_DIR}
            DEPENDS ${idl_file})
    ENDFOREACH(idl_file ${IDL_FILES})

    SET(ORB_LIBRARIES /usr/lib/libTAO.so /usr/lib/libTAO_CosNaming.so)
ENDMACRO(TAO_ORB)
MACRO(OMNIORB)
    ADD_DEFINITIONS(-DCORBA_IS_OMNIORB)
    FOREACH(idl_file ${IDL_FILES})
        FILE(RELATIVE_PATH idl_basename ${IDL_DIR} ${idl_file})

        STRING(REGEX REPLACE ".idl$" "C.h"   hdr_file ${idl_basename})
        STRING(REGEX REPLACE ".idl$" "DynSK.cpp" dyn_file ${idl_basename})
        STRING(REGEX REPLACE ".idl$" "C.cpp" cpp_file ${idl_basename})
        SET(client_hdr "${hdr_file}")
        SET(client_imp "${cpp_file};${dyn_file}")

        LIST(APPEND ORB_IDL_FILES ${client_imp})
        add_custom_command(OUTPUT ${client_hdr} ${client_imp}
            COMMAND omniidl -bcxx -Wba -Wbh=C.h -Wbs=C.cpp -Wbd=DynSK.cpp -I${CMAKE_CURRENT_SOURCE_DIR} ${idl_file}
            DEPENDS ${idl_file})
    ENDFOREACH(idl_file ${IDL_FILES})

    SET(ORB_LIBRARIES omniORB4 omniDynamic4)
ENDMACRO(OMNIORB)

link_directories(${RTT_ROS_LIBRARY_DIRS})

OMNIORB()
SET(EXTENSION_NAME rorocos)
ADD_RUBY_EXTENSION(${EXTENSION_NAME}
    ruby_task_context.cc rorocos.cc corba.cc datahandling.cc operations.cc
    lib/corba_name_service_client.cc ${ORB_IDL_FILES} ${ROS_FILES})
target_link_libraries(${EXTENSION_NAME} ${ORB_LIBRARIES} ${RTT_LIBRARIES}
    ${RTT_CORBA_LIBRARIES} ${TYPELIB_LIBRARIES}
    ${RTT_PLUGIN_rtt-typekit_LIBRARY}
    ${RTT_PLUGIN_rtt-transport-corba_LIBRARY}
    ${RTT_Typelib_LIBRARIES}
    ${RTT_ROS_LIBRARIES})
if (RTT_MQUEUE_FOUND)
    target_link_libraries(${EXTENSION_NAME}
        ${RTT_PLUGIN_rtt-transport-mqueue_LIBRARY})
endif()

INSTALL(TARGETS ${EXTENSION_NAME} LIBRARY DESTINATION ".")

