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
import "pager.js" as Pager
import "tiles"
import "complications"
import "home"
import "compositor"

/* The home screen. Its parts are owned modules in home/ (W1-launcher-split):
 *   FaceLayer          the watch face, its options and clock  (faceLayer)
 *   Trays              the panels around the face, the layout (trays)
 *   TilesRing          the tiles, their dconf list, page dots (tilesRing)
 *   AmbientController  display state, always-on, burn-in, hub, modes (ambientController)
 *   (the nightstand is gone: DECISIONS.md Q34; ChargingController is the compositor's)
 *   HomeOverlays       app list, face picker, tiles editor, splash, first run (overlays)
 *   StatusSlot         unread indicator, edge hints           (statusSlot)
 * This file keeps what the panels, faces, app launchers and the compositor
 * reach by name: the root properties and functions below (desktop.*), and
 * the ids of the shared objects (alb, wallClock, use12H, alwaysOnDisplay,
 * mceChargerType, displaySettings, launcherModel, complications, grid,
 * nightstandMode). The modules' own objects are forwarded under their old
 * names (burnInProtectionManager, appDrawer, facePicker, tilesEditor,
 * confirmation, splash, the indicators), so a lookup by name from a panel,
 * a face or an app launcher finds the same object as before. */
Item {
    id: desktop
    width: Dims.w(100)
    height: Dims.h(100)
    // Recents opens over an application too: above it, below calls, alarms and the assistant (compositor.qml)
    z: splash.visible ? 10 : (recents.isOpen ? 2.4 : 0)

    visible: Lipstick.compositor.homeActive || aboutToOpen || aboutToClose || aboutToMinimize || recents.isOpen
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
    property var bgCenterColor: (!launcherColorOverride && !wearLayout && grid.normalizedVerOffset > 0)
                              ? mixColor(launcherCenterColor, defaultCenterColor, grid.normalizedVerOffset)
                              : defaultCenterColor
    property var bgOuterColor: (!launcherColorOverride && !wearLayout && grid.normalizedVerOffset > 0)
                             ? mixColor(launcherOuterColor, defaultOuterColor, grid.normalizedVerOffset)
                             : defaultOuterColor

    /* Wallpaper darkening overlay opacity, expressed as the maximum of two
     * independent, declarative contributions so it can never get stranded the
     * way the old imperative signal handlers could:
     *  - scrollDarken tracks the grid offset (instant, follows the finger).
     *    The launcher page (verOffset > 0) is intentionally not darkened unless
     *    a launcher overrides the background colours. In the Wear layout the
     *    vertical panels are trays over a still face, which is neither darkened
     *    nor moved (the trays have their own background, PanelsGrid), and the
     *    tiles slide over a face that zooms behind a black layer of the
     *    grid's (PanelsGrid.faceDistance), so nothing here darkens.
     *  - ambientDarken is toggled by the ambient signals (AmbientController)
     *    and fades over 300ms. */
    property real scrollDarken: displayAmbient ? 0.0
                              : (grid.normalizedVerOffset > 0 && !launcherColorOverride) ? 0.0
                              : wearLayout ? 0
                              : Math.max(Math.abs(grid.normalizedHorOffset), Math.abs(grid.normalizedVerOffset)) * 0.4
    property real ambientDarken: 0.0
    /* Going to the always-on screen the wallpaper darkens together with the
     * face's own change (500 ms, the standard easing: the watch face's
     * ambient transition, WFF runtime_ambient_transition_ms, ambient-aod-19);
     * the wake is at once (no brightness ramp at screen on, stock
     * config_skipScreenOnBrightnessRamp, motion-transitions-32). */
    function setAmbientDarken(v) {
        ambientFade.stop()
        if (v > ambientDarken && Motion.animationScale > 0) {
            ambientFade.to = v
            ambientFade.restart()
        } else {
            ambientDarken = v
        }
    }
    NumberAnimation {
        id: ambientFade
        target: desktop
        property: "ambientDarken"
        duration: 500
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easing.standard
    }

    property var compositor: Lipstick.compositor

    property bool aboutToOpen: false
    property bool aboutToClose: false
    property bool aboutToMinimize: false

    // for the watchfaces: no nightstand mode any more (the stock charging screen is the
    // compositor's, W2-launcher-charging); the name stays so the faces keep loading
    property alias nightstand: nightstandMode.active
    // the charging screen's unread dot
    readonly property int unreadCount: statusSlot.notificationIndicator.unreadCount

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

    // the layout, read at start (Trays)
    readonly property bool wearLayout: _wearLayout
    property bool _wearLayout: true
    property bool launchedFromDrawer: false

    // the tiles (TilesRing)
    readonly property var tileRegistry: tilesRing.tileRegistry
    readonly property var builtTiles: tilesRing.builtTiles
    readonly property int tileCount: tilesRing.tileCount
    function buildTiles() { tilesRing.buildTiles() }
    function openTilesEditor() { tilesRing.openTilesEditor() }

    // the face picker (FaceLayer, HomeOverlays)
    function openFacePicker() { faceLayer.openFacePicker() }

    // the drawer, the face picker and the tiles editor go (HomeOverlays)
    function closeOverlays() { overlays.closeOverlays() }
    // the face picker alone (the assistant came up, face-interaction-33)
    function closeFacePicker() { overlays.closeFacePicker() }

    // the side button's Recents (the compositor's KeyRouter): opens it, or closes it when open
    function toggleRecents() { return overlays.toggleRecents() }

    // the long press of an ongoing activity's chip: turn its app's live updates off? (StatusSlot)
    function openLiveMenu(app, who) { statusSlot.openLiveMenu(app, who) }

    // the crown button on the home screen (HomeOverlays)
    function crownPressed() { overlays.crownPressed() }

    /* A tap on the heads-up card: the notification, open, in the stream (an
     * application on the screen closes first, as the crown would) */
    property Item streamItem: null
    /* The notification stream, as the Notifications complication opens it */
    function openNotificationStream() {
        if (Desktop.compositorRoot && !Lipstick.compositor.homeActive)
            Desktop.compositorRoot.closeTopmost()
        closeOverlays()
        if (wearLayout)
            grid.showStream()
    }
    function openNotification(n) {
        if (Desktop.compositorRoot && !Lipstick.compositor.homeActive)
            Desktop.compositorRoot.closeTopmost()
        closeOverlays()
        if (wearLayout && streamItem) {
            // only this one is read, not the rest of the stream under it (status-indicators-08)
            statusSlot.notificationIndicator.openedFromHeadsUp(n)
            grid.showStream()
            streamItem.openDetail(n)
        } else {
            grid.moveTo(-1, 0)
        }
    }

    /* Settings > Apps > App info of an app: the launcher writes "<page>@<ms>" to
     * /org/asteroidos/settings/ui/open (asteroid-settings main.qml openRequested)
     * and starts Settings; the desktop file name of the app goes to
     * /org/asteroidos/settings/ui/open-app for the page of that app. A long
     * press on an app of the list or the grid, and Recents' "App Info" */
    ConfigurationValue {
        id: settingsOpen
        key: "/org/asteroidos/settings/ui/open"
        defaultValue: ""
    }
    ConfigurationValue {
        id: settingsOpenApp
        key: "/org/asteroidos/settings/ui/open-app"
        defaultValue: ""
    }
    function openAppInfo(item) {
        if (!item || !item.filePath)
            return
        settingsOpenApp.value = item.filePath.split("/").pop()
        settingsOpen.value = "app_info@" + Date.now()
        launchByName("asteroid-settings", null)
    }

    /* A long press on the face in Bedtime mode: Bedtime mode's settings page
     * (stock BEDTIME_MODE_CUSTOMIZE_SETTINGS, face-interaction-04); the same
     * way Settings is asked for as App info above ("bedtime@<ms>" to ui/open,
     * handled by asteroid-settings main.qml openRequested) */
    function openBedtimeSettings() { openSettings("bedtime") }

    // Settings, on a page (wave 1 follow-up): "<page>@<ms>" to ui/open, then the program
    function openSettings(page) {
        closeOverlays()
        settingsOpen.value = page + "@" + Date.now()
        launchByName("asteroid-settings", null)
    }

    /* "Find my phone" of the app list: the launcher's own page (the entry
     * asteroid-find-my-phone.desktop has no program). The page registers
     * itself as Desktop.findMyPhone (apps-misc-04); until it does, quick
     * settings, where the Find my phone button is, opens (3 = REASON.nonDrag) */
    function openFindMyPhone() {
        closeOverlays()
        if (Desktop.findMyPhone && Desktop.findMyPhone.open)
            Desktop.findMyPhone.open()
        else
            grid.openTray(-1, 3, 0)
    }

    // the crown (or the app ending) takes Recents away from the face: it closes
    Connections {
        target: Lipstick.compositor
        function onHomeActiveChanged() {
            if (Lipstick.compositor.homeActive && recents.isOpen)
                recents.closeNow()
        }
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
        // a tile's app opens as every launch does, with no origin of the tile's
        // own (stock starts it with makeBasic options: tiles-framework-29)
        if (fromItem && fromItem.tileFrame === true)
            fromItem = null
        // "Assistant" in the app list is the launcher's own overlay
        if (launcherItem.filePath && launcherItem.filePath.split("/").pop() === "asteroid-assistant.desktop") {
            if (Desktop.compositorRoot && Desktop.compositorRoot.openAssistant)
                Desktop.compositorRoot.openAssistant("")
            return
        }
        // "Find my phone" in the app list is the launcher's own page too
        if (launcherItem.filePath && launcherItem.filePath.split("/").pop() === "asteroid-find-my-phone.desktop") {
            openFindMyPhone()
            return
        }
        // Recents: this launch is the newest (the history is written now, never by a timer)
        recents.record(launcherItem)
        // already running, hidden in the background: it comes back warm, with
        // the open motion and no splash (AppLifecycle.resumeApp)
        if (Desktop.compositorRoot && Desktop.compositorRoot.resumeApp
                && Desktop.compositorRoot.resumeApp(launcherItem.exec)) {
            launchedFromDrawer = appDrawer.isOpen
            return
        }
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
        overlays.startPrewarm()
        lipstickSettings.lockScreen(true)
        if(firstRun.isFirstRun())
            overlays.startFirstRun()
    }

    // the clock of the watch face (FaceLayer.checkSeconds); its id is the
    // faces' and the first-run wizard's
    property bool displayAwake: true
    property Item centreItem: null
    readonly property bool faceShown: centreItem !== null && centreItem.visible
    /* The face is the current panel with nothing over it: a new notification's
     * glanceable is for this, anywhere else it is a bubble; and the notification
     * list is the current panel: only a vibration (W2-launcher-heads-up) */
    readonly property bool faceCurrent: faceShown && !displayAmbient && !appDrawer.isOpen && !recents.isOpen
                                        && !splash.visible && grid.currentHorizontalPos === 0
                                        && grid.currentVerticalPos === 0 && Math.abs(grid.ringPosition) < 0.001
                                        && grid.topTrayFraction === 0 && grid.bottomTrayFraction === 0
    readonly property bool streamCurrent: wearLayout ? (grid.currentHorizontalPos === 0 && grid.currentVerticalPos === 1)
                                                     : (grid.currentHorizontalPos === -1 && grid.currentVerticalPos === 0)
                                      && appDrawer.progress < 1 && facePicker.progress < 1 && !tilesEditor.visible
    readonly property bool faceSecondsShown: faceLayer.faceSecondsShown
    function checkSeconds() { faceLayer.checkSeconds() }
    function applyFaceOptions() { faceLayer.applyFaceOptions() }
    WallClock {
        id: wallClock
        enabled: desktop.visible && desktop.displayAwake
        updateFrequency: desktop.faceShown && desktop.faceSecondsShown ? WallClock.Second : WallClock.Minute
    }

    // Shared by id with the panels, tiles, faces and app launchers
    MceChargerType {
        id: mceChargerType
    }

    ConfigurationValue {
        id: use12H
        key: "/org/asteroidos/settings/use-12h-format"
        defaultValue: false
    }

    ConfigurationValue {
        id: alwaysOnDisplay
        key: "/org/asteroidos/settings/always-on-display"
        defaultValue: true
    }

    /* The watch face complications (ComplicationSources): the data the
     * faces' slots show, read only while the face (or the face editor) is
     * on the awake screen; nothing is read, and nothing on the face changes,
     * with the screen off or in always-on, where only the date shows */
    ComplicationSources {
        id: complications
        active: desktop.displayAwake && !displayAmbient && (desktop.faceShown || facePicker.visible)
        ambient: displayAmbient
        // the sensor hub draws the always-on face: live data would go stale there (ambient-aod-11)
        hubDrawn: ambientController.hubFace && !ambientController.alwaysOnBlocked
        nightstand: nightstandMode.active
        use12h: use12H.value
        now: wallClock.time
        unread: statusSlot.notificationIndicator.unreadCount
        apps: launcherModel
    }

    LauncherModel {
        id: launcherModel
    }

    DisplaySettings {
        id: displaySettings
    }

    // the always-on screen (AmbientController)
    readonly property string hubLayoutInputs: ambientController.hubLayoutInputs
    readonly property real ambientMinuteShown: ambientController.ambientMinuteShown
    readonly property int hubBurnInMoveMinutes: ambientController.hubBurnInMoveMinutes
    function scheduleAmbientMinute() { ambientController.scheduleAmbientMinute() }
    readonly property Item burnInProtectionManager: ambientController.burnInProtectionManager
    readonly property bool modesReady: ambientController.modesReady
    readonly property bool alwaysOnBlocked: ambientController.alwaysOnBlocked
    readonly property bool brightnessHeld: ambientController.brightnessHeld
    function applyLowPower() { ambientController.applyLowPower() }
    // Bedtime coming on: the watch face (system/ModeScreen.qml)
    function showWatchface() {
        closeOverlays()
        grid.moveTo(0, 0)
    }

    // what opens over the home screen (HomeOverlays)
    readonly property Item splash: overlays.splash
    readonly property Item appDrawer: overlays.appDrawer
    readonly property Item facePicker: overlays.facePicker
    readonly property Item tilesEditor: overlays.tilesEditor
    readonly property Item confirmation: overlays.confirmation
    readonly property Item recents: overlays.recents
    readonly property bool prewarmPending: overlays.prewarmPending

    // the status slot's indicators (StatusSlot)
    readonly property Item rightIndicator: statusSlot.rightIndicator
    readonly property Item leftIndicator: statusSlot.leftIndicator
    readonly property Item topIndicator: statusSlot.topIndicator
    readonly property Item bottomIndicator: statusSlot.bottomIndicator

    FaceLayer { id: faceLayer }
    // The nightstand mode is gone (DECISIONS.md Q34, charging-battery-10): the faces, the face
    // layer and the always-on rules still read these names, which now say 'not active'
    QtObject {
        id: nightstandMode
        readonly property bool active: false
        readonly property var watchfaceSource: ""
        readonly property var useCustomWatchface: false
        readonly property var alwaysOnDisplayValue: true
        function enter() {}
        function leave() {}
    }
    AmbientController { id: ambientController }
    Trays { id: trays }

    Connections {
        target: watchfaceReloader
        // A watchface was just installed into the user folder; the C++ side has
        // dropped the component cache, so re-trigger the loader to re-read the
        // directory and pick the new face up live.
        function onReloadNeeded() {
            desktop.watchfaceReloadRequested()
        }
    }

    /* The face and what it stands on, drawn as one: the grid with the face
     * and the trays, the tiles' dots, the status slot and the wallpaper. The
     * app list opens over it (W2-launcher-window-motion): while the list zooms
     * in the face shrinks to 0.70 under a 50 % black dim; while the list goes,
     * the face grows from 0.5 (faceScale, faceAlpha, faceDim of AppDrawer).
     * Cropped to a circle while it moves; at rest nothing is changed. */
    Item {
        id: faceStack
        anchors.fill: parent
        scale: appDrawer.faceScale
        opacity: appDrawer.faceAlpha
        layer.enabled: appDrawer.faceMoving && DeviceSpecs.hasRoundScreen
        layer.effect: CircleMaskShader { }

        PanelsGrid {
            id: grid
            anchors.fill: parent
            // no swipe opens the app list in the Wear layout (stock: the crown
            // does); a swipe right on the face shows the last tile, the carousel
            // being a ring (tiles-framework-01, app-launcher-28). Only an
            // AsteroidOS-layout launcher could set an edge target.
            edgeTarget: null

            Component.onCompleted: trays.build()
        }

        TilesRing { id: tilesRing }


        StatusSlot { id: statusSlot }

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
            // the right place no matter how the position was reached. Not in the
            // Wear layout: the trays pass over a face that stays put, and so do the
            // tiles; the face (wallpaper with it) zooms to 0.8 behind them instead
            // (stock lcl.java:40-91; none with Reduce animations).
            scale: wearLayout ? Pager.faceScale(grid.faceDistance, Motion.reduceMotion) : 1
            anchors.horizontalCenterOffset: wearLayout ? 0 : grid.normalizedHorOffset * grid.width  * (-0.05)
            anchors.verticalCenterOffset:   wearLayout ? 0 : grid.normalizedVerOffset * grid.height * (-0.05)
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

        // the black dim over the face
        Rectangle {
            z: 1000
            anchors.fill: parent
            radius: width / 2
            color: "black"
            opacity: appDrawer.faceDim
            visible: opacity > 0
        }
    }

    HomeOverlays { id: overlays }
}
