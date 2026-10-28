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
        readonly property bool dismissing: gestureArea.active || root.anywhereActive
        // a swipe right from anywhere (lipstick's backSwipe*) or from the edge
        readonly property bool dismissHorizontal: root.anywhereActive || gestureArea.horizontal
        readonly property real dismissValue: root.anywhereActive ? root.anywhereValue : gestureArea.value
        readonly property real dismissProgress: !dismissing ? 0
            : Math.min(1, root.anywhereActive ? root.anywhereValue / Math.max(1, width) : gestureArea.progress)
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

    // Launcher overlays, rendered directly in the compositor scene as
    // z-ordered items instead of in-process "windows". Each is fed by a C++
    // object exposed as a context property; the QML gates its own visibility.
    Loader {
        z: 3
        anchors.fill: parent
        source: "notifications/NotificationPreview.qml"
    }

    // A call ringing on the phone: full screen, above the preview
    Loader {
        z: 3
        anchors.fill: parent
        source: "IncomingCall.qml"
    }

    // An alarm or timer ringing on the phone: full screen, above the preview
    Loader {
        z: 3
        anchors.fill: parent
        source: "PhoneAlarm.qml"
    }

    Loader {
        z: 3
        anchors.fill: parent
        source: "system/ShutdownScreen.qml"
    }

    Loader {
        z: 4
        anchors.fill: parent
        source: "connectivity/BluetoothAgent.qml"
    }

    BorderGestureArea {
        id: gestureArea
        enabled: comp ? comp.appActive : false
        z: 5
        anchors.fill: parent
        acceptsDown: true
        acceptsRight: comp != null && comp.topmostWindow != null && !comp.topmostWindowRequestsGesturesDisabled

        // Wear OS: past half the screen, or a flick
        property real swipeThreshold: 0.5

        // The gesture (its direction and value) stays set until the
        // window has settled back or left: the animations below run on it
        function endGesture() {
            delayReset = false
            Desktop.desktop.aboutToClose = false
            Desktop.desktop.aboutToMinimize = false
        }

        onGestureStarted: (gesture) => {
            swipeAnimation.stop()
            cancelAnimation.stop()
            delayReset = true
            if (gesture == "down") {
                Desktop.desktop.aboutToClose = true
            } else if(gesture == "right") {
                Desktop.desktop.aboutToMinimize = true
            }
        }

        onGestureFinished: (gesture) => {
            if ((gesture == "down" || gesture == "right")
                    && (gestureArea.progress >= swipeThreshold || gestureArea.flung)) {
                // the window keeps going the way the finger went, then the
                // application closes
                swipeAnimation.valueTo = max
                swipeAnimation.start()
            } else {
                cancelAnimation.start()
            }
        }

        SequentialAnimation {
            id: cancelAnimation

            NumberAnimation {
                target: gestureArea
                property: "value"
                to: 0
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.settleEasing
            }

            ScriptAction { script: gestureArea.endGesture() }
        }

        SequentialAnimation {
            id: swipeAnimation
            property alias valueTo: valueAnimation.to

            NumberAnimation {
                id: valueAnimation
                target: gestureArea
                property: "value"
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.settleEasing
            }

            ScriptAction {
                script: {
                    var app = comp.topmostWindow
                    comp.setCurrentWindow(null)
                    if (app && app.window)
                        Lipstick.compositor.closeClientForWindowId(app.window.windowId)
                    gestureArea.endGesture()
                }
            }
        }
    }

    Component {
        id: windowWrapper
        WindowWrapperBase { }
    }

    /* The crown button (mce's power_button_trigger, see CrownButton), as
     * Wear OS uses it: in an application it goes back to the watchface (the
     * window leaves as a Wear OS window does: down to 0.75 and fading,
     * 250 ms), on the home screen the home screen decides (app list, back
     * to the watchface) */
    property real closeProgress: 0

    /* Back from anywhere, as Wear OS at the root of an application: the
     * client allows it per touch (qml-asteroid Application.backFromAnywhere,
     * the gestures protocol's set_back_from_anywhere), lipstick takes a
     * swipe right from anywhere on the window and says so here; the window
     * follows the finger as with the edge swipe and closes past half the
     * screen or on a flick */
    property bool anywhereActive: false
    property real anywhereValue: 0
    readonly property Item _topWindowItem: comp.topmostWindow ? comp.topmostWindow.window : null

    Connections {
        target: root._topWindowItem
        ignoreUnknownSignals: true
        function onBackSwipeStarted() {
            if (closeAnim.running || gestureArea.active)
                return
            anywhereSettle.stop()
            anywhereClose.stop()
            root.anywhereValue = 0
            root.anywhereActive = true
            Desktop.desktop.aboutToMinimize = true
        }
        function onBackSwipeMoved(value) {
            if (root.anywhereActive && !anywhereClose.running && !anywhereSettle.running)
                root.anywhereValue = Math.min(value, root.width)
        }
        function onBackSwipeFinished(value, velocity) {
            if (!root.anywhereActive)
                return
            // Wear OS: past half the width, or a flick (125 dp/s)
            if (value >= root.width / 2 || velocity >= root.width / 192 * 125)
                anywhereClose.start()
            else
                anywhereSettle.start()
        }
    }

    SequentialAnimation {
        id: anywhereSettle
        NumberAnimation {
            target: root; property: "anywhereValue"; to: 0; duration: 200
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.settleEasing
        }
        ScriptAction {
            script: {
                root.anywhereActive = false
                Desktop.desktop.aboutToMinimize = false
            }
        }
    }

    SequentialAnimation {
        id: anywhereClose
        NumberAnimation {
            target: root; property: "anywhereValue"; to: root.width; duration: 200
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.settleEasing
        }
        ScriptAction {
            script: {
                var app = comp.topmostWindow
                comp.setCurrentWindow(null)
                if (app && app.window)
                    Lipstick.compositor.closeClientForWindowId(app.window.windowId)
                root.anywhereActive = false
                root.anywhereValue = 0
                Desktop.desktop.aboutToMinimize = false
            }
        }
    }

    function closeTopmost() {
        if (closeAnim.running || gestureArea.active || !comp.topmostWindow)
            return
        Desktop.desktop.aboutToClose = true
        closeAnim.start()
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: root
            property: "closeProgress"
            from: 0
            to: 1
            duration: 250
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.windowEasing
        }
        ScriptAction {
            script: {
                var app = comp.topmostWindow
                comp.setCurrentWindow(null)
                if (app && app.window)
                    Lipstick.compositor.closeClientForWindowId(app.window.windowId)
                root.closeProgress = 0
                Desktop.desktop.aboutToClose = false
            }
        }
    }

    Connections {
        target: typeof crownButton !== "undefined" ? crownButton : null
        function onPressed() {
            if (launchSplash.active)
                return
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.crownPressed()
        }
    }

    Timer {
        id: delayTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (comp.topmostWindow && comp.topmostWindow.window)
                Lipstick.compositor.closeClientForWindowId(comp.topmostWindow.window.windowId)
            Lipstick.compositor.setAmbientUpdatesEnabled(true)
        }
    }

    Compositor {
        id: comp

        // The current foreground application window, or null when the home
        // screen (the persistent item underneath) is showing.
        property Item topmostWindow

        // Only used to change blank timeout when on watchface or elsewhere
        property bool longTimeout: homeActive
        Component.onCompleted: {
            longTimeout = Qt.binding(function() {
                return homeActive && Desktop.panelsGrid != null
                    && Desktop.panelsGrid.currentVerticalPos == 0
                    && Desktop.panelsGrid.currentHorizontalPos == 0
            })
        }
        onLongTimeoutChanged: lipstickSettings.lockscreenVisible = longTimeout

        // Home is active whenever no application window is on top
        homeActive: topmostWindow == null
        property bool appActive: !homeActive

        // The application window that was most recently topmost
        property Item topmostApplicationWindow

        readonly property bool topmostWindowRequestsGesturesDisabled: topmostWindow && topmostWindow.window
                                                                      && topmostWindow.window.overridesSystemGestures

        function windowToFront(winId) {
            var o = comp.windowForId(winId)
            setCurrentWindow(o ? o.userData : null)
        }

        function setCurrentWindow(w, skipAnimation) {
            topmostWindow = w; // null => the home screen is shown

            if (topmostWindow != null) {
                if (topmostApplicationWindow && topmostApplicationWindow != topmostWindow)
                    topmostApplicationWindow.visible = false
                topmostApplicationWindow = topmostWindow
                topmostApplicationWindow.visible = true
                // over the launch splash the window only fades in; without
                // one it zooms in from 75% as a Wear OS activity does
                if (!skipAnimation) topmostApplicationWindow.animateIn(launchSplash.active)
                launchSplash.finish()
                w.window.takeFocus()
            }
        }

        onDisplayOff: {
            delayTimer.start()
            launchSplash.cancel()
        }
        onDisplayAboutToBeOn: delayTimer.stop()

        // An application that comes to the front while the display is off or
        // in low power mode asks for the unlock above when mce refuses it
        // (mce only unlocks with the display on or dimmed) and puts the lock
        // back. The application then sits under mce's lockscreen policy: it
        // blanks 10 s after the display comes on, and delayTimer closes the
        // application 5 s later. Ask again once the display is on, and give
        // the application back the focus lipstick did not restore while
        // locked.
        onDisplayOn: {
            // A wake through the low-power (AOD) path does not always emit
            // displayAboutToBeOn: the close timer started at display off
            // would close the application 5 s later with the display on.
            delayTimer.stop()
            if (appActive && lipstickSettings.lockscreenVisible) {
                lipstickSettings.lockscreenVisible = false
                if (topmostWindow && topmostWindow.window)
                    topmostWindow.window.takeFocus()
            }
        }

        onWindowAdded: (window) => {
            // The launcher's own UI (home screen + overlays) are plain items,
            // so every window here is a Wayland client application.
            var isDialogWindow = window.category === "dialog"

            var w = windowWrapper.createObject(appLayer, { window: window })
            window.userData = w

            if (!isDialogWindow) {
                if (topmostApplicationWindow != null) {
                    Lipstick.compositor.closeClientForWindowId(topmostApplicationWindow.window.windowId)
                }
                appLayer.ready = false
                w.smoothBorders = Qt.binding(function() {
                    return gestureArea.active || root.anywhereActive || appLayer.opacity < 1.0 || !appLayer.ready
                })
                // a new application ends a swipe still settling
                if (gestureArea.active) {
                    cancelAnimation.stop()
                    swipeAnimation.stop()
                    gestureArea.endGesture()
                    gestureArea.reset()
                }
                setCurrentWindow(w)
            }
        }

        onWindowRaised: (window) => windowToFront(window.windowId)

        onWindowRemoved: (window) => {
            var w = window.userData;
            if (comp.topmostWindow == w)
                setCurrentWindow(null); // reveal the home screen underneath

            if (window.userData)
                window.userData.destroy()
        }
    }

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
