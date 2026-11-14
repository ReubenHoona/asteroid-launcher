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

# The digits the sensor hub's atlases draw (src/eoshubdigits.h), Qt Core only
add_executable(tst_hubdigits tst_hubdigits.cpp)
target_include_directories(tst_hubdigits PRIVATE ../src)
target_link_libraries(tst_hubdigits PRIVATE Qt6::Core)

# The off-body source (src/offbody.h) against a fake service on a private bus:
#   dbus-run-session -- ./tst_offbody
add_executable(tst_offbody tst_offbody.cpp ../src/offbody.cpp ../src/offbody.h)
set_target_properties(tst_offbody PROPERTIES AUTOMOC ON)
target_include_directories(tst_offbody PRIVATE ../src)
target_link_libraries(tst_offbody PRIVATE Qt6::Core Qt6::DBus)

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

# The order of the Wear app list (lipstick/src/components/launchersortmodel.h), Qt Core only
add_executable(tst_launchersort tst_launchersort.cpp ../lipstick/src/components/launchersortmodel.cpp ../lipstick/src/components/launchersortmodel.h)
set_target_properties(tst_launchersort PROPERTIES AUTOMOC ON)
target_include_directories(tst_launchersort PRIVATE ../lipstick/src/components)
target_link_libraries(tst_launchersort PRIVATE Qt6::Core)

# The crash rule of the app watcher (lipstick/src/components/eosappcrash.h), plain C++
add_executable(tst_appcrash tst_appcrash.cpp)
target_include_directories(tst_appcrash PRIVATE ../lipstick/src/components)

# The unresponsive-app exchange (lipstick/src/compositor/eosanr.h), plain C++
add_executable(tst_anr tst_anr.cpp)
target_include_directories(tst_anr PRIVATE ../lipstick/src/compositor)

# The screenshot file: round mask, name, folder (lipstick/src/eosscreenshot.h), Qt Gui
add_executable(tst_screenshot tst_screenshot.cpp)
target_include_directories(tst_screenshot PRIVATE ../lipstick/src)
target_link_libraries(tst_screenshot PRIVATE Qt6::Gui)

# The low storage rule (lipstick/src/notifications/eosstorage.h) and the shutdown type
# (lipstick/src/eosshutdown.h), plain C++
add_executable(tst_storage tst_storage.cpp)
target_include_directories(tst_storage PRIVATE ../lipstick/src ../lipstick/src/notifications)

# The crown's triggers (src/crownbutton.h) against a fake mce on a private bus:
#   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS tst_crownbutton'
add_executable(tst_crownbutton tst_crownbutton.cpp ../src/crownbutton.cpp ../src/crownbutton.h)
set_target_properties(tst_crownbutton PROPERTIES AUTOMOC ON)
target_include_directories(tst_crownbutton PRIVATE ../src)
target_link_libraries(tst_crownbutton PRIVATE Qt6::Core Qt6::DBus)
