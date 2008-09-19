PROJECT(rorocos)

SET (CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}")
INCLUDE(RubyExtensions)

ADD_DEFINITIONS(-D_REENTRANT)

INCLUDE_DIRECTORIES(${CMAKE_CURRENT_BINARY_DIR})
MACRO(TAO_ORB)
    ADD_DEFINITIONS(-DCORBA_IS_TAO)
    INCLUDE_DIRECTORIES(/usr/include/orbsvcs)
    FILE(GLOB IDL_FILES *.idl)
    FOREACH(idl_file ${IDL_FILES})
        FILE(RELATIVE_PATH idl_file ${CMAKE_CURRENT_SOURCE_DIR} ${idl_file})

        STRING(REGEX REPLACE ".idl$" "C.h"   hdr_file ${idl_file})
        STRING(REGEX REPLACE ".idl$" "C.inl" inl_file ${idl_file})
        STRING(REGEX REPLACE ".idl$" "C.cpp" cpp_file ${idl_file})
        SET(client_hdr "${hdr_file};${inl_file}")
        SET(client_imp ${cpp_file})

        LIST(APPEND ORB_IDL_FILES ${client_imp})
        add_custom_command(OUTPUT ${client_hdr} ${client_imp}
            COMMAND tao_idl -Gt -Gd ${CMAKE_CURRENT_SOURCE_DIR}/${idl_file} -I${CMAKE_CURRENT_SOURCE_DIR}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${idl_file})
    ENDFOREACH(idl_file ${IDL_FILES})

    SET(ORB_LIBRARIES /usr/lib/libTAO.so /usr/lib/libTAO_CosNaming.so)
ENDMACRO(TAO_ORB)
MACRO(OMNIORB)
    ADD_DEFINITIONS(-DCORBA_IS_OMNIORB)
    FILE(GLOB IDL_FILES *.idl)
    FOREACH(idl_file ${IDL_FILES})
        FILE(RELATIVE_PATH idl_file ${CMAKE_CURRENT_SOURCE_DIR} ${idl_file})

        STRING(REGEX REPLACE ".idl$" "C.h"   hdr_file ${idl_file})
        STRING(REGEX REPLACE ".idl$" "DynSK.cpp" dyn_file ${idl_file})
        STRING(REGEX REPLACE ".idl$" "C.cpp" cpp_file ${idl_file})
        SET(client_hdr "${hdr_file}")
        SET(client_imp "${cpp_file};${dyn_file}")

        LIST(APPEND ORB_IDL_FILES ${client_imp})
        add_custom_command(OUTPUT ${client_hdr} ${client_imp}
            COMMAND omniidl -bcxx -Wba -Wbh=C.h -Wbs=C.cpp -Wbd=DynSK.cpp -I${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/${idl_file}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${idl_file})
    ENDFOREACH(idl_file ${IDL_FILES})

    SET(ORB_LIBRARIES omniORB4 omniDynamic4)
ENDMACRO(OMNIORB)

OMNIORB()
ADD_RUBY_EXTENSION(rorocos_ext 
    rorocos.cc corba_access.cc ${ORB_IDL_FILES})
TARGET_LINK_LIBRARIES(rorocos_ext ${ORB_LIBRARIES})

ADD_EXECUTABLE(test main.cpp corba_access.cc ${ORB_IDL_FILES})
TARGET_LINK_LIBRARIES(test ${ORB_LIBRARIES})

