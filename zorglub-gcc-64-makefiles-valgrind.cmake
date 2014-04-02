# Client maintainer: mathieu . malaterre  gmail . com

set(CTEST_SITE "zorglub")
set(CTEST_BUILD_NAME "Linux-gcc-GIT")
set(CTEST_BUILD_CONFIGURATION Debug)
set(CTEST_CMAKE_GENERATOR "Unix Makefiles")
set(dashboard_root_name "MyTests")
SET(CTEST_BUILD_FLAGS "-j2")
set(dashboard_source_name "gdcm")
set(dashboard_binary_name "gdcm-gcc-tomate")
set(dashboard_do_memcheck TRUE)
set(dashboard_do_coverage FALSE)
set(CTEST_TEST_TIMEOUT 3000)

SET(CTEST_MEMORYCHECK_COMMAND           "/usr/bin/valgrind")
SET(CTEST_MEMORYCHECK_COMMAND_OPTIONS   "-q --tool=memcheck --leak-check=yes --show-reachable=yes --num-callers=10")
SET(ENV{GLIBCPP_FORCE_NEW} 1)
SET(ENV{GLIBCXX_FORCE_NEW} 1)

SET(ENV{CXXFLAGS} "-g -O0 -Wall -W -Wextra -Wshadow -Wunused -Wno-system-headers -Wno-deprecated -Woverloaded-virtual -Wwrite-strings -pedantic -Wno-long-long -Wsign-promo -Wabi -D_GLIBCXX_DEBUG")
SET(ENV{CFLAGS}   "-g -O0 -Wall -W -Wextra -pedantic -Wno-long-long")

#SET(ENV{JAVA_HOME} "/opt/jdk")
# Need to pass the path to the VTK libraries
#SET(ENV{LD_LIBRARY_PATH} "${CTEST_DASHBOARD_ROOT}/VTK-gcc-tomate/bin")

macro(dashboard_hook_init)
  set( dashboard_cache "
MEMORYCHECK_COMMAND_OPTIONS:STRING=${CTEST_MEMORYCHECK_COMMAND_OPTIONS}
GDCM_BUILD_SHARED_LIBS:BOOL=ON
GDCM_BUILD_APPLICATIONS:BOOL=ON
GDCM_BUILD_EXAMPLES:BOOL=ON
GDCM_USE_VTK:BOOL=ON
# Cannot use CTEST_DASHBOARD_ROOT directly...
CMAKE_INSTALL_PREFIX:PATH=/tmp/tomate-gdcm
# wrapping stuff
GDCM_WRAP_PYTHON:BOOL=ON
# cant get python/cmake stuff working:
# hardcode for now:
PYTHON_EXECUTABLE:FILEPATH=/usr/bin/python2.7
PYTHON_INCLUDE_DIR:PATH=/usr/include/python2.7
PYTHON_INCLUDE_DIR2:PATH=/usr/include/python2.7
PYTHON_LIBRARY:FILEPATH=/usr/lib/libpython2.7.so
GDCM_WRAP_JAVA:BOOL=ON
GDCM_WRAP_CSHARP:BOOL=OFF
GDCM_USE_SYSTEM_OPENSSL:BOOL=ON
GDCM_TEST_DCMTK:BOOL=ON
GDCM_DATA_EXTRA_ROOT:PATH=${CTEST_DASHBOARD_ROOT}/gdcmDataExtra
GDCM_TEST_BOOTSTRAP:BOOL=ON
GDCM_USE_SYSTEM_LIBXML2:BOOL=ON
    "
    )
endmacro(dashboard_hook_init)

include(${CTEST_SCRIPT_DIRECTORY}/gdcm_common.cmake)
