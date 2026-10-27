# Unit tests of the eos changes to asteroid-launcher and its lipstick, built natively (x86_64) with Debian's Qt 6:
#   cmake -S tests -B build-tests [-DCOVERAGE=ON] && cmake --build build-tests && ctest --test-dir build-tests
# Only the units under test are compiled, from their real sources; the AsteroidOS-only libraries they include
# (lipstick's compositor, mlite, ngf, qmce, mce-dev) are the stubs in stubs/, lipstick's NotificationManager is
# fakes/fakenotificationmanager.cpp behind its real header. D-Bus peers (mce, BlueZ, GeoClue, PulseAudio) are fakes
# on a private dbus-daemon each test starts (common/). .sonar/coverage.sh runs this for SonarQube.
cmake_minimum_required(VERSION 3.16)
project(asteroid-launcher-tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core DBus Gui Test)
find_package(PkgConfig REQUIRED)
pkg_check_modules(DBUSGLIB REQUIRED IMPORTED_TARGET dbus-1 dbus-glib-1 glib-2.0)

option(COVERAGE "Compile the units under test with gcc --coverage" OFF)

set(REPO ${CMAKE_CURRENT_SOURCE_DIR}/..)
set(LIPSTICK ${REPO}/lipstick/src)

enable_testing()
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/junit)

add_library(testcommon STATIC common/fakeservice.cpp common/fakeservice.h common/mce.h)
target_include_directories(testcommon PUBLIC common)
target_compile_definitions(testcommon PUBLIC TEST_BUS_CONFIG="${CMAKE_CURRENT_SOURCE_DIR}/common/test-bus.conf")
target_link_libraries(testcommon PUBLIC Qt6::Core Qt6::DBus Qt6::Test)

# launcher_test(NAME SOURCES test.cpp ... UNITS real-source.cpp ... [INCLUDES dir ...] [LIBS lib ...])
function(launcher_test name)
    cmake_parse_arguments(T "" "" "SOURCES;UNITS;INCLUDES;LIBS" ${ARGN})
    add_executable(${name} ${T_SOURCES} ${T_UNITS})
    # the stubs come before the real include directories
    target_include_directories(${name} PRIVATE stubs fakes ${T_INCLUDES})
    target_compile_definitions(${name} PRIVATE UNIT_TEST)
    target_link_libraries(${name} PRIVATE testcommon ${T_LIBS})
    if(COVERAGE)
        foreach(unit ${T_UNITS})
            if(unit MATCHES "\\.cpp$")
                set_property(SOURCE ${unit} TARGET_DIRECTORY ${name} APPEND PROPERTY COMPILE_OPTIONS --coverage -O0 -g)
            endif()
        endforeach()
        target_link_options(${name} PRIVATE --coverage)
    endif()
    # results on stdout and as JUnit XML (SonarQube's cxx plugin imports it as the test count)
    add_test(NAME ${name} COMMAND ${name} -o -,txt -o ${CMAKE_BINARY_DIR}/junit/${name}.xml,junitxml)
    set_tests_properties(${name} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 120)
endfunction()

launcher_test(tst_bluetoothagent
    SOURCES tst_bluetoothagent.cpp
    UNITS ${LIPSTICK}/bluetoothagent.cpp ${LIPSTICK}/bluetoothagent.h
    INCLUDES ${LIPSTICK})

launcher_test(tst_pulseaudiocontrol
    SOURCES tst_pulseaudiocontrol.cpp
    UNITS ${LIPSTICK}/volume/pulseaudiocontrol.cpp ${LIPSTICK}/volume/pulseaudiocontrol.h
    INCLUDES ${LIPSTICK}/volume
    LIBS PkgConfig::DBUSGLIB)

set(NOTIFICATION_FAKES
    fakes/fakenotificationmanager.cpp fakes/fakenotificationmanager.h
    ${LIPSTICK}/notifications/notificationmanager.h
    ${LIPSTICK}/notifications/lipsticknotification.cpp ${LIPSTICK}/notifications/lipsticknotification.h)

launcher_test(tst_notificationfeedbackplayer
    SOURCES tst_notificationfeedbackplayer.cpp ${NOTIFICATION_FAKES}
    UNITS ${LIPSTICK}/notifications/notificationfeedbackplayer.cpp ${LIPSTICK}/notifications/notificationfeedbackplayer.h
    INCLUDES ${LIPSTICK}/notifications ${LIPSTICK}
    LIBS Qt6::Gui)

launcher_test(tst_notificationpreviewpresenter
    SOURCES tst_notificationpreviewpresenter.cpp ${NOTIFICATION_FAKES}
    UNITS ${LIPSTICK}/notifications/notificationpreviewpresenter.cpp ${LIPSTICK}/notifications/notificationpreviewpresenter.h
          ${LIPSTICK}/notifications/notificationfeedbackplayer.cpp ${LIPSTICK}/notifications/notificationfeedbackplayer.h
    INCLUDES ${LIPSTICK}/notifications ${LIPSTICK}
    LIBS Qt6::Gui)

launcher_test(tst_firstrun
    SOURCES tst_firstrun.cpp
    UNITS ${REPO}/src/firstrun.cpp ${REPO}/src/firstrun.h
    INCLUDES ${REPO}/src)
