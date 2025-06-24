#
# Python package
#

set(CMAKE_MESSAGE_INDENT "[${PROJECT_NAME}][python] ")
set(DEFAULT_PYTHON_RPATH "\$ORIGIN:\$ORIGIN/../../..:\$ORIGIN/../../../rocprofiler-sdk")

include("${CMAKE_CURRENT_LIST_DIR}/utilities.cmake")

if(NOT ROCPROFILER_PYTHON_VERSIONS)
    unset(ROCPROFILER_PYTHON_VERSIONS CACHE)
    get_default_python_versions(DEFAULT_PYTHON_VERSIONS)
    set(ROCPROFILER_PYTHON_VERSIONS
        "${DEFAULT_PYTHON_VERSIONS}"
        CACHE STRING "")
endif()

add_subdirectory(roctx)
add_subdirectory(rocpd)
