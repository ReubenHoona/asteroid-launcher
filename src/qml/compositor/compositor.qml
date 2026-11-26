/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2013 John Brooks <john.brooks@dereferenced.net>
 *               2013 Jolla Ltd.
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
import QtQuick.Window
import org.nemomobile.lipstick
import org.asteroid.controls
import org.asteroid.utils
import "desktop.js" as Desktop
import "compositor"
import "system"
import "home"
import "charging"
import "lock"
import "a11y"

/* The compositor scene. Its parts are owned modules in compositor/
 * (W1-launcher-split):
 *   AppLifecycle       lipstick's Compositor, windows in front (comp)
 *   WindowTransitions  edge swipe, swipe from anywhere, crown close (transitions)
 *   OverlayArbiter     assistant, heads-up, call, alarm, power, mode, BT (arbiter)
 *   KeyRouter          crown button, side button: one key map (keymap.js)
 *   ChargingController the charger: charging screen, plug and unplug wake (charging)
 * This file keeps the stacking (home, scrim, launch splash, application
 * layer, overlays, swipe, corner mask) and forwards the modules' old names
 * (assistantShown, openAssistant, closeTopmost, closeProgress,
 * anywhereActive, anywhereValue), which the home screen and the tiles use
 * through Desktop.compositorRoot. */
Item {
    id: root
    width: Dims.w(100)
    height: Dims.h(100)
    // a right-to-left language: the launcher's layouts (anchors, rows, lists) mirror, as qml-asteroid's
    // Application does for the apps (locale-formats-05); the faces place their items themselves and stay
    LayoutMirroring.enabled: Theme.rtl
    LayoutMirroring.childrenInherit: true
    /* The wrist and crown setting (W3-launcher-wrist, wrist-orientation-04): with the crown on the left
     * (modes 1 and 3) the whole picture is turned by 180 degrees about the display centre (this root is
     * the display, so the pivot is (192, 192)), as stock's freezeRotation(ROTATION_180): at once, no
     * animation, applications, overlays and dialogs included. Touches follow the item transforms. The mode
     * is read before the first frame (main.cpp). Lipstick's screenOrientation is not used for it: it sends
     * a wl_output transform and makes clients turn themselves. */
    readonly property int wristRotation: typeof wristOrientation !== "undefined" && wristOrientation ? wristOrientation.rotation : 0
    rotation: wristRotation
    // the crown's sign follows the flip in one place: an event filter on the window (WristOrientation)
    function wristAttach() {
        if (typeof wristOrientation !== "undefined" && wristOrientation && root.Window.window)
            wristOrientation.attachWindow(root.Window.window)
    }
    Window.onWindowChanged: wristAttach()

    /* Wear OS motion. Window open and close: AOSP frameworks/base
     * core/res/res/interpolator-watch/rounded_window_interpolator.xml
     * (0.4, 0, 0.2, 1) over 250 ms; swipe to dismiss settling: androidx
     * wear compose SwipeToDismissBox, LinearOutSlowIn (0, 0, 0.2, 1) over
     * 200 ms, dismissed past half the width or on a flick */
    readonly property var windowEasing: [0.4, 0, 0.2, 1, 1, 1]
    readonly property var settleEasing: [0, 0, 0.2, 1, 1, 1]

    Component.onCompleted: {
        wristAttach()
        Desktop.launchSplash = launchSplash
        Desktop.compositorRoot = root
        /* Every list here is the system UI's (the app list, the grid, Recents, the stream, quick
         * settings, the launcher's own pages): the scroll indicator in its style, a white thumb on a
         * #4D4D4D track over 34 degrees (the Wear OS 6 emulator S05, S07, S11; N61-03). A view that
         * is an M3 screen in stock keeps the app style with `property bool m3Indicator: true`
         * (the tile picker, TileAddList). Applications are other processes: not touched. */
        RotaryInput.systemIndicator = true
    }

    /* Bedtime's colour filter (NightLight.qml, modes-dnd-09): the whole scene
     * is drawn through it while it is on, and not through a layer otherwise */
    ColorCorrection { id: colorCorrection }
    NightLight { id: nightLight; extra: colorCorrection }
    layer.enabled: nightLight.active
    layer.effect: nightLight.effect
    // magnified (a11y/Magnifier.qml), the layer is drawn at the size it is shown, not stretched
    layer.textureSize: magnifier.magnified ? Qt.size(width * magnifier.zoom, height * magnifier.zoom) : Qt.size(0, 0)
    // Magnification: Scale and Translate of the whole scene, in window coordinates
    transform: magnifier.transforms

    // the overlays (OverlayArbiter)
    readonly property bool assistantShown: arbiter.assistantShown
    // (not while the screen is locked: the assistant would be a way round the lock)
    function openAssistant(text, instant) {
        if (keyguard.locked)
            return
        arbiter.openAssistant(text, instant === true)
    }
    function closeAssistant() { arbiter.closeAssistant() }
    // stock: the assistant coming up closes the face picker without applying (face-interaction-33)
    onAssistantShownChanged: {
        if (assistantShown && homeLoader.item && homeLoader.item.closeFacePicker)
            homeLoader.item.closeFacePicker()
    }

    // the windows leaving (WindowTransitions)
    readonly property real closeProgress: transitions.closeProgress
    readonly property bool anywhereActive: transitions.anywhereActive
    readonly property real anywhereValue: transitions.anywhereValue
    function closeTopmost() { transitions.closeTopmost() }

    // the applications (AppLifecycle): leave to the background, come back,
    // the one before, the list for Recents
    function leaveApp() { comp.leaveApp(comp.topmostWindow) }
    function resumeApp(exec) { return comp.resumeApp(exec) }
    function previousApp() { return comp.previousApp() }
    function recents() { return comp.recents() }
    function closeHidden(windowId) { comp.closeHidden(windowId) }
    // (comp is null while the compositor goes)
    readonly property bool alertShown: comp ? comp.alertShown : false
    // the heads-up (W2-launcher-heads-up): its view is up (the crown and the edge swipe are
    // its); what the home screen tells it
    readonly property bool headsUpShown: arbiter.headsUpShown
    readonly property bool faceCurrent: homeLoader.item && comp ? (comp.homeActive && homeLoader.item.faceCurrent === true) : false
    // the same in always-on too: what the heads-up is told (D60-02; the home screen as
    // loaded, a MainScreen)
    readonly property var homeScreen: homeLoader.item
    readonly property bool faceForAlerts: homeScreen && comp ? (comp.homeActive && homeScreen.faceForAlerts === true) : false
    readonly property bool streamCurrent: homeLoader.item && comp ? (comp.homeActive && homeLoader.item.streamCurrent === true) : false
    // the parts, for the tests and the other packages
    readonly property QtObject keys: keyRouter
    readonly property QtObject lifecycle: comp
    readonly property Item overlays: arbiter
    readonly property Item windowMotion: transitions
    readonly property Item applications: appLayer
    readonly property Item homeItem: homeLayer
    // the always-on screen over an open application (W2-launcher-ambient)
    readonly property Item ambientLite: liteLayer
    // the power system (W2-launcher-power-system): touch lock, power menu, SOS, error
    // dialogs, screenshot show; a surface of these takes the edge swipe away
    readonly property bool touchLocked: touchLock.locked
    // The face's status icons (W2-launcher-status): the touch lock and the open microphone are claims of
    // the ongoing registry, which the home screen's status slot reads
    readonly property bool micInUse: arbiter.micInUse
    function claimStatus(kind, on) {
        if (typeof ongoingRegistry !== "undefined" && ongoingRegistry !== null)
            ongoingRegistry.setInUse(kind, on)
    }
    onTouchLockedChanged: claimStatus("touchlock", touchLocked)
    onMicInUseChanged: claimStatus("mic", micInUse)
    // (a change handler does not run for the value a property starts with)
    QtObject {
        Component.onCompleted: {
            root.claimStatus("touchlock", root.touchLocked)
            root.claimStatus("mic", root.micInUse)
        }
    }
    readonly property bool systemModal: arbiter.powerMenuShown || arbiter.sosShown || arbiter.errorShown || charging.up || keyguard.locked
    // the screen lock (W3-launcher-a11y-security): the keyguard item, for the other modules
    readonly property bool keyguardLocked: keyguard.locked
    readonly property Item keyguardItem: keyguard
    readonly property Item magnifierItem: magnifier
    readonly property Item screenReaderItem: screenReader
    // the charging screen (or its quality screen) is up (W2-launcher-charging): the crown closes it
    readonly property bool chargingShown: charging.up
    readonly property Item chargingItem: chargingScreen
    function dismissCharging() { return charging.dismiss() }
    readonly property Item touchLockItem: touchLock
    readonly property Item screenshotItem: screenshotOverlay
    function takeScreenshot() { screenshotOverlay.capture() }
    readonly property Item splash: launchSplash

    // The side button's Recents (KeyRouter): the home screen's Recents list,
    // when it has one (W2-launcher-app-list); true when it opened or closed
    property var recentsHandler: null
    function toggleRecents() {
        if (recentsHandler)
            return !!recentsHandler()
        return homeLoader.item && homeLoader.item.toggleRecents ? !!homeLoader.item.toggleRecents() : false
    }

    // The home screen is a persistent item at the bottom of the z-stack, not
    // an in-process "window". Its z follows MainScreen's own z (raised while
    // the splash is up) so it can sit above running apps when needed.
    Item {
        id: homeLayer
        z: homeLoader.item ? homeLoader.item.z : 0
        anchors.fill: parent

        // What the window transitions do to the home screen (WindowTransitions,
        // W2-launcher-window-motion): under an app opening it shrinks to 0.70
        // and dims; on the way back (the crown) it grows from 0.5; behind a
        // back swipe it grows 0.85 -> 0.93, dimmed. Cropped to a circle while
        // it moves, as stock; at rest nothing is changed or rendered twice.
        scale: transitions.homeScale * keyguard.faceZoom
        opacity: transitions.homeAlpha
        layer.enabled: transitions.homeMoving && DeviceSpecs.hasRoundScreen
        layer.effect: CircleMaskShader { }

        Loader {
            id: homeLoader
            anchors.fill: parent
            source: "MainScreen.qml"
            onLoaded: item.aboutToOpen = Qt.binding(function() { return comp ? !comp.homeActive && !appLayer.ready : false })
        }

        // the black dim over it
        Rectangle {
            z: 1000
            anchors.fill: parent
            radius: width / 2
            color: "black"
            opacity: transitions.homeDim
            visible: opacity > 0
        }
    }

    // Behind the layers while they move (the home screen shrinks over black; an
    // application shrinks behind Recents)
    Rectangle {
        z: -1
        anchors.fill: parent
        color: "black"
        visible: transitions.homeMoving || transitions.recentsMoving
    }

    // Launch feedback, Wear OS style: the tapped icon grows into a disc in
    // the colours of the application that fills the screen right away and
    // stays until the window of the application fades in over it
    LaunchSplash {
        id: launchSplash
        z: 1.5
        anchors.fill: parent
        // the opening window of the launch transition (WindowTransitions.launch)
        motion: transitions.launch
        // the starting window shows only with the display on
        displayOn: comp ? !comp.displayIsOff : true
    }

    Item {
        property bool ready: false
        id: appLayer
        visible: comp ? comp.appActive || transitions.backActive : false
        z: 2

        /* An application leaving (WindowTransitions): the crown shrinks it to
         * 0.60 and fades it; a swipe right shrinks it to 0.70 with its right
         * edge on the screen's right edge, dimmed, and (let go past the
         * commit rule) takes its left edge off the screen. A window opening is
         * scaled by its own wrapper (WindowWrapperBase). */
        opacity: transitions.appAlpha
        transform: [
            Scale {
                origin.x: appLayer.width / 2
                origin.y: appLayer.height / 2
                xScale: transitions.appScale * keyguard.faceZoom
                yScale: transitions.appScale * keyguard.faceZoom
            },
            Translate { x: transitions.appX }
        ]

        // the black dim over the application (a back swipe)
        Rectangle {
            z: 1000
            anchors.fill: parent
            radius: width / 2
            color: "black"
            opacity: transitions.appDim
            visible: opacity > 0
        }

        width: parent.width
        height: parent.height

        // The applications do not turn themselves: the root turns them with everything else
        // (wristRotation); no counter-rotation here
        rotation: 0
    }

    /* The charger (W2-launcher-charging): the charging screen over the home screen and the
     * applications, under every overlay of the arbiter (z 2.5: the assistant, notifications,
     * calls and alarms draw above it); the charging quality screen above it. The controller
     * holds the rules, the screens only draw. */
    ChargingController {
        id: charging
        displayOff: comp ? comp.displayIsOff : false
        // the plug-in vibration (ngfd charging_started, hardware class = the Using crown switch, as
        // stock); it came with lipstick's 'Charging' banner, which is gone
        onPlugFeedback: Haptics.playAs("charging_started", Haptics.Crown)
    }
    ChargingScreen {
        id: chargingScreen
        z: 2.4
        anchors.fill: parent
        shown: charging.shown
        plugIntro: charging.intro
        fade: charging.fade
        awake: comp ? !comp.displayIsOff : true
        // the unread dot (N61-18): the home screen's, with the setting "Show unread notification
        // indicator" (stock's charging view state copies notificationDotEnabled, inj.java:29)
        unread: root.homeScreen ? root.homeScreen.unreadDotWanted === true : false
        onIntroFinished: charging.intro = false
    }
    ChargerProblem {
        id: chargerProblem
        z: 2.45
        anchors.fill: parent
        kind: charging.problemKind
    }

    /* The screen lock (W3-launcher-a11y-security): over the face and the applications, under the
     * notifications, calls, alarms, the power menu and SOS of the arbiter (declared after it, same z: its items draw above): the
     * bouncer, the lockout dialog and the boot lock screen. Locked, the watch goes to the face; the
     * face is held there (the crown cannot move it) and zooms out behind the bouncer. */
    Keyguard {
        id: keyguard
        z: 2.5
        displayOn: comp ? !comp.displayIsOff : true
        touchLocked: touchLock.locked
        onEngaged: {
            root.closeAssistant()
            arbiter.closeHeadsUp()
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.showWatchface()
        }
    }
    // a secure lock keeps the sensor hub's tilt-to-bright off (CR-46 ttb)
    Binding {
        target: Lipstick.compositor
        property: "offloadLockedSecure"
        value: keyguard.locked && keyguard.secured
        when: !!Lipstick.compositor && Lipstick.compositor.offloadLockedSecure !== undefined
    }
    // locked, the face is all that shows (a panel moved by the crown goes back at once)
    Connections {
        target: homeLoader.item
        ignoreUnknownSignals: true
        function onFaceCurrentChanged() {
            if (keyguard.locked && homeLoader.item && !homeLoader.item.faceCurrent && !keyguard.bouncerShown
                    && homeLoader.item.showWatchface)
                homeLoader.item.showWatchface()
        }
    }

    OverlayArbiter { id: arbiter }

    /* Emergency SOS: the quiet modes and touch lock go off (stock
     * WearEmergencyActionsHelper: DND, Theater, Touch lock, Bedtime), and
     * the lock's exit view and the power menu give way */
    Connections {
        target: arbiter
        function onSosTriggered() {
            touchLock.unlock()
            arbiter.closePowerMenu()
            if (typeof modes !== "undefined" && modes !== null) {
                modes.bedtime = false
                modes.theater = false
                modes.doNotDisturb = false
            }
        }
    }

    /* Touch lock (wake-sleep-display-03): above the edge swipe (5) and the
     * screenshot show, under the always-on screen; turned on, it takes the
     * watch to the face (the quick settings tile, Settings, the power menu) */
    TouchLock {
        id: touchLock
        z: arbiter.layers.touchLock
        displayOn: comp ? !comp.displayIsOff : true
        onEngaged: {
            arbiter.closePowerMenu()
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.showWatchface()
        }
    }

    /* The screenshot show (system-dialogs-misc-08) */
    ScreenshotOverlay {
        id: screenshotOverlay
        z: 5.6
    }

    /* The always-on screen over an open application: Ambient Lite or the media
     * layout (AmbientLite.qml, ambient-aod-01, media-controls-15), under the
     * burn-in mask and the corner mask. Nothing of it shows with the display on. */
    AmbientLite {
        id: liteLayer
        z: 5.8
        anchors.fill: parent
        sourceItem: appLayer
        use12h: !TimeFormat.use24h
    }
    BurnInMask {
        z: 5.9
        anchors.fill: parent
    }

    WindowTransitions {
        id: transitions
        readonly property var home: homeLoader.item
        recents: home ? home.recents : null
    }

    /* Accessibility (W3-launcher-a11y-security): magnification (the scene's own transform), the
     * vibration watch, and the screen reader's state (KeyRouter reads its shortcut and toggle) */
    Magnifier {
        id: magnifier
        z: 7
    }
    VibrationWatch {
        id: vibrationWatch
        displayOn: comp ? !comp.displayIsOff : true
        onFace: root.faceCurrent
    }
    ScreenReader { id: screenReader }

    KeyRouter { id: keyRouter }

    AppLifecycle { id: comp; home: homeLoader.item }

    // Rounds off the corners of a round screen. The mask depends on nothing
    // but the size of the screen, so rather than masking the whole screen
    // again on every frame the system draws, it is rendered once into a
    // texture that every later frame simply blits.
    ShaderEffectSource {
        z: 6
        anchors.fill: parent
        visible: DeviceSpecs.hasRoundScreen
        live: false
        hideSource: true
        sourceItem: cornerMask

        Component.onCompleted: scheduleUpdate()
        onWidthChanged: scheduleUpdate()
        onHeightChanged: scheduleUpdate()

        Item {
            id: cornerMask
            anchors.fill: parent

            // CircleMaskShader shades a source texture, and the source here is
            // a constant: the corners are painted plain black. A single opaque
            // black pixel, stretched over the item, is that constant.
            Rectangle {
                id: blackPixel
                width: 1
                height: 1
                color: "black"
                layer.enabled: true
            }

            CircleMaskShader {
                anchors.fill: parent
                smoothness: 0.002
                keepInner: false
                property Item source: blackPixel
            }
        }
    }
}
