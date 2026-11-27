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

# The requests to the display offload daemon (lipstick/src/compositor/eosoffloadclient.h, CR-46: boost, mask,
# brightness, ttb) against a fake daemon on a socket of its own: plain C++ and POSIX threads
find_package(Threads REQUIRED)
add_executable(tst_offloadclient tst_offloadclient.cpp)
target_include_directories(tst_offloadclient PRIVATE ../lipstick/src/compositor)
target_link_libraries(tst_offloadclient PRIVATE Threads::Threads)

# An application's keyboard and the crown (lipstick/src/compositor/eoskeyboardopen.h, CR-45), plain C++
add_executable(tst_keyboardopen tst_keyboardopen.cpp)
target_include_directories(tst_keyboardopen PRIVATE ../lipstick/src/compositor)

# The battery notices of the notification server (lipstick/src/notifications/eosbatterypolicy.h) and a lint of
# batterynotifier.cpp (no keepalive wake-up): plain C++
add_executable(tst_batterypolicy tst_batterypolicy.cpp)
target_include_directories(tst_batterypolicy PRIVATE ../lipstick/src/notifications)
target_compile_definitions(tst_batterypolicy PRIVATE NOTIFIER_SRC="${CMAKE_CURRENT_SOURCE_DIR}/../lipstick/src/notifications")

# The notification server in Bedtime and Theater (lipstick/src/notifications/eosquietpolicy.h), plain C++
add_executable(tst_quietpolicy tst_quietpolicy.cpp)
target_include_directories(tst_quietpolicy PRIVATE ../lipstick/src/notifications)

# M4 WO-12: what a notification's x-asteroid-category asks of the server (lipstick/src/notifications/eoscategory.h:
# the heart rate alert's category alarm, one id, full screen) and a lint of where the server uses it, plain C++
add_executable(tst_eoscategory tst_eoscategory.cpp)
target_include_directories(tst_eoscategory PRIVATE ../lipstick/src/notifications)
target_compile_definitions(tst_eoscategory PRIVATE NOTIFIER_SRC="${CMAKE_CURRENT_SOURCE_DIR}/../lipstick/src/notifications")

# The app notification switches (lipstick/src/notifications/eosdisabledapps.h, CR-18) and a lint of where the
# notification server, the launcher and the battery notices use them: plain C++
add_executable(tst_disabledapps tst_disabledapps.cpp)
target_include_directories(tst_disabledapps PRIVATE ../lipstick/src/notifications)
target_compile_definitions(tst_disabledapps PRIVATE NOTIFIER_SRC="${CMAKE_CURRENT_SOURCE_DIR}/../lipstick/src/notifications"
	SRC_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/..")

# The digits the sensor hub's atlases draw (src/eoshubdigits.h), Qt Core only
add_executable(tst_hubdigits tst_hubdigits.cpp)
target_include_directories(tst_hubdigits PRIVATE ../src)
target_link_libraries(tst_hubdigits PRIVATE Qt6::Core)

# The off-body source (src/offbody.h) against a fake service on a private bus:
#   dbus-run-session -- ./tst_offbody
add_executable(tst_offbody tst_offbody.cpp ../src/offbody.cpp ../src/offbody.h)
set_target_properties(tst_offbody PROPERTIES AUTOMOC ON)
target_include_directories(tst_offbody PRIVATE ../src stubs)
target_link_libraries(tst_offbody PRIVATE Qt6::Core Qt6::DBus)

# The screen lock: the credential store, the service and the root helper eos-lockd as a second process of the test
# (src/eoslock.h, lockservice.*, lockbackend.h, lockhelper.*), on a private bus:
#   dbus-run-session -- ./tst_lock
add_executable(tst_lock tst_lock.cpp ../src/lockservice.cpp ../src/lockservice.h ../src/lockbackend.h
	../src/lockhelper.cpp ../src/lockhelper.h ../src/eoslock.h)
set_target_properties(tst_lock PROPERTIES AUTOMOC ON)
target_include_directories(tst_lock PRIVATE ../src)
target_link_libraries(tst_lock PRIVATE Qt6::Core Qt6::DBus)

# The multi-tap recognizer and the touch observer (src/eostouch.h, src/touchobserver.*) on synthetic touch streams:
#   ./tst_touch
add_executable(tst_touch tst_touch.cpp ../src/touchobserver.cpp ../src/touchobserver.h ../src/eostouch.h)
set_target_properties(tst_touch PROPERTIES AUTOMOC ON)
target_include_directories(tst_touch PRIVATE ../src)
target_link_libraries(tst_touch PRIVATE Qt6::Core Qt6::Gui)

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

# The call state service (src/callstate.h, CR-03 and CR-09) on a private bus, with a stand-in for mlite's MDConfItem
# (tests/stubs/MDConfItem):
#   dbus-run-session -- ./tst_callstate
add_executable(tst_callstate tst_callstate.cpp ../src/callstate.cpp ../src/callstate.h)
set_target_properties(tst_callstate PROPERTIES AUTOMOC ON)
target_include_directories(tst_callstate PRIVATE ../src stubs)
target_link_libraries(tst_callstate PRIVATE Qt6::Core Qt6::DBus)

# The launcher's session bus surface by the name org.asteroidos.launcher (CR-01 to CR-06): every exported object
# called and introspected by the name on a private bus, and a lint of the name's registration in lipstick:
#   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS ./tst_launcherbus'
add_executable(tst_launcherbus tst_launcherbus.cpp ../src/keyclaims.cpp ../src/keyclaims.h ../src/ongoingregistry.cpp
	../src/ongoingregistry.h ../src/callstate.cpp ../src/callstate.h ../src/assistantkey.cpp ../src/assistantkey.h
	../src/lockservice.cpp ../src/lockservice.h ../src/lockhelper.cpp ../src/lockhelper.h ../src/lockbackend.h ../src/eoslock.h)
set_target_properties(tst_launcherbus PROPERTIES AUTOMOC ON)
target_include_directories(tst_launcherbus PRIVATE ../src ../lipstick/src/notifications stubs)
target_compile_definitions(tst_launcherbus PRIVATE SRC_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/..")
target_link_libraries(tst_launcherbus PRIVATE Qt6::Core Qt6::DBus)

# The ongoing activity registry (src/ongoingregistry.h, lipstick/src/notifications/eosongoing.h): the rules and the
# table, and the bus object on a private bus:
#   dbus-run-session -- ./tst_ongoing
add_executable(tst_ongoing tst_ongoing.cpp ../src/ongoingregistry.cpp ../src/ongoingregistry.h)
set_target_properties(tst_ongoing PROPERTIES AUTOMOC ON)
target_include_directories(tst_ongoing PRIVATE ../src ../lipstick/src/notifications)
target_link_libraries(tst_ongoing PRIVATE Qt6::Core Qt6::DBus)

# The cached previews of the face picker (src/facepreviews.h), Qt Core only
add_executable(tst_facepreviews tst_facepreviews.cpp ../src/facepreviews.cpp ../src/facepreviews.h)
set_target_properties(tst_facepreviews PROPERTIES AUTOMOC ON)
target_include_directories(tst_facepreviews PRIVATE ../src)
target_link_libraries(tst_facepreviews PRIVATE Qt6::Core)

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

# The app start trace (lipstick/src/utilities/eosappstart.h), Qt Core only
add_executable(tst_appstart tst_appstart.cpp ../lipstick/src/utilities/eosappstart.h)
target_include_directories(tst_appstart PRIVATE ../lipstick/src/utilities)
target_link_libraries(tst_appstart PRIVATE Qt6::Core)

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

# The alert rules (lipstick/src/notifications/eosalertpolicy.h): On wrist raise, the 10 s window, the 2 s
# vibration limit, the queue of 5, auto-resume, plain C++
add_executable(tst_alertpolicy tst_alertpolicy.cpp)
target_include_directories(tst_alertpolicy PRIVATE ../lipstick/src/notifications)

# The Bluetooth pairing rules (lipstick/src/eosbluetooth.h): the phone class, the name without the address,
# the silent service answer, plain C++
add_executable(tst_bluetooth tst_bluetooth.cpp)
target_include_directories(tst_bluetooth PRIVATE ../lipstick/src)

# The BlueZ agent (lipstick/src/bluetoothagent.cpp) against a fake BlueZ on a private bus:
#   dbus-run-session -- sh -c 'DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS ./tst_btagent_dbus'
add_executable(tst_btagent_dbus tst_btagent_dbus.cpp ../lipstick/src/bluetoothagent.cpp ../lipstick/src/bluetoothagent.h)
set_target_properties(tst_btagent_dbus PROPERTIES AUTOMOC ON)
target_include_directories(tst_btagent_dbus PRIVATE ../lipstick/src)
target_link_libraries(tst_btagent_dbus PRIVATE Qt6::Core Qt6::DBus)

# HealthLog window mode (src/healthlog.h): the Daily heart rate tile reads 2 hours in 3 minute means, Qt Core only
add_executable(tst_healthlog tst_healthlog.cpp ../src/healthlog.cpp ../src/healthlog.h)
set_target_properties(tst_healthlog PROPERTIES AUTOMOC ON)
target_include_directories(tst_healthlog PRIVATE ../src)
target_link_libraries(tst_healthlog PRIVATE Qt6::Core)

# The wrist and crown setting (W3-launcher-wrist): the rules (lipstick/src/eoswrist.h), WristOrientation with the sensor hub
# call against a fake sensorfwd and the crown's event filter (src/wristorientation.*), on a private bus:
#   dbus-run-session -- ./tst_wrist
add_executable(tst_wrist tst_wrist.cpp ../src/wristorientation.cpp ../src/wristorientation.h)
set_target_properties(tst_wrist PROPERTIES AUTOMOC ON)
target_include_directories(tst_wrist PRIVATE ../src ../lipstick/src)
target_link_libraries(tst_wrist PRIVATE Qt6::Core Qt6::Gui Qt6::DBus)

# The hub's always-on layout under the wrist flip (src/eoshubflip.h): the scene transform, the turned sprite's place and cells
add_executable(tst_hubflip tst_hubflip.cpp)
target_include_directories(tst_hubflip PRIVATE ../src)
target_link_libraries(tst_hubflip PRIVATE Qt6::Gui)

# HubOffload::build for the Concentric face (src/watchfaces/027-concentric.qml): the minutes dial as sprites on 60 fixed
# slots drawn over black only (the covers and the still short ticks in the background, cut out of the cells), the 12 h
# hour with its leading zero (huboffload.cpp buildDial, fitDial, eosHubZeroPad). The real face file (it needs the
# image's org.asteroid.controls for Motion) in software Qt Quick, the compositor stand-in:
#   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./tst_huboffload_dial
add_executable(tst_huboffload_dial tst_huboffload_dial.cpp ../src/huboffload.cpp ../src/huboffload.h ../src/eoslayout.c)
set_target_properties(tst_huboffload_dial PROPERTIES AUTOMOC ON)
target_include_directories(tst_huboffload_dial BEFORE PRIVATE stubs ../src)
target_compile_definitions(tst_huboffload_dial PRIVATE SRC_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/..")
target_link_libraries(tst_huboffload_dial PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml)

# HubOffload::build with the digit items under the compositor's 180 degree root turn (huboffload.cpp, eoslayout.c) in a window
# of software Qt Quick, with a stand-in for the lipstick compositor that only takes the layout (tests/stubs/lipstickcompositor.h):
#   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ./tst_huboffload_flip
add_executable(tst_huboffload_flip tst_huboffload_flip.cpp ../src/huboffload.cpp ../src/huboffload.h ../src/eoslayout.c)
set_target_properties(tst_huboffload_flip PROPERTIES AUTOMOC ON)
target_include_directories(tst_huboffload_flip BEFORE PRIVATE stubs ../src)
target_link_libraries(tst_huboffload_flip PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::Qml)

# The app icon keys of a .desktop file (src/applauncherbackground.*, D60-26): the disc, X-Eos-Glyph-Color and
# The hub layout encoder's functions, rotation groups and health metric properties (R5 A-05, K-03; src/eoslayout.c);
# EL_PROBE_DIR=dir also writes the on-watch probe layouts. No Qt.
add_executable(tst_eoslayout tst_eoslayout.cpp ../src/eoslayout.c ../src/eoslayout.h)
target_include_directories(tst_eoslayout PRIVATE ../src)

# The World clock's time zones (A-13, src/worldzones.h): zone.tab regions and codes, offsets with summer time; Qt Core
add_executable(tst_worldzones tst_worldzones.cpp ../src/worldzones.cpp ../src/worldzones.h)
set_target_properties(tst_worldzones PROPERTIES AUTOMOC ON)
target_include_directories(tst_worldzones PRIVATE ../src)
target_link_libraries(tst_worldzones PRIVATE Qt6::Core)

# X-Eos-Own-Icon on temporary files; Qt Core and Gui, no display
add_executable(tst_launchericons tst_launchericons.cpp ../src/applauncherbackground.cpp ../src/applauncherbackground.h)
set_target_properties(tst_launchericons PROPERTIES AUTOMOC ON)
target_include_directories(tst_launchericons PRIVATE ../src)
target_link_libraries(tst_launchericons PRIVATE Qt6::Core Qt6::Gui)
