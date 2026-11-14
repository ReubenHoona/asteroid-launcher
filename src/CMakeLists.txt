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
	ongoingregistry.cpp
	huboffload.cpp
	offbody.cpp
	facepreviews.cpp
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
	ongoingregistry.h
	huboffload.h
	offbody.h
	facepreviews.h
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
	qml/system/FindPhone.qml
	qml/system/PhoneAway.qml
	qml/system/SmartLinks.qml
	qml/system/MediaAutoLaunch.qml
	qml/system/GoalCelebration.qml
	qml/system/goals.js
	qml/system/VolumePopup.qml
	qml/system/LiveUpdate.qml
	qml/system/liveupdate.js
	qml/system/ThermalUi.qml
	qml/system/thermal.js
	qml/system/smartlinks.js
	qml/misc/desktop.js
	qml/misc/tray.js
	qml/misc/pager.js
	qml/misc/AppDrawer.qml
	qml/misc/Recents.qml
	qml/misc/recents.js
	qml/misc/FacePicker.qml
	qml/misc/FaceAddList.qml
	qml/misc/FaceFavourites.qml
	qml/misc/FaceStyle.qml
	qml/misc/CurvedTopText.qml
	qml/misc/RoundMask.qml
	qml/misc/facepicker.js
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
	qml/notifications/NotificationActionsPage.qml
	qml/notifications/NotificationRemote.qml
	qml/notifications/NotificationInputButton.qml
	qml/notifications/NotificationPhoneIcon.qml
	qml/notifications/NotificationProgress.qml
	qml/notifications/NotificationButton.qml
	qml/notifications/NotificationIndicator.qml
	qml/notifications/NotificationView.qml
	qml/notifications/NotificationsPanel.qml
	qml/notifications/NotificationPreview.qml
	qml/notifications/Glanceable.qml
	qml/notifications/HunBubble.qml
	qml/notifications/HeadsUpDetail.qml
	qml/notifications/headsup.js
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
	qml/firstrun/FirstRunConfig.qml
	qml/firstrun/SetupCharge.qml
	qml/firstrun/SetupCheck.qml
	qml/firstrun/SetupCode.qml
	qml/firstrun/SetupComplete.qml
	qml/firstrun/SetupConnecting.qml
	qml/firstrun/SetupDate.qml
	qml/firstrun/SetupFirst.qml
	qml/firstrun/SetupGps.qml
	qml/firstrun/SetupHelp.qml
	qml/firstrun/SetupInstructions.qml
	qml/firstrun/SetupList.qml
	qml/firstrun/SetupTime.qml
	qml/firstrun/Tutorial.qml
	qml/firstrun/TutorialHint.qml
	qml/firstrun/setup.js
	qml/firstrun/tutorial.js
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
	qml/charging/charging.js
	qml/charging/Bolt.qml
	qml/charging/ChargingScreen.qml
	qml/charging/ChargerProblem.qml
	qml/home/HomeOverlays.qml
	qml/home/StatusSlot.qml
	qml/home/ambient.js
	qml/home/status.js
	qml/home/unread.js
	qml/home/ongoing.js
	qml/home/StatusSources.qml
	qml/home/FaceStatusIcon.qml
	qml/home/LiveSpace.qml
	qml/home/OngoingFeed.qml
	qml/home/MediaOngoing.qml
	qml/home/LiveChips.qml
	qml/home/LiveMenu.qml
	qml/compositor/AmbientLite.qml
	qml/compositor/BurnInMask.qml
	qml/system/PowerMenu.qml
	qml/system/TouchLock.qml
	qml/system/Sos.qml
	qml/system/CrashDialog.qml
	qml/system/AppErrors.qml
	qml/system/ScreenshotOverlay.qml
	qml/system/system.js
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
set_source_files_properties(qml/system/FindPhone.qml                 PROPERTIES QT_RESOURCE_ALIAS system/FindPhone.qml)
set_source_files_properties(qml/system/PhoneAway.qml                 PROPERTIES QT_RESOURCE_ALIAS system/PhoneAway.qml)
set_source_files_properties(qml/system/SmartLinks.qml                PROPERTIES QT_RESOURCE_ALIAS system/SmartLinks.qml)
set_source_files_properties(qml/system/MediaAutoLaunch.qml           PROPERTIES QT_RESOURCE_ALIAS system/MediaAutoLaunch.qml)
set_source_files_properties(qml/system/GoalCelebration.qml           PROPERTIES QT_RESOURCE_ALIAS system/GoalCelebration.qml)
set_source_files_properties(qml/system/goals.js                      PROPERTIES QT_RESOURCE_ALIAS system/goals.js)
set_source_files_properties(qml/system/VolumePopup.qml               PROPERTIES QT_RESOURCE_ALIAS system/VolumePopup.qml)
set_source_files_properties(qml/system/LiveUpdate.qml                PROPERTIES QT_RESOURCE_ALIAS system/LiveUpdate.qml)
set_source_files_properties(qml/system/liveupdate.js                 PROPERTIES QT_RESOURCE_ALIAS system/liveupdate.js)
set_source_files_properties(qml/system/ThermalUi.qml                 PROPERTIES QT_RESOURCE_ALIAS system/ThermalUi.qml)
set_source_files_properties(qml/system/thermal.js                    PROPERTIES QT_RESOURCE_ALIAS system/thermal.js)
set_source_files_properties(qml/system/smartlinks.js                 PROPERTIES QT_RESOURCE_ALIAS system/smartlinks.js)
set_source_files_properties(qml/misc/desktop.js                      PROPERTIES QT_RESOURCE_ALIAS desktop.js)
set_source_files_properties(qml/firstrun/FirstRunConfig.qml         PROPERTIES QT_RESOURCE_ALIAS firstrun/FirstRunConfig.qml)
set_source_files_properties(qml/firstrun/SetupCharge.qml            PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupCharge.qml)
set_source_files_properties(qml/firstrun/SetupCheck.qml             PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupCheck.qml)
set_source_files_properties(qml/firstrun/SetupCode.qml              PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupCode.qml)
set_source_files_properties(qml/firstrun/SetupComplete.qml          PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupComplete.qml)
set_source_files_properties(qml/firstrun/SetupConnecting.qml        PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupConnecting.qml)
set_source_files_properties(qml/firstrun/SetupDate.qml              PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupDate.qml)
set_source_files_properties(qml/firstrun/SetupFirst.qml             PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupFirst.qml)
set_source_files_properties(qml/firstrun/SetupGps.qml               PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupGps.qml)
set_source_files_properties(qml/firstrun/SetupHelp.qml              PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupHelp.qml)
set_source_files_properties(qml/firstrun/SetupInstructions.qml      PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupInstructions.qml)
set_source_files_properties(qml/firstrun/SetupList.qml              PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupList.qml)
set_source_files_properties(qml/firstrun/SetupTime.qml              PROPERTIES QT_RESOURCE_ALIAS firstrun/SetupTime.qml)
set_source_files_properties(qml/firstrun/Tutorial.qml               PROPERTIES QT_RESOURCE_ALIAS firstrun/Tutorial.qml)
set_source_files_properties(qml/firstrun/TutorialHint.qml           PROPERTIES QT_RESOURCE_ALIAS firstrun/TutorialHint.qml)
set_source_files_properties(qml/firstrun/setup.js                   PROPERTIES QT_RESOURCE_ALIAS firstrun/setup.js)
set_source_files_properties(qml/firstrun/tutorial.js                PROPERTIES QT_RESOURCE_ALIAS firstrun/tutorial.js)
set_source_files_properties(qml/misc/tray.js                         PROPERTIES QT_RESOURCE_ALIAS tray.js)
set_source_files_properties(qml/misc/pager.js                        PROPERTIES QT_RESOURCE_ALIAS pager.js)
set_source_files_properties(qml/misc/AppDrawer.qml                   PROPERTIES QT_RESOURCE_ALIAS AppDrawer.qml)
set_source_files_properties(qml/misc/Recents.qml                     PROPERTIES QT_RESOURCE_ALIAS Recents.qml)
set_source_files_properties(qml/misc/recents.js                      PROPERTIES QT_RESOURCE_ALIAS recents.js)
set_source_files_properties(qml/misc/FacePicker.qml                  PROPERTIES QT_RESOURCE_ALIAS FacePicker.qml)
set_source_files_properties(qml/misc/FaceAddList.qml              PROPERTIES QT_RESOURCE_ALIAS FaceAddList.qml)
set_source_files_properties(qml/misc/FaceFavourites.qml           PROPERTIES QT_RESOURCE_ALIAS FaceFavourites.qml)
set_source_files_properties(qml/misc/FaceStyle.qml                PROPERTIES QT_RESOURCE_ALIAS FaceStyle.qml)
set_source_files_properties(qml/misc/CurvedTopText.qml            PROPERTIES QT_RESOURCE_ALIAS CurvedTopText.qml)
set_source_files_properties(qml/misc/RoundMask.qml                PROPERTIES QT_RESOURCE_ALIAS RoundMask.qml)
set_source_files_properties(qml/misc/facepicker.js                PROPERTIES QT_RESOURCE_ALIAS facepicker.js)
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
set_source_files_properties(qml/notifications/NotificationActionsPage.qml PROPERTIES QT_RESOURCE_ALIAS NotificationActionsPage.qml)
set_source_files_properties(qml/notifications/NotificationRemote.qml PROPERTIES QT_RESOURCE_ALIAS NotificationRemote.qml)
set_source_files_properties(qml/notifications/NotificationInputButton.qml PROPERTIES QT_RESOURCE_ALIAS NotificationInputButton.qml)
set_source_files_properties(qml/notifications/NotificationPhoneIcon.qml PROPERTIES QT_RESOURCE_ALIAS NotificationPhoneIcon.qml)
set_source_files_properties(qml/notifications/NotificationProgress.qml PROPERTIES QT_RESOURCE_ALIAS NotificationProgress.qml)
set_source_files_properties(qml/notifications/NotificationButton.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationButton.qml)
set_source_files_properties(qml/notifications/NotificationIndicator.qml PROPERTIES QT_RESOURCE_ALIAS NotificationIndicator.qml)
set_source_files_properties(qml/notifications/NotificationView.qml      PROPERTIES QT_RESOURCE_ALIAS NotificationView.qml)
set_source_files_properties(qml/notifications/NotificationsPanel.qml    PROPERTIES QT_RESOURCE_ALIAS NotificationsPanel.qml)
set_source_files_properties(qml/notifications/NotificationPreview.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/NotificationPreview.qml)
set_source_files_properties(qml/notifications/Glanceable.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/Glanceable.qml)
set_source_files_properties(qml/notifications/HunBubble.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/HunBubble.qml)
set_source_files_properties(qml/notifications/HeadsUpDetail.qml   PROPERTIES QT_RESOURCE_ALIAS notifications/HeadsUpDetail.qml)
set_source_files_properties(qml/notifications/headsup.js   PROPERTIES QT_RESOURCE_ALIAS notifications/headsup.js)
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
set_source_files_properties(qml/charging/charging.js                      PROPERTIES QT_RESOURCE_ALIAS charging/charging.js)
set_source_files_properties(qml/charging/Bolt.qml                         PROPERTIES QT_RESOURCE_ALIAS charging/Bolt.qml)
set_source_files_properties(qml/charging/ChargingScreen.qml               PROPERTIES QT_RESOURCE_ALIAS charging/ChargingScreen.qml)
set_source_files_properties(qml/charging/ChargerProblem.qml               PROPERTIES QT_RESOURCE_ALIAS charging/ChargerProblem.qml)
set_source_files_properties(qml/home/HomeOverlays.qml                     PROPERTIES QT_RESOURCE_ALIAS home/HomeOverlays.qml)
set_source_files_properties(qml/home/StatusSlot.qml                       PROPERTIES QT_RESOURCE_ALIAS home/StatusSlot.qml)
set_source_files_properties(qml/home/ambient.js                           PROPERTIES QT_RESOURCE_ALIAS home/ambient.js)
set_source_files_properties(qml/home/status.js                    PROPERTIES QT_RESOURCE_ALIAS home/status.js)
set_source_files_properties(qml/home/unread.js                    PROPERTIES QT_RESOURCE_ALIAS home/unread.js)
set_source_files_properties(qml/home/ongoing.js                   PROPERTIES QT_RESOURCE_ALIAS home/ongoing.js)
set_source_files_properties(qml/home/StatusSources.qml            PROPERTIES QT_RESOURCE_ALIAS home/StatusSources.qml)
set_source_files_properties(qml/home/FaceStatusIcon.qml           PROPERTIES QT_RESOURCE_ALIAS home/FaceStatusIcon.qml)
set_source_files_properties(qml/home/LiveSpace.qml                PROPERTIES QT_RESOURCE_ALIAS home/LiveSpace.qml)
set_source_files_properties(qml/home/OngoingFeed.qml              PROPERTIES QT_RESOURCE_ALIAS home/OngoingFeed.qml)
set_source_files_properties(qml/home/MediaOngoing.qml             PROPERTIES QT_RESOURCE_ALIAS home/MediaOngoing.qml)
set_source_files_properties(qml/home/LiveChips.qml                PROPERTIES QT_RESOURCE_ALIAS home/LiveChips.qml)
set_source_files_properties(qml/home/LiveMenu.qml                 PROPERTIES QT_RESOURCE_ALIAS home/LiveMenu.qml)
set_source_files_properties(qml/compositor/AmbientLite.qml                PROPERTIES QT_RESOURCE_ALIAS compositor/AmbientLite.qml)
set_source_files_properties(qml/compositor/BurnInMask.qml                 PROPERTIES QT_RESOURCE_ALIAS compositor/BurnInMask.qml)
set_source_files_properties(qml/system/PowerMenu.qml                PROPERTIES QT_RESOURCE_ALIAS system/PowerMenu.qml)
set_source_files_properties(qml/system/TouchLock.qml                PROPERTIES QT_RESOURCE_ALIAS system/TouchLock.qml)
set_source_files_properties(qml/system/Sos.qml                      PROPERTIES QT_RESOURCE_ALIAS system/Sos.qml)
set_source_files_properties(qml/system/CrashDialog.qml              PROPERTIES QT_RESOURCE_ALIAS system/CrashDialog.qml)
set_source_files_properties(qml/system/AppErrors.qml                PROPERTIES QT_RESOURCE_ALIAS system/AppErrors.qml)
set_source_files_properties(qml/system/ScreenshotOverlay.qml        PROPERTIES QT_RESOURCE_ALIAS system/ScreenshotOverlay.qml)
set_source_files_properties(qml/system/system.js                    PROPERTIES QT_RESOURCE_ALIAS system/system.js)

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
