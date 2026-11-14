# Tests of the modes engine and the display offload decisions (cmake -DLAUNCHER_TESTS=ON): the rules on a fake
# store (Qt Core only), and the engine against a fake mce on a private bus:
#   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS tst_modes'
add_executable(tst_modescore tst_modescore.cpp ../src/modescore.cpp)
target_include_directories(tst_modescore PRIVATE ../src)
target_link_libraries(tst_modescore PRIVATE Qt6::Core)

add_executable(tst_modes tst_modes.cpp ../src/modes.cpp ../src/modescore.cpp ../src/modes.h)
set_target_properties(tst_modes PROPERTIES AUTOMOC ON)
target_include_directories(tst_modes PRIVATE ../src)
target_link_libraries(tst_modes PRIVATE Qt6::Core Qt6::DBus PkgConfig::mlite6 Timed::Timed)

# The display offload decisions (lipstick/src/compositor/eosoffloadpolicy.h), plain C++
add_executable(tst_offloadpolicy tst_offloadpolicy.cpp)
target_include_directories(tst_offloadpolicy PRIVATE ../lipstick/src/compositor)

# The notification server in Bedtime and Theater (lipstick/src/notifications/eosquietpolicy.h), plain C++
add_executable(tst_quietpolicy tst_quietpolicy.cpp)
target_include_directories(tst_quietpolicy PRIVATE ../lipstick/src/notifications)

# The freezer of hidden applications (lipstick/src/compositor/eosfreezer.h), plain C++
add_executable(tst_freezer tst_freezer.cpp)
target_include_directories(tst_freezer PRIVATE ../lipstick/src/compositor)

# The program name behind a window (lipstick/src/compositor/eosappkey.h), plain C++
add_executable(tst_appkey tst_appkey.cpp)
target_include_directories(tst_appkey PRIVATE ../lipstick/src/compositor)

# Key claims (src/keyclaims.h): the table, and the bus object on a private bus:
#   dbus-run-session -- ./tst_keyclaims
add_executable(tst_keyclaims tst_keyclaims.cpp ../src/keyclaims.cpp ../src/keyclaims.h)
set_target_properties(tst_keyclaims PROPERTIES AUTOMOC ON)
target_include_directories(tst_keyclaims PRIVATE ../src)
target_link_libraries(tst_keyclaims PRIVATE Qt6::Core Qt6::DBus)

# The finger speed of a swipe (src/swipevelocity.h), plain C++
add_executable(tst_swipevelocity tst_swipevelocity.cpp)
target_include_directories(tst_swipevelocity PRIVATE ../src)
