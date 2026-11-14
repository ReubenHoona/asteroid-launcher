set(SRC
	main.cpp
	applauncherbackground.cpp
	firstrun.cpp
	gesturefilterarea.cpp
	applauncher.cpp
	notificationsnoozer.cpp
	watchfacereloader.cpp
	healthlog.cpp
	crownbutton.cpp
	aodbrightness.cpp
	modescore.cpp
	modes.cpp
	assistantkey.cpp
	keyclaims.cpp
	huboffload.cpp
	offbody.cpp
	eoslayout.c)
set(HEADERS
	applauncherbackground.h
	firstrun.h
	gesturefilterarea.h
	swipevelocity.h
	applauncher.h
	notificationsnoozer.h
	watchfacereloader.h
	healthlog.h
	crownbutton.h
	aodbrightness.h
	modescore.h
	modes.h
	assistantkey.h
	keyclaims.h
	huboffload.h
	offbody.h
	eoshubdigits.h
	eoslayout.h)

add_executable(asteroid-launcher ${SRC} ${HEADERS} resources-qml.qrc)

set(QML_FILES
	qml/MainScreen.qml
	qml/today/Today.qml
	qml/today/weathericons.js
	qml/compositor/compositor.qml
	qml/compositor/WindowWrapperBase.qml
	qml/compositor/CircleMaskShader.qml
	qml/compositor/LaunchSplash.qml
	qml/compositor/NightLight.qml
	qml/misc/Splash.qml
	qml/misc/PanelsGrid.qml
	qml/misc/ShutdownScreen.qml
	qml/misc/ModeScreen.qml
	qml/misc/BluetoothAgent.qml
	qml/misc/desktop.js
	qml/misc/tray.js
	qml/misc/pager.js
	qml/misc/AppDrawer.qml
	qml/misc/Recents.qml
	qml/misc/recents.js
	qml/misc/FacePicker.qml
	qml/notifications/NotificationStream.qml
	qml/notifications/NotificationCard.qml
	qml/notifications/NotificationText.qml
	qml/notifications/NotificationPicture.qml
	qml/notifications/NotificationConversation.qml
	qml/notifications/NotificationBlockingMenu.qml
	qml/tiles/TileBase.qml
	qml/tiles/EmptyTile.qml
	qml/tiles/TilesEditor.qml
	qml/tiles/HeartRateTile.qml
	qml/tiles/StepsTile.qml
	qml/tiles/WeatherTile.qml
	qml/tiles/AgendaTile.qml
	qml/tiles/TimerTile.qml
	qml/tiles/MediaTile.qml
	qml/tiles/AssistantTile.qml
	qml/tiles/AlarmTile.qml
	qml/tiles/BatteryTile.qml
	qml/complications/ComplicationSources.qml
	qml/complications/ComplicationView.qml
	qml/complications/AgendaSource.qml
	qml/complications/ClockSource.qml
	qml/complications/MediaSource.qml
	qml/complications/complications.js
	qml/complications/FaceEditor.qml
	qml/assistant/AssistantOverlay.qml
	qml/assistant/AssistantActions.qml
	qml/assistant/AssistantGlow.qml
	qml/assistant/AssistantSpark.qml
	qml/notifications/NotificationActions.qml
	qml/notifications/NotificationButton.qml
	qml/notifications/NotificationIndicator.qml
	qml/notifications/NotificationView.qml
	qml/notifications/NotificationsPanel.qml
	qml/notifications/NotificationPreview.qml
	qml/notifications/IncomingCall.qml
	qml/calls/InCall.qml
	qml/calls/CallAudio.qml
	qml/calls/CallVolumeArc.qml
	qml/calls/CallVolume.qml
	qml/calls/IncomingCallMore.qml
	qml/calls/InCallMore.qml
	qml/calls/InCallKeypad.qml
	qml/notifications/PhoneAlarm.qml
	qml/quickpanel/QuickPanel.qml
	qml/quickpanel/QuickPanelToggle.qml
	qml/quickpanel/ModeDialog.qml
	qml/quickpanel/StatusTray.qml
	qml/quickpanel/qs.js
	qml/firstrun/FakeAlarmclock.qml
	qml/firstrun/FirstRunConfig.qml
	qml/firstrun/Tutorial.qml
	qml/compositor/KeyRouter.qml
	qml/compositor/keymap.js
	qml/compositor/lifecycle.js
	qml/compositor/windowmotion.js
	qml/compositor/AppOpen.qml
	qml/compositor/WatchfaceReveal.qml
	qml/compositor/AppLifecycle.qml
	qml/compositor/WindowTransitions.qml
	qml/compositor/OverlayArbiter.qml
	qml/home/FaceLayer.qml
	qml/home/Trays.qml
	qml/home/TilesRing.qml
	qml/home/TilesIndicator.qml
	qml/home/AmbientController.qml
	qml/home/ChargingController.qml
	qml/home/HomeOverlays.qml
	qml/home/StatusSlot.qml
	qml/home/ambient.js
	qml/compositor/AmbientLite.qml
	qml/compositor/BurnInMask.qml
)

set_source_files_properties(qml/MainScreen.qml                       PROPERTIES QT_RESOURCE_ALIAS MainScreen.qml)
set_source_files_properties(qml/today/Today.qml                      PROPERTIES QT_RESOURCE_ALIAS Today.qml)
set_source_files_properties(qml/today/weathericons.js                PROPERTIES QT_RESOURCE_ALIAS weathericons.js)
set_source_files_properties(qml/compositor/compositor.qml            PROPERTIES QT_RESOURCE_ALIAS compositor.qml)
set_source_files_properties(qml/compositor/WindowWrapperBase.qml     PROPERTIES QT_RESOURCE_ALIAS compositor/WindowWrapperBase.qml)
set_source_files_properties(qml/compositor/CircleMaskShader.qml      PROPERTIES QT_RESOURCE_ALIAS compositor/CircleMaskShader.qml)
set_source_files_properties(qml/compositor/LaunchSplash.qml          PROPERTIES QT_RESOURCE_ALIAS compositor/LaunchSplash.qml)
set_source_files_properties(qml/compositor/NightLight.qml            PROPERTIES QT_RESOURCE_ALIAS compositor/NightLight.qml)
set_source_files_properties(qml/misc/Splash.qml                      PROPERTIES QT_RESOURCE_ALIAS Splash.qml)
set_source_files_properties(qml/misc/PanelsGrid.qml                  PROPERTIES QT_RESOURCE_ALIAS PanelsGrid.qml)
set_source_files_properties(qml/misc/ShutdownScreen.qml              PROPERTIES QT_RESOURCE_ALIAS system/ShutdownScreen.qml)
set_source_files_properties(qml/misc/ModeScreen.qml                  PROPERTIES QT_RESOURCE_ALIAS system/ModeScreen.qml)
set_source_files_properties(qml/misc/BluetoothAgent.qml              PROPERTIES QT_RESOURCE_ALIAS connectivity/BluetoothAgent.qml)
set_source_files_properties(qml/misc/desktop.js                      PROPERTIES QT_RESOURCE_ALIAS desktop.js)
set_source_files_properties(qml/misc/tray.js                         PROPERTIES QT_RESOURCE_ALIAS tray.js)
set_source_files_properties(qml/misc/pager.js                        PROPERTIES QT_RESOURCE_ALIAS pager.js)
set_source_files_properties(qml/misc/AppDrawer.qml                   PROPERTIES QT_RESOURCE_ALIAS AppDrawer.qml)
set_source_files_properties(qml/misc/Recents.qml                     PROPERTIES QT_RESOURCE_ALIAS Recents.qml)
set_source_files_properties(qml/misc/recents.js                      PROPERTIES QT_RESOURCE_ALIAS recents.js)
set_source_files_properties(qml/misc/FacePicker.qml                  PROPERTIES QT_RESOURCE_ALIAS FacePicker.qml)
set_source_files_properties(qml/notifications/NotificationStream.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationStream.qml)
set_source_files_properties(qml/notifications/NotificationCard.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationCard.qml)
set_source_files_properties(qml/notifications/NotificationText.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationText.qml)
set_source_files_properties(qml/notifications/NotificationPicture.qml   PROPERTIES QT_RESOURCE_ALIAS NotificationPicture.qml)
set_source_files_properties(qml/notifications/NotificationConversation.qml PROPERTIES QT_RESOURCE_ALIAS NotificationConversation.qml)
set_source_files_properties(qml/notifications/NotificationBlockingMenu.qml PROPERTIES QT_RESOURCE_ALIAS NotificationBlockingMenu.qml)
set_source_files_properties(qml/tiles/TileBase.qml                   PROPERTIES QT_RESOURCE_ALIAS tiles/TileBase.qml)
set_source_files_properties(qml/tiles/EmptyTile.qml                  PROPERTIES QT_RESOURCE_ALIAS tiles/EmptyTile.qml)
set_source_files_properties(qml/tiles/TilesEditor.qml                PROPERTIES QT_RESOURCE_ALIAS tiles/TilesEditor.qml)
set_source_files_properties(qml/tiles/HeartRateTile.qml              PROPERTIES QT_RESOURCE_ALIAS tiles/HeartRateTile.qml)
set_source_files_properties(qml/tiles/StepsTile.qml                  PROPERTIES QT_RESOURCE_ALIAS tiles/StepsTile.qml)
set_source_files_properties(qml/tiles/WeatherTile.qml                PROPERTIES QT_RESOURCE_ALIAS tiles/WeatherTile.qml)
set_source_files_properties(qml/tiles/AgendaTile.qml                 PROPERTIES QT_RESOURCE_ALIAS tiles/AgendaTile.qml)
set_source_files_properties(qml/tiles/TimerTile.qml                  PROPERTIES QT_RESOURCE_ALIAS tiles/TimerTile.qml)
set_source_files_properties(qml/tiles/MediaTile.qml                  PROPERTIES QT_RESOURCE_ALIAS tiles/MediaTile.qml)
set_source_files_properties(qml/tiles/AssistantTile.qml              PROPERTIES QT_RESOURCE_ALIAS tiles/AssistantTile.qml)
set_source_files_properties(qml/tiles/AlarmTile.qml                  PROPERTIES QT_RESOURCE_ALIAS tiles/AlarmTile.qml)
set_source_files_properties(qml/tiles/BatteryTile.qml                PROPERTIES QT_RESOURCE_ALIAS tiles/BatteryTile.qml)
set_source_files_properties(qml/complications/ComplicationSources.qml PROPERTIES QT_RESOURCE_ALIAS complications/ComplicationSources.qml)
set_source_files_properties(qml/complications/ComplicationView.qml   PROPERTIES QT_RESOURCE_ALIAS complications/ComplicationView.qml)
set_source_files_properties(qml/complications/AgendaSource.qml       PROPERTIES QT_RESOURCE_ALIAS complications/AgendaSource.qml)
set_source_files_properties(qml/complications/ClockSource.qml        PROPERTIES QT_RESOURCE_ALIAS complications/ClockSource.qml)
set_source_files_properties(qml/complications/MediaSource.qml        PROPERTIES QT_RESOURCE_ALIAS complications/MediaSource.qml)
set_source_files_properties(qml/complications/complications.js       PROPERTIES QT_RESOURCE_ALIAS complications/complications.js)
set_source_files_properties(qml/complications/FaceEditor.qml         PROPERTIES QT_RESOURCE_ALIAS complications/FaceEditor.qml)
set_source_files_properties(qml/assistant/AssistantOverlay.qml       PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantOverlay.qml)
set_source_files_properties(qml/assistant/AssistantActions.qml       PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantActions.qml)
set_source_files_properties(qml/assistant/AssistantGlow.qml          PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantGlow.qml)
set_source_files_properties(qml/assistant/AssistantSpark.qml         PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantSpark.qml)
set_source_files_properties(qml/notifications/NotificationActions.qml   PROPERTIES QT_RESOURCE_ALIAS NotificationActions.qml)
set_source_files_properties(qml/notifications/NotificationButton.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationButton.qml)
set_source_files_properties(qml/notifications/NotificationIndicator.qml PROPERTIES QT_RESOURCE_ALIAS NotificationIndicator.qml)
set_source_files_properties(qml/notifications/NotificationView.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationView.qml)
set_source_files_properties(qml/notifications/NotificationsPanel.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationsPanel.qml)
set_source_files_properties(qml/notifications/NotificationPreview.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/NotificationPreview.qml)
set_source_files_properties(qml/notifications/IncomingCall.qml          PROPERTIES QT_RESOURCE_ALIAS IncomingCall.qml)
set_source_files_properties(qml/calls/InCall.qml                   PROPERTIES QT_RESOURCE_ALIAS InCall.qml)
set_source_files_properties(qml/calls/CallAudio.qml                PROPERTIES QT_RESOURCE_ALIAS CallAudio.qml)
set_source_files_properties(qml/calls/CallVolumeArc.qml            PROPERTIES QT_RESOURCE_ALIAS CallVolumeArc.qml)
set_source_files_properties(qml/calls/CallVolume.qml               PROPERTIES QT_RESOURCE_ALIAS CallVolume.qml)
set_source_files_properties(qml/calls/IncomingCallMore.qml         PROPERTIES QT_RESOURCE_ALIAS IncomingCallMore.qml)
set_source_files_properties(qml/calls/InCallMore.qml               PROPERTIES QT_RESOURCE_ALIAS InCallMore.qml)
set_source_files_properties(qml/calls/InCallKeypad.qml             PROPERTIES QT_RESOURCE_ALIAS InCallKeypad.qml)
set_source_files_properties(qml/notifications/PhoneAlarm.qml            PROPERTIES QT_RESOURCE_ALIAS PhoneAlarm.qml)
set_source_files_properties(qml/quickpanel/QuickPanel.qml            PROPERTIES QT_RESOURCE_ALIAS QuickPanel.qml)
set_source_files_properties(qml/quickpanel/QuickPanelToggle.qml      PROPERTIES QT_RESOURCE_ALIAS QuickPanelToggle.qml)
set_source_files_properties(qml/quickpanel/ModeDialog.qml            PROPERTIES QT_RESOURCE_ALIAS ModeDialog.qml)
set_source_files_properties(qml/quickpanel/StatusTray.qml            PROPERTIES QT_RESOURCE_ALIAS StatusTray.qml)
set_source_files_properties(qml/quickpanel/qs.js                     PROPERTIES QT_RESOURCE_ALIAS qs.js)
set_source_files_properties(qml/firstrun/FakeAlarmclock.qml          PROPERTIES QT_RESOURCE_ALIAS FakeAlarmclock.qml)
set_source_files_properties(qml/firstrun/FirstRunConfig.qml          PROPERTIES QT_RESOURCE_ALIAS FirstRunConfig.qml)
set_source_files_properties(qml/firstrun/Tutorial.qml                PROPERTIES QT_RESOURCE_ALIAS Tutorial.qml)
set_source_files_properties(qml/compositor/KeyRouter.qml                  PROPERTIES QT_RESOURCE_ALIAS compositor/KeyRouter.qml)
set_source_files_properties(qml/compositor/keymap.js                      PROPERTIES QT_RESOURCE_ALIAS compositor/keymap.js)
set_source_files_properties(qml/compositor/lifecycle.js                   PROPERTIES QT_RESOURCE_ALIAS compositor/lifecycle.js)
set_source_files_properties(qml/compositor/windowmotion.js                PROPERTIES QT_RESOURCE_ALIAS compositor/windowmotion.js)
set_source_files_properties(qml/compositor/AppOpen.qml                    PROPERTIES QT_RESOURCE_ALIAS compositor/AppOpen.qml)
set_source_files_properties(qml/compositor/WatchfaceReveal.qml            PROPERTIES QT_RESOURCE_ALIAS compositor/WatchfaceReveal.qml)
set_source_files_properties(qml/compositor/AppLifecycle.qml               PROPERTIES QT_RESOURCE_ALIAS compositor/AppLifecycle.qml)
set_source_files_properties(qml/compositor/WindowTransitions.qml          PROPERTIES QT_RESOURCE_ALIAS compositor/WindowTransitions.qml)
set_source_files_properties(qml/compositor/OverlayArbiter.qml             PROPERTIES QT_RESOURCE_ALIAS compositor/OverlayArbiter.qml)
set_source_files_properties(qml/home/FaceLayer.qml                        PROPERTIES QT_RESOURCE_ALIAS home/FaceLayer.qml)
set_source_files_properties(qml/home/Trays.qml                            PROPERTIES QT_RESOURCE_ALIAS home/Trays.qml)
set_source_files_properties(qml/home/TilesRing.qml                        PROPERTIES QT_RESOURCE_ALIAS home/TilesRing.qml)
set_source_files_properties(qml/home/TilesIndicator.qml                   PROPERTIES QT_RESOURCE_ALIAS home/TilesIndicator.qml)
set_source_files_properties(qml/home/AmbientController.qml                PROPERTIES QT_RESOURCE_ALIAS home/AmbientController.qml)
set_source_files_properties(qml/home/ChargingController.qml               PROPERTIES QT_RESOURCE_ALIAS home/ChargingController.qml)
set_source_files_properties(qml/home/HomeOverlays.qml                     PROPERTIES QT_RESOURCE_ALIAS home/HomeOverlays.qml)
set_source_files_properties(qml/home/StatusSlot.qml                       PROPERTIES QT_RESOURCE_ALIAS home/StatusSlot.qml)
set_source_files_properties(qml/home/ambient.js                           PROPERTIES QT_RESOURCE_ALIAS home/ambient.js)
set_source_files_properties(qml/compositor/AmbientLite.qml                PROPERTIES QT_RESOURCE_ALIAS compositor/AmbientLite.qml)
set_source_files_properties(qml/compositor/BurnInMask.qml                 PROPERTIES QT_RESOURCE_ALIAS compositor/BurnInMask.qml)

asteroid_app_qml_module(asteroid-launcher ${QML_FILES})

qt_add_shaders(
    asteroid-launcher "asteroid-launcher_shaders"
    FILES
        "qml/compositor/circlemaskshader.frag"
        "shaders/assistant-glow.frag"
        "shaders/colorfilter.frag"
        "shaders/masked-spartan.frag"
        "shaders/speed-dial-mask.frag"
)

target_link_libraries(
	asteroid-launcher
	PRIVATE
		Qt6::Quick
		Qt6::WaylandCompositor
		Qt6::DBus
		lipstick
		Timed::Timed
		PkgConfig::mlite6
)

install(
	TARGETS asteroid-launcher
	DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(
	DIRECTORY watchfaces
	DESTINATION ${CMAKE_INSTALL_DATADIR}/asteroid-launcher
)
install(
	DIRECTORY watchfaces-img
	DESTINATION ${CMAKE_INSTALL_DATADIR}/asteroid-launcher
)
install(
	DIRECTORY watchfaces-preview
	DESTINATION ${CMAKE_INSTALL_DATADIR}/asteroid-launcher
)
install(
	DIRECTORY shaders
	DESTINATION ${CMAKE_INSTALL_DATADIR}/asteroid-launcher
)
install(
	DIRECTORY applauncher
	DESTINATION ${CMAKE_INSTALL_DATADIR}/asteroid-launcher
)
# the launcher's own entries of the app list (no program: MainScreen.launchApp answers them)
install(
	FILES desktop/asteroid-find-my-phone.desktop
	DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
)
