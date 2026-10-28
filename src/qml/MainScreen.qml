/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import Nemo.Mce
import org.nemomobile.lipstick
import org.asteroid.settings
import org.asteroid.controls
import org.asteroid.utils
import org.asteroid.launcher
import "desktop.js" as Desktop
import "tiles"

Item {
    id: desktop
    width: Dims.w(100)
    height: Dims.h(100)
    z: splash.visible ? 10 : 0

    visible: Lipstick.compositor.homeActive || aboutToOpen || aboutToClose || aboutToMinimize
    enabled: visible

    // Requests the active watchface Loader to reload from disk. A signal, so
    // the handler can live in the Loader's own scope.
    signal watchfaceReloadRequested()

    AppLauncherBackground { id: alb }

    property var defaultCenterColor: alb.centerColor("/usr/share/asteroid-launcher/default-colors.desktop")
    property var defaultOuterColor: alb.outerColor("/usr/share/asteroid-launcher/default-colors.desktop")

    property var launcherCenterColor: defaultCenterColor
    property var launcherOuterColor: defaultOuterColor
    property var launcherColorOverride: false

    property var displayAmbient: Lipstick.compositor.displayAmbient

    /* Background gradient colours handed to the wallpaper. While scrolling down
     * to the launcher (normalizedVerOffset in (0,1]) they fade from the default
     * colours towards the launcher's colours; everywhere else, and whenever an
     * app launcher overrides the colours itself, they stay at the defaults.
     * Pure bindings, so they always match the current grid position. */
    function mixColor(a, b, t) {
        return Qt.rgba(a.r*t + b.r*(1-t), a.g*t + b.g*(1-t), a.b*t + b.b*(1-t), a.a*t + b.a*(1-t))
    }
    property var bgCenterColor: (!launcherColorOverride && grid.normalizedVerOffset > 0)
                              ? mixColor(launcherCenterColor, defaultCenterColor, grid.normalizedVerOffset)
                              : defaultCenterColor
    property var bgOuterColor: (!launcherColorOverride && grid.normalizedVerOffset > 0)
                             ? mixColor(launcherOuterColor, defaultOuterColor, grid.normalizedVerOffset)
                             : defaultOuterColor

    /* Wallpaper darkening overlay opacity, expressed as the maximum of two
     * independent, declarative contributions so it can never get stranded the
     * way the old imperative signal handlers could:
     *  - scrollDarken tracks the grid offset (instant, follows the finger).
     *    The launcher page (verOffset > 0) is intentionally not darkened unless
     *    a launcher overrides the background colours.
     *  - ambientDarken is toggled by the ambient signals and fades over 300ms. */
    property real scrollDarken: displayAmbient ? 0.0
                              : (grid.normalizedVerOffset > 0 && !launcherColorOverride) ? 0.0
                              : Math.max(Math.abs(grid.normalizedHorOffset), Math.abs(grid.normalizedVerOffset)) * 0.4
    property real ambientDarken: 0.0
    Behavior on ambientDarken { NumberAnimation { duration: 300 } }

    property var compositor: Lipstick.compositor

    property bool aboutToOpen: false
    property bool aboutToClose: false
    property bool aboutToMinimize: false

    /*
     * The nightstand property is for use by watchfaces to signal them to, for example,
     * enable a visual display of battery charge level, as with a ring around the perimeter
     * of the watch that wouldn't normally be displayed.
     */
    property alias nightstand: nightstandMode.active

    onAboutToCloseChanged: {
        grid.moveTo(0, 0)
        if (aboutToClose)
            closeOverlays()
    }
    onAboutToMinimizeChanged: {
        if (!wearLayout) {
            grid.moveTo(0, 1)
            return
        }
        // Wear OS: back from an app opened from the app list is the list,
        // from anywhere else the watchface
        grid.moveTo(0, 0)
        if (aboutToMinimize && launchedFromDrawer)
            appDrawer.openNow()
    }

    /* The Wear OS home screen (dconf /org/asteroidos/ux/home-layout "wear",
     * the default; "asteroid" for the AsteroidOS one; read at start):
     * watchface in the middle, quick settings above, the notification
     * stream below (swipe up), the tiles to the right (swipe left), the app
     * list over it all on the crown button (or a swipe right) */
    ConfigurationValue {
        id: homeLayout
        key: "/org/asteroidos/ux/home-layout"
        defaultValue: "wear"
    }
    readonly property bool wearLayout: _wearLayout
    property bool _wearLayout: true
    property bool launchedFromDrawer: false

    // the tiles: id -> file and name
    readonly property var tileRegistry: ({
        //% "Heart rate"
        "heartrate": { file: "tiles/HeartRateTile.qml", name: qsTrId("id-tile-heart-rate") },
        //% "Steps"
        "steps": { file: "tiles/StepsTile.qml", name: qsTrId("id-tile-steps") },
        //% "Weather"
        "weather": { file: "tiles/WeatherTile.qml", name: qsTrId("id-tile-weather") },
        //% "Agenda"
        "agenda": { file: "tiles/AgendaTile.qml", name: qsTrId("id-tile-agenda") },
        //% "Timer"
        "timer": { file: "tiles/TimerTile.qml", name: qsTrId("id-tile-timer") },
        //% "Media"
        "media": { file: "tiles/MediaTile.qml", name: qsTrId("id-tile-media") }
    })
    ConfigurationValue {
        id: tilesSetting
        key: "/org/asteroidos/ux/tiles"
        defaultValue: ["weather", "heartrate", "steps", "agenda", "timer", "media"]
        onValueChanged: if (desktop.wearLayout && grid.panels.size > 0) desktop.buildTiles()
    }
    property var builtTiles: []
    readonly property int tileCount: builtTiles.length

    // the tiles from dconf, unknown ids left out, as panels (1..n, 0)
    function buildTiles() {
        var wanted = []
        var list = tilesSetting.value || []
        for (var i = 0; i < list.length; i++)
            if (tileRegistry[list[i]] && wanted.indexOf(list[i]) < 0)
                wanted.push(list[i])
        if (JSON.stringify(wanted) === JSON.stringify(builtTiles))
            return
        var onTiles = grid.currentHorizontalPos > 0
        for (var r = 1; r <= builtTiles.length; r++)
            grid.removePanel(r, 0)
        for (var t = 0; t < wanted.length; t++) {
            var panel = grid.addPanel(t + 1, 0, tilePanel)
            panel.tileFile = tileRegistry[wanted[t]].file
        }
        // drawn once offscreen (first textures, text, shapes made now, not
        // in the first frames of a swipe), then hidden
        grid.hideSoon()
        builtTiles = wanted
        if (onTiles)
            grid.moveTo(Math.min(grid.currentHorizontalPos, wanted.length), 0)
        grid.changeAllowedDirections()
    }

    function openTilesEditor() {
        var names = {}
        for (var k in tileRegistry)
            names[k] = tileRegistry[k].name
        tilesEditor.names = names
        tilesEditor.open(builtTiles)
    }

    function openFacePicker() {
        facePicker.current = watchFaceSource.value
        facePicker.open()
    }

    // the drawer, the face picker and the tiles editor go
    function closeOverlays() {
        appDrawer.closeNow()
        if (facePicker.visible) facePicker.close()
        if (tilesEditor.visible) tilesEditor.close(false)
    }

    /* The crown button on the home screen, as Wear OS: on the watchface it
     * opens the app list; anywhere else (the app list, a tile, the
     * notifications, quick settings) it goes back to the watchface */
    function crownPressed() {
        if (splash.visible)
            return
        if (facePicker.visible || tilesEditor.visible) {
            closeOverlays()
            return
        }
        if (appDrawer.isOpen) {
            appDrawer.close()
            return
        }
        if (grid.currentHorizontalPos !== 0 || grid.currentVerticalPos !== 0) {
            grid.animateTo(0, 0)
            return
        }
        if (wearLayout)
            appDrawer.open()
        else
            grid.animateTo(0, 1)
    }

    /* Launch the app of /usr/share/applications/<name>.desktop the way the
     * launcher does (lipstick's launcher item: booster, splash) */
    function launchByName(name, fromItem) {
        for (var i = 0; i < launcherModel.itemCount; i++) {
            var it = launcherModel.get(i)
            if (it && it.object)
                it = it.object
            if (it && it.filePath && it.filePath.split("/").pop() === name + ".desktop") {
                launchApp(it, fromItem)
                return true
            }
        }
        return false
    }

    /* Launch an application from the launcher. The launch splash grows out
     * of fromItem (the tapped icon; null: the middle of the screen) in the
     * colours of the application and covers the screen until its window
     * shows up, as Wear OS does. The app launchers call this as
     * desktop.launchApp(model.object, circle). */
    function launchApp(launcherItem, fromItem) {
        launchedFromDrawer = appDrawer.isOpen
        if (Desktop.launchSplash && !launcherItem.isLaunching) {
            var r = fromItem ? fromItem.mapToItem(null, 0, 0, fromItem.width, fromItem.height)
                             : Qt.rect(0, 0, 0, 0)
            Desktop.launchSplash.start(r, alb.centerColor(launcherItem.filePath),
                                       alb.outerColor(launcherItem.filePath),
                                       launcherItem.iconId === "" ? "ios-help" : launcherItem.iconId)
        }
        launcherItem.launchApplication()
    }

    Component.onCompleted: {
        Desktop.desktop = desktop
        Desktop.panelsGrid = grid
        Desktop.confirmation = confirmation
        prewarmTimer.start()
        lipstickSettings.lockScreen(true)
        if(firstRun.isFirstRun())
            firstRunComponent.createObject(desktop)
    }

    Splash {
        id: splash
        z: 9
    }

    Component {
        id: firstRunComponent
        Item {
            anchors.fill: parent
            z: 8
            // An ambient display keeps showing its last frame, which would be
            // a frozen-looking wizard: show the ambient watchface below instead
            visible: !Lipstick.compositor.displayAmbient
            Tutorial { }
            FirstRunConfig { }
        }
    }

    ConfigurationValue {
        id: bipLevel
        key: "/org/asteroidos/settings/burn-in-protection-level"
        defaultValue: DeviceSpecs.needsBurnInProtection ? 1.0 : 0.0
    }

    ConfigurationValue {
        id: alwaysOnDisplay
        key: "/org/asteroidos/settings/always-on-display"
        defaultValue: true
    }

    Item {
        id: burnInProtectionManager

        // Maximum offset before components from other grid becomes visible.
        property int maximumWidthOffset: Dims.w(27)
        property int maximumHeightOffset: Dims.h(27)

        property int leftOffset: Dims.w(2)
        property int rightOffset: Dims.w(2)
        property int topOffset: Dims.h(2)
        property int bottomOffset: Dims.h(2)

        // The maximum allowed movement in x and y direction.
        property int widthOffset
        property int heightOffset

        // Enable/disable burn in protection.
        enabled: DeviceSpecs.needsBurnInProtection && bipLevel.value > 0.0
        readonly property real bipMultiplier: Math.max(0.0, Math.min(1.0, bipLevel.value))

        /* Wear OS moves the always-on screen by a few pixels at a time. The
         * Settings levels High, Medium and Low (1.0, 0.5, 0.25) give about
         * 8, 5 and 3 px either way from the centre (the old offsets let High
         * wander some 52 px); the face walks there in steps of 1 or 2 px a
         * minute instead of jumping anywhere in the range. The faces'
         * setActiveWatchFaceArea/setCenterWatchFaceArea are kept for them
         * but no longer widen it. */
        readonly property real maxShift: bipMultiplier <= 0 ? 0
            : Math.round((3 + 5 * Math.max(0, bipMultiplier - 0.25) / 0.75) * Dims.w(100) / 384)
        property real shiftX: 0
        property real shiftY: 0
        function walk(v) {
            var s = maxShift
            var d = (Math.random() < 0.5 ? -1 : 1) * (1 + Math.floor(Math.random() * 2))
            var n = v + d
            if (n > s || n < -s)
                n = v - d
            return Math.max(-s, Math.min(s, n))
        }
        function step() {
            shiftX = walk(shiftX)
            shiftY = walk(shiftY)
        }

        onHeightOffsetChanged: {
            topOffset = heightOffset/2
            bottomOffset = topOffset
        }

        onWidthOffsetChanged: {
            leftOffset = widthOffset/2
            rightOffset = leftOffset
        }

        onLeftOffsetChanged: if (leftOffset > maximumWidthOffset/2) leftOffset = maximumWidthOffset/2
        onRightOffsetChanged: if (rightOffset > maximumWidthOffset/2) rightOffset = maximumWidthOffset/2
        onTopOffsetChanged: if (topOffset > maximumHeightOffset/2) topOffset = maximumHeightOffset/2
        onBottomOffsetChanged: if (bottomOffset > maximumHeightOffset/2) bottomOffset = maximumHeightOffset/2

        function setActiveWatchFaceArea(x, y, w, h) {
            leftOffset = Math.min(x, maximumWidthOffset/2)
            topOffset = Math.min(y, maximumHeightOffset/2)
            rightOffset = Math.min(Dims.w(100)-w-x, maximumWidthOffset/2)
            bottomOffset = Math.min(Dims.h(100)-h-y, maximumHeightOffset/2)
        }
        function setCenterWatchFaceArea(w, h) {
            widthOffset = Dims.w(100)-w
            heightOffset = Dims.h(100)-h
        }
        function resetOffsets() {
            leftOffset = Dims.w(2)
            rightOffset = Dims.w(2)
            topOffset = Dims.h(2)
            bottomOffset = Dims.h(2)
        }
    }

    /* The clock the watchfaces draw. It ticks every second only while the
     * watchface is the page on screen and its seconds are shown (faces hide
     * them in nightstand, ambient or 12 h mode); else every minute, on the
     * minute: under tiles, the notifications or the app list that is the
     * frame their own curved time draws anyway, and the face is right when
     * it comes back, with no text to change in the first frame of the way
     * back. It stops under an application and with the display off. */
    property bool displayAwake: true
    property Item centreItem: null
    readonly property bool faceShown: centreItem !== null && centreItem.visible
                                      && appDrawer.progress < 1 && facePicker.progress < 1 && !tilesEditor.visible
    property bool faceSecondsShown: false
    function checkSeconds() {
        if (!centreItem)
            return
        applyFaceOptions()
        if (!faceShown)
            return
        faceSecondsShown = faceShowSeconds.value
                           && watchfaceReloader.secondsShown(centreItem.activeFace, centreItem.activeSource)
    }

    /* The watchface options of the face picker, for every face: date and
     * seconds shown or not (seconds never in always-on mode, as on Wear OS),
     * and how the always-on face looks: "dim" (the face in grey: 55 %) or
     * "outline" (grey letter outlines, and the rest dimmed) */
    ConfigurationValue {
        id: faceShowDate
        key: "/org/asteroidos/watchface/show-date"
        defaultValue: true
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    ConfigurationValue {
        id: faceShowSeconds
        key: "/org/asteroidos/watchface/show-seconds"
        defaultValue: true
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    ConfigurationValue {
        id: faceAmbientStyle
        key: "/org/asteroidos/watchface/ambient-style"
        defaultValue: "dim"
        onValueChanged: Qt.callLater(desktop.checkSeconds)
    }
    function applyFaceOptions() {
        if (!centreItem || !centreItem.activeFace)
            return
        watchfaceReloader.applyFaceOptions(centreItem.activeFace, faceShowDate.value, faceShowSeconds.value,
                                           displayAmbient, faceAmbientStyle.value)
    }
    onFaceShownChanged: if (faceShown) checkSeconds()
    onDisplayAmbientChanged: Qt.callLater(checkSeconds)
    Connections {
        target: nightstandMode
        function onActiveChanged() { Qt.callLater(desktop.checkSeconds) }
    }
    Connections {
        target: use12H
        function onValueChanged() { Qt.callLater(desktop.checkSeconds) }
    }
    WallClock {
        id: wallClock
        enabled: desktop.visible && desktop.displayAwake
        updateFrequency: desktop.faceShown && desktop.faceSecondsShown ? WallClock.Second : WallClock.Minute
    }

    MceChargerType {
        id: mceChargerType
    }

    ConfigurationValue {
        id: use12H
        key: "/org/asteroidos/settings/use-12h-format"
        defaultValue: false
    }

    Timer {
        id: wallClockAmbientTimeout
        interval: 200
        repeat: false
        onTriggered: Lipstick.compositor.setAmbientUpdatesEnabled(false)
    }

    // The ambient face is only redrawn on request (the wall clock is off):
    // ask for an update at every minute while it shows.
    Timer {
        id: ambientMinuteTimer
        repeat: false
        onTriggered: {
            Lipstick.compositor.setAmbientUpdatesEnabled(true)
            scheduleAmbientMinute()
        }
    }

    function scheduleAmbientMinute() {
        var now = new Date()
        ambientMinuteTimer.interval = 60000 - now.getSeconds() * 1000 - now.getMilliseconds() + 100
        ambientMinuteTimer.restart()
    }

    LauncherModel {
        id: launcherModel
    }

    DisplaySettings { 
        id: displaySettings
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayAboutToBeOn() {
            wallClockAmbientTimeout.stop()
            desktop.displayAwake = true
        }
        function onDisplayAboutToBeOff() { desktop.displayAwake = false }
        function onDisplayOn() {
            ambientMinuteTimer.stop()
            if (desktop.prewarmPending)
                prewarmTimer.restart()
            grid.animateIndicators()
            ambientDarken = 0
            if (Lipstick.compositor.ambientEnabled) grid.moveTo(0, 0)
        }
        function onDisplayAmbientEntered() {
            scheduleAmbientMinute()
            ambientDarken = 1
            grid.hideOffscreen();
        }
        function onDisplayAmbientLeft() {
            if (burnInProtectionManager.enabled) leftIndicator.anchors.verticalCenterOffset = 0
        }
        function onDisplayAmbientUpdate() {
            // Perform burn in protection
            if (burnInProtectionManager.enabled) {
                burnInProtectionManager.step()
                grid.contentX = burnInProtectionManager.shiftX
                grid.contentY = burnInProtectionManager.shiftY
                leftIndicator.anchors.horizontalCenterOffset = burnInProtectionManager.shiftX
                leftIndicator.anchors.verticalCenterOffset = burnInProtectionManager.shiftY
            }
            // Give watchface some time to update, then go back to deep sleep.
            wallClockAmbientTimeout.start();
        }
    }

    ConfigurationValue {
        id: watchFaceSource
        key: "/desktop/asteroid/watchface"
        defaultValue: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
        onValueChanged: burnInProtectionManager.resetOffsets()
    }

    ConfigurationValue {
        id: appLauncherSource
        key: "/desktop/asteroid/applauncher"
        defaultValue: "file:///usr/share/asteroid-launcher/applauncher/000-default-horizontal.qml"
    }

    ConfigurationValue {
        id: watchfaceNightstandSource
        key: "/desktop/asteroid/nightstand/watchface"
        defaultValue: "file:///usr/share/asteroid-launcher/watchfaces/000-default-digital.qml"
    }

    ConfigurationValue {
        id: nightstandBrightness
        key: "/desktop/asteroid/nightstand/brightness"
        defaultValue: 30
    }

    ConfigurationValue {
        id: nightstandDelay
        key: "/desktop/asteroid/nightstand/delay"
        defaultValue: 5
    }

    ConfigurationValue {
        id: nightstandEnabled
        key: "/desktop/asteroid/nightstand/enabled"
        defaultValue: true
    }

    ConfigurationValue {
        id: nightstandAlwaysOnDisplay
        key: "/desktop/asteroid/nightstand/always-on-display"
        defaultValue: true
    }

    ConfigurationValue {
        id: nightstandUseCustomWatchface
        key: "/desktop/asteroid/nightstand/use-custom-watchface"
        defaultValue: false
    }

    Item {
        id: nightstandMode
        readonly property bool active: ready || nightstandDelayTimer.running
        readonly property bool ready: nightstandEnabled.value && mceChargerType.type != MceChargerType.None
        property int oldBrightness: 100
        onReadyChanged: {
            if (ready) {
                if (nightstandDelayTimer.running) {
                    // timer was holding off, so cancel timer
                    nightstandDelayTimer.stop()
                } else {
                    // enter nightstand mode
                    oldBrightness = displaySettings.brightness
                    displaySettings.brightness = nightstandBrightness.value
                    displaySettings.lowPowerModeEnabled = nightstandAlwaysOnDisplay.value
                }
            } else {
                if (nightstandEnabled.value) {
                    // start off-charger timer
                    nightstandDelayTimer.restart()
                } else {
                    // mode disabled, so 
                    // exit nightstand mode immediately
                    nightstandDelayTimer.stop()
                    displaySettings.brightness = oldBrightness
                    displaySettings.lowPowerModeEnabled = alwaysOnDisplay.value
                }
            }
        }
        Timer {
            id: nightstandDelayTimer
            interval: nightstandDelay.value * 1000
            repeat: false
            onTriggered: {
                // timer expired, so restore brightness
                displaySettings.brightness = nightstandMode.oldBrightness
                displaySettings.lowPowerModeEnabled = alwaysOnDisplay.value
            }
        }
    }

    Connections {
        target: localeManager
        function onChangesObserverChanged() {
            var watchFaceSourceBackup = watchFaceSource.value
            watchFaceSource.value = ""
            watchFaceSource.value = watchFaceSourceBackup
            var appLauncherSourceBackup = appLauncherSource.value
            appLauncherSource.value = ""
            appLauncherSource.value = appLauncherSourceBackup
        }
    }

    Connections {
        target: watchfaceReloader
        // A watchface was just installed into the user folder; the C++ side has
        // dropped the component cache, so re-trigger the loader to re-read the
        // directory and pick the new face up live.
        function onReloadNeeded() {
            desktop.watchfaceReloadRequested()
        }
    }

    Component { id: topPanel;    QuickPanel      { } }
    Component { id: streamPanel; NotificationStream { panelsGrid: grid } }
    Component {
        id: tilePanel
        Loader {
            property string tileFile
            property bool forbidTop: true
            property bool forbidBottom: true
            source: tileFile !== "" ? Qt.resolvedUrl(tileFile) : ""
        }
    }
    Component { id: leftPanel;   NotificationsPanel { panelsGrid: grid } }
    Component { id: rightPanel;  Today              { } }
    Component {
        id: centerPanel;
        Item {
            property bool nightstandWatchfaceActive: nightstandMode.active && nightstandUseCustomWatchface.value && watchfaceNightstandSource.value != watchFaceSource.value
            // always-on: the face in grey, not full white
            opacity: displayAmbient ? 0.55 : 1.0
            // Wear OS: a long press on the watchface opens the face picker
            // (under the face: a face's own buttons keep their presses)
            MouseArea {
                anchors.fill: parent
                z: -1
                enabled: !displayAmbient
                pressAndHoldInterval: 500
                onPressAndHold: {
                    Haptics.longPress()
                    desktop.openFacePicker()
                }
            }
            // the face on screen and its file, for the clock (checkSeconds)
            readonly property Item activeFace: nightstandWatchfaceActive ? nightstandWatchfaceLoader.item : watchfaceLoader.item
            readonly property url activeSource: nightstandWatchfaceActive ? watchfaceNightstandSource.value : watchFaceSource.value
            onActiveFaceChanged: Qt.callLater(desktop.checkSeconds)
            Loader {
                id: nightstandWatchfaceLoader
                opacity: nightstandWatchfaceActive ? 1.0 : 0.0
                visible: opacity
                anchors.fill: parent
                source: watchfaceNightstandSource.value
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InCirc } }
            }
            Loader {
                id: watchfaceLoader
                opacity: !nightstandWatchfaceActive ? 1.0 : 0.0
                visible: opacity
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.InCirc} }
                anchors.fill: parent
                source: watchFaceSource.value

                // Reinstantiate to re-read the source from disk. Toggling the
                // Loader instead of rewriting the dconf-backed watchFaceSource
                // avoids a cross-process write that can clobber a concurrent
                // activation.
                Connections {
                    target: desktop
                    function onWatchfaceReloadRequested() {
                        watchfaceLoader.active = false
                        watchfaceLoader.active = true
                    }
                }
            }
        }
    }
    Component {
        id: bottomPanel
        Loader {
            id: appLauncher
            property bool fakePressed:     false
            property bool toTopAllowed:    true
            property bool toBottomAllowed: true
            property bool toLeftAllowed:   true
            property bool toRightAllowed:  true
            property bool forbidTop: false
            property bool forbidBottom: false
            property bool forbidLeft: false
            property bool forbidRight: false
            source: appLauncherSource.value
            onStatusChanged: {
                if (appLauncher.status == Loader.Ready) {
                    Desktop.appLauncher = appLauncher.item
                }
            }
        }
    }

    PanelsGrid {
        id: grid 
        anchors.fill: parent
        // the app list follows a swipe right on the watchface (Wear layout)
        edgeTarget: desktop.wearLayout ? appDrawer : null

        Component.onCompleted: {
            desktop._wearLayout = homeLayout.value !== "asteroid"
            if (desktop.wearLayout) {
                desktop.centreItem = addPanel(0, 0, centerPanel)
                addPanel(0, -1, topPanel)
                var ns = addPanel(0, 1, streamPanel)
                desktop.buildTiles()
                appDrawer.source = Qt.binding(function() { return appLauncherSource.value })
                rightIndicator.visible  = Qt.binding(function() { return grid.toLeftAllowed && !displayAmbient })
                leftIndicator.visible   = Qt.binding(function() { return grid.toRightAllowed && !displayAmbient && !appDrawer.isOpen })
                topIndicator.visible    = Qt.binding(function() { return grid.toBottomAllowed && !displayAmbient })
                bottomIndicator.visible = Qt.binding(function() { return grid.toTopAllowed && (!displayAmbient || !ns.modelEmpty) })
                bottomIndicator.keepExpanded = Qt.binding(function() { return !ns.modelEmpty && grid.currentHorizontalPos == 0 && grid.currentVerticalPos == 0 })
                return
            }
            desktop.centreItem = addPanel(0, 0, centerPanel)
            var al = addPanel(0, 1, bottomPanel)
            addPanel(1, 0, rightPanel)
            var np = addPanel(-1, 0, leftPanel)
            addPanel(0, -1, topPanel)

            rightIndicator.visible  = Qt.binding(function() { return ((grid.toLeftAllowed   || (grid.currentVerticalPos == 1 && al.toLeftAllowed ))   && !displayAmbient)})
            leftIndicator.visible   = Qt.binding(function() { return ((grid.toRightAllowed  || (grid.currentVerticalPos == 1 && al.toRightAllowed))   && (!displayAmbient || !np.modelEmpty))})
            topIndicator.visible    = Qt.binding(function() { return ((grid.toBottomAllowed || (grid.currentVerticalPos == 1 && al.toBottomAllowed )) && !displayAmbient)})
            bottomIndicator.visible = Qt.binding(function() { return ((grid.toTopAllowed    || (grid.currentVerticalPos == 1 && al.toTopAllowed ))    && !displayAmbient)})

            leftIndicator.keepExpanded = Qt.binding(function() { return !np.modelEmpty && grid.currentHorizontalPos == 0 && grid.currentVerticalPos == 0 })
        }
    }

    // Wear OS's page dots under the tiles (the watchface is the first)
    ArcPageIndicator {
        id: tileDots
        z: 2
        count: desktop.wearLayout && desktop.tileCount > 0 ? desktop.tileCount + 1 : 0
        position: Math.max(0, -grid.contentX / Math.max(1, grid.width))
        visible: count > 0 && grid.currentVerticalPos === 0 && !displayAmbient
                 && (grid.currentHorizontalPos > 0 || grid.contentX < -1)
    }

    // The app list is drawn once, unseen, a few seconds after the start, so
    // that its first opening does not make its textures and text then
    property bool prewarmPending: false
    Timer {
        id: prewarmTimer
        interval: 4000
        onTriggered: {
            desktop.prewarmPending = !(desktop.visible && desktop.displayAwake && !displayAmbient)
            if (!desktop.prewarmPending)
                appDrawer.prewarm()
        }
    }

    AppDrawer {
        id: appDrawer
        z: 5
        onIsOpenChanged: if (isOpen && launcher.item) Desktop.appLauncher = launcher.item
    }

    FacePicker {
        id: facePicker
        z: 6
        onChosen: (face) => watchFaceSource.value = face
    }

    TilesEditor {
        id: tilesEditor
        z: 6
        onDone: (tiles) => tilesSetting.value = tiles
    }

    // "Sent", "Saved"... over everything on the home screen
    Confirmation {
        id: confirmation
        z: 8
    }

    NotificationIndicator {
        id: notifIndic
        anchors.top: parent.top
        anchors.topMargin: Dims.h(5)
        height: Dims.h(8)
        width: parent.width
        panelsGrid: grid
    }

    Indicator { id: rightIndicator; edge: Qt.RightEdge }
    Indicator { id: leftIndicator; edge: Qt.LeftEdge }
    Indicator { id: topIndicator; edge: Qt.TopEdge }
    Indicator { id: bottomIndicator; edge: Qt.BottomEdge }

    Timer {
        id: lockscreenDelay
        interval: 150
        repeat: false
        onTriggered: grid.moveTo(0, 0)
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayOff() {
            lockscreenDelay.start()
            desktop.closeOverlays()
        }
     }

// Wallpaper
    ConfigurationValue {
        id: wallpaperSource
        key: "/desktop/asteroid/background-filename"
        defaultValue: "file:///usr/share/asteroid-launcher/wallpapers/full/000-flatmesh.qml"

        function updateWallpaper() {
            var endsWithQml = /qml$/;
            if (endsWithQml.test(wallpaperSource.value)) {
                wallpaperLoader.sourceComponent = undefined
                wallpaperLoader.source = wallpaperSource.value
            } else {
                wallpaperLoader.source = ""
                wallpaperLoader.sourceComponent = imageWallpaper
            }
        }

        Component.onCompleted: updateWallpaper()
        onValueChanged: updateWallpaper()
    }

    Item {
        id: wallpaper
        width: Dims.w(110)
        height:  Dims.h(110)
        visible: wallpaperDarkener.opacity != 1.0
        enabled: visible
        z: -100
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        // Parallax: shift the wallpaper by 5% of the screen against the scroll
        // direction. Pure bindings on the grid offset, so they always settle to
        // the right place no matter how the position was reached.
        anchors.horizontalCenterOffset: grid.normalizedHorOffset * grid.width  * (-0.05)
        anchors.verticalCenterOffset:   grid.normalizedVerOffset * grid.height * (-0.05)
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Component {
            id: imageWallpaper
            Image { source: wallpaperSource.value }
        }

        Loader {
            id: wallpaperLoader
            anchors.fill: parent
        }
    }

    Rectangle {
        id: wallpaperDarkener
        anchors.fill: wallpaper
        z: -99
        color: "#000000"
        opacity: Math.max(scrollDarken, ambientDarken)
        visible: opacity != 0.0
    }
}
