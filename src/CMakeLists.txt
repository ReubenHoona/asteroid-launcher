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
	assistantkey.cpp
	huboffload.cpp
	eoslayout.c)
set(HEADERS
	applauncherbackground.h
	firstrun.h
	gesturefilterarea.h
	applauncher.h
	notificationsnoozer.h
	watchfacereloader.h
	healthlog.h
	crownbutton.h
	aodbrightness.h
	assistantkey.h
	huboffload.h
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
	qml/misc/Splash.qml
	qml/misc/PanelsGrid.qml
	qml/misc/ShutdownScreen.qml
	qml/misc/BluetoothAgent.qml
	qml/misc/desktop.js
	qml/misc/AppDrawer.qml
	qml/misc/FacePicker.qml
	qml/notifications/NotificationStream.qml
	qml/notifications/NotificationCard.qml
	qml/notifications/NotificationText.qml
	qml/notifications/NotificationPicture.qml
	qml/tiles/TileBase.qml
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
	qml/assistant/AssistantOverlay.qml
	qml/assistant/AssistantActions.qml
	qml/assistant/AssistantDots.qml
	qml/notifications/NotificationActions.qml
	qml/notifications/NotificationButton.qml
	qml/notifications/NotificationIndicator.qml
	qml/notifications/NotificationView.qml
	qml/notifications/NotificationsPanel.qml
	qml/notifications/NotificationPreview.qml
	qml/notifications/IncomingCall.qml
	qml/notifications/PhoneAlarm.qml
	qml/quickpanel/QuickPanel.qml
	qml/quickpanel/QuickPanelToggle.qml
	qml/firstrun/FakeAlarmclock.qml
	qml/firstrun/FirstRunConfig.qml
	qml/firstrun/Tutorial.qml
)

set_source_files_properties(qml/MainScreen.qml                       PROPERTIES QT_RESOURCE_ALIAS MainScreen.qml)
set_source_files_properties(qml/today/Today.qml                      PROPERTIES QT_RESOURCE_ALIAS Today.qml)
set_source_files_properties(qml/today/weathericons.js                PROPERTIES QT_RESOURCE_ALIAS weathericons.js)
set_source_files_properties(qml/compositor/compositor.qml            PROPERTIES QT_RESOURCE_ALIAS compositor.qml)
set_source_files_properties(qml/compositor/WindowWrapperBase.qml     PROPERTIES QT_RESOURCE_ALIAS compositor/WindowWrapperBase.qml)
set_source_files_properties(qml/compositor/CircleMaskShader.qml      PROPERTIES QT_RESOURCE_ALIAS compositor/CircleMaskShader.qml)
set_source_files_properties(qml/compositor/LaunchSplash.qml          PROPERTIES QT_RESOURCE_ALIAS compositor/LaunchSplash.qml)
set_source_files_properties(qml/misc/Splash.qml                      PROPERTIES QT_RESOURCE_ALIAS Splash.qml)
set_source_files_properties(qml/misc/PanelsGrid.qml                  PROPERTIES QT_RESOURCE_ALIAS PanelsGrid.qml)
set_source_files_properties(qml/misc/ShutdownScreen.qml              PROPERTIES QT_RESOURCE_ALIAS system/ShutdownScreen.qml)
set_source_files_properties(qml/misc/BluetoothAgent.qml              PROPERTIES QT_RESOURCE_ALIAS connectivity/BluetoothAgent.qml)
set_source_files_properties(qml/misc/desktop.js                      PROPERTIES QT_RESOURCE_ALIAS desktop.js)
set_source_files_properties(qml/misc/AppDrawer.qml                   PROPERTIES QT_RESOURCE_ALIAS AppDrawer.qml)
set_source_files_properties(qml/misc/FacePicker.qml                  PROPERTIES QT_RESOURCE_ALIAS FacePicker.qml)
set_source_files_properties(qml/notifications/NotificationStream.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationStream.qml)
set_source_files_properties(qml/notifications/NotificationCard.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationCard.qml)
set_source_files_properties(qml/notifications/NotificationText.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationText.qml)
set_source_files_properties(qml/notifications/NotificationPicture.qml   PROPERTIES QT_RESOURCE_ALIAS NotificationPicture.qml)
set_source_files_properties(qml/tiles/TileBase.qml                   PROPERTIES QT_RESOURCE_ALIAS tiles/TileBase.qml)
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
set_source_files_properties(qml/assistant/AssistantOverlay.qml       PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantOverlay.qml)
set_source_files_properties(qml/assistant/AssistantActions.qml       PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantActions.qml)
set_source_files_properties(qml/assistant/AssistantDots.qml          PROPERTIES QT_RESOURCE_ALIAS assistant/AssistantDots.qml)
set_source_files_properties(qml/notifications/NotificationActions.qml   PROPERTIES QT_RESOURCE_ALIAS NotificationActions.qml)
set_source_files_properties(qml/notifications/NotificationButton.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationButton.qml)
set_source_files_properties(qml/notifications/NotificationIndicator.qml PROPERTIES QT_RESOURCE_ALIAS NotificationIndicator.qml)
set_source_files_properties(qml/notifications/NotificationView.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationView.qml)
set_source_files_properties(qml/notifications/NotificationsPanel.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationsPanel.qml)
set_source_files_properties(qml/notifications/NotificationPreview.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/NotificationPreview.qml)
set_source_files_properties(qml/notifications/IncomingCall.qml          PROPERTIES QT_RESOURCE_ALIAS IncomingCall.qml)
set_source_files_properties(qml/notifications/PhoneAlarm.qml            PROPERTIES QT_RESOURCE_ALIAS PhoneAlarm.qml)
set_source_files_properties(qml/quickpanel/QuickPanel.qml            PROPERTIES QT_RESOURCE_ALIAS QuickPanel.qml)
set_source_files_properties(qml/quickpanel/QuickPanelToggle.qml      PROPERTIES QT_RESOURCE_ALIAS QuickPanelToggle.qml)
set_source_files_properties(qml/firstrun/FakeAlarmclock.qml          PROPERTIES QT_RESOURCE_ALIAS FakeAlarmclock.qml)
set_source_files_properties(qml/firstrun/FirstRunConfig.qml          PROPERTIES QT_RESOURCE_ALIAS FirstRunConfig.qml)
set_source_files_properties(qml/firstrun/Tutorial.qml                PROPERTIES QT_RESOURCE_ALIAS Tutorial.qml)

asteroid_app_qml_module(asteroid-launcher ${QML_FILES})

qt_add_shaders(
    asteroid-launcher "asteroid-launcher_shaders"
    FILES
        "qml/compositor/circlemaskshader.frag"
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
