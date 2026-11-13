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
    function openAssistant(text) { arbiter.openAssistant(text) }
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

        Loader {
            id: homeLoader
            anchors.fill: parent
            source: "MainScreen.qml"
            onLoaded: item.aboutToOpen = Qt.binding(function() { return comp ? !comp.homeActive && !appLayer.ready : false })
        }
    }

    // The home screen darkens under an application being swiped away and
    // brightens as it leaves (Wear OS: background scrim 0.5 * (1 - progress))
    Rectangle {
        z: 1
        anchors.fill: parent
        color: "black"
        opacity: 0.5 * (1 - appLayer.dismissProgress)
        visible: appLayer.dismissing && opacity > 0
    }

    // Launch feedback, Wear OS style: the tapped icon grows into a disc in
    // the colours of the application that fills the screen right away and
    // stays until the window of the application fades in over it
    LaunchSplash {
        id: launchSplash
        z: 1.5
        anchors.fill: parent
        easing: root.windowEasing
    }

    Item {
        property bool ready: false
        id: appLayer
        visible: comp ? comp.appActive || dismissing : false
        z: 2

        /* An application being swiped away follows the finger and shrinks
         * (to 0.8: Wear OS squeezes the screen it dismisses), and fades in
         * the last part of the way */
        readonly property bool dismissing: transitions.gestureArea.active || root.anywhereActive
        // a swipe right from anywhere (lipstick's backSwipe*) or from the edge
        readonly property bool dismissHorizontal: root.anywhereActive || transitions.gestureArea.horizontal
        readonly property real dismissValue: root.anywhereActive ? root.anywhereValue : transitions.gestureArea.value
        readonly property real dismissProgress: !dismissing ? 0
            : Math.min(1, root.anywhereActive ? root.anywhereValue / Math.max(1, width) : transitions.gestureArea.progress)
        readonly property real dismissScale: (1 - 0.2 * dismissProgress) * (1 - 0.25 * root.closeProgress)
        opacity: (dismissProgress < 0.6 ? 1 : 1 - (dismissProgress - 0.6) / 0.4) * (1 - root.closeProgress)
        transform: [
            Scale {
                origin.x: appLayer.width / 2
                origin.y: appLayer.height / 2
                xScale: appLayer.dismissScale
                yScale: appLayer.dismissScale
            },
            Translate {
                // the near edge of the shrunk window stays under the finger
                x: appLayer.dismissing && appLayer.dismissHorizontal
                   ? appLayer.dismissValue - (1 - appLayer.dismissScale) * appLayer.width / 2 : 0
                y: appLayer.dismissing && !appLayer.dismissHorizontal
                   ? appLayer.dismissValue - (1 - appLayer.dismissScale) * appLayer.height / 2 : 0
            }
        ]

        width: parent.width
        height: parent.height

        // Let app deal with rotation themselves
        rotation: Screen.angleBetween(Lipstick.compositor.screenOrientation, Screen.primaryScreen)
    }

    OverlayArbiter { id: arbiter }

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
