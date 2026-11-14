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

/* The compositor scene. Its parts are owned modules in compositor/
 * (W1-launcher-split):
 *   AppLifecycle       lipstick's Compositor, windows in front (comp)
 *   WindowTransitions  edge swipe, swipe from anywhere, crown close (transitions)
 *   OverlayArbiter     assistant, heads-up, call, alarm, power, mode, BT (arbiter)
 *   KeyRouter          crown button, side button: one key map (keymap.js)
 * This file keeps the stacking (home, scrim, launch splash, application
 * layer, overlays, swipe, corner mask) and forwards the modules' old names
 * (assistantShown, openAssistant, closeTopmost, closeProgress,
 * anywhereActive, anywhereValue), which the home screen and the tiles use
 * through Desktop.compositorRoot. */
Item {
    id: root
    width: Dims.w(100)
    height: Dims.h(100)
    rotation: Screen.angleBetween(Screen.primaryScreen, Lipstick.compositor.screenOrientation)

    /* Wear OS motion. Window open and close: AOSP frameworks/base
     * core/res/res/interpolator-watch/rounded_window_interpolator.xml
     * (0.4, 0, 0.2, 1) over 250 ms; swipe to dismiss settling: androidx
     * wear compose SwipeToDismissBox, LinearOutSlowIn (0, 0, 0.2, 1) over
     * 200 ms, dismissed past half the width or on a flick */
    readonly property var windowEasing: [0.4, 0, 0.2, 1, 1, 1]
    readonly property var settleEasing: [0, 0, 0.2, 1, 1, 1]

    Component.onCompleted: {
        Desktop.launchSplash = launchSplash
        Desktop.compositorRoot = root
    }

    /* Bedtime's colour filter (NightLight.qml, modes-dnd-09): the whole scene
     * is drawn through it while it is on, and not through a layer otherwise */
    NightLight { id: nightLight }
    layer.enabled: nightLight.active
    layer.effect: nightLight.effect

    // the overlays (OverlayArbiter)
    readonly property bool assistantShown: arbiter.assistantShown
    function openAssistant(text, instant) { arbiter.openAssistant(text, instant === true) }
    function closeAssistant() { arbiter.closeAssistant() }

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
    readonly property bool alertShown: comp.alertShown
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
    readonly property bool systemModal: arbiter.powerMenuShown || arbiter.sosShown || arbiter.errorShown
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
        scale: transitions.homeScale
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

    // Behind the layers while they move (the home screen shrinks over black)
    Rectangle {
        z: -1
        anchors.fill: parent
        color: "black"
        visible: transitions.homeMoving
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
                xScale: transitions.appScale
                yScale: transitions.appScale
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

        // Let app deal with rotation themselves
        rotation: Screen.angleBetween(Lipstick.compositor.screenOrientation, Screen.primaryScreen)
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
        onFace: comp ? comp.homeActive && !arbiter.interrupting && !arbiter.powerMenuShown : true
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

    WindowTransitions { id: transitions }

    KeyRouter { id: keyRouter }

    AppLifecycle { id: comp }

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
