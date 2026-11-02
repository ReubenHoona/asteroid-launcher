# Tests of the modes engine (cmake -DLAUNCHER_TESTS=ON): the rules on a fake
# store (Qt Core only), and the engine against a fake mce on a private bus:
#   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS tst_modes'
add_executable(tst_modescore tst_modescore.cpp ../src/modescore.cpp)
target_include_directories(tst_modescore PRIVATE ../src)
target_link_libraries(tst_modescore PRIVATE Qt6::Core)

add_executable(tst_modes tst_modes.cpp ../src/modes.cpp ../src/modescore.cpp ../src/modes.h)
set_target_properties(tst_modes PROPERTIES AUTOMOC ON)
target_include_directories(tst_modes PRIVATE ../src)
target_link_libraries(tst_modes PRIVATE Qt6::Core Qt6::DBus PkgConfig::mlite6)
