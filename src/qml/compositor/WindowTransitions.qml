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
import org.nemomobile.lipstick
import org.asteroid.controls
import "../desktop.js" as Desktop

/* How application windows leave (split out of compositor.qml): the swipe
 * down or right from the edge (BorderGestureArea), the swipe right from
 * anywhere (lipstick's backSwipe*), and the close on the crown. The
 * application layer in compositor.qml follows the values here
 * (gestureArea, anywhereActive, anywhereValue, closeProgress, which
 * compositor.qml forwards under its old names). Instantiated once in
 * compositor.qml as `transitions` at z 5 (the edge swipe's z), under the
 * corner mask (6). Reads compositor.qml's ids (root, comp) through the
 * context. Owned by W2-launcher-window-motion. */
Item {
    id: transitions
    anchors.fill: parent
    z: 5

    readonly property Item gestureArea: edgeSwipe

    BorderGestureArea {
        id: edgeSwipe
        enabled: comp ? comp.appActive && !root.assistantShown : false
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
                    && (edgeSwipe.progress >= swipeThreshold || edgeSwipe.flung)) {
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
                target: edgeSwipe
                property: "value"
                to: 0
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.settleEasing
            }

            ScriptAction { script: edgeSwipe.endGesture() }
        }

        SequentialAnimation {
            id: swipeAnimation
            property alias valueTo: valueAnimation.to

            NumberAnimation {
                id: valueAnimation
                target: edgeSwipe
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
                    edgeSwipe.endGesture()
                }
            }
        }
    }

    // a new application ends a swipe still settling (AppLifecycle)
    function endEdgeSwipe() {
        if (edgeSwipe.active) {
            cancelAnimation.stop()
            swipeAnimation.stop()
            edgeSwipe.endGesture()
            edgeSwipe.reset()
        }
    }

    /* The crown button (KeyRouter) in an application: the window leaves as
     * a Wear OS window does (down to 0.75 and fading, 250 ms) */
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
    // The swipe ends with its window: once the window that would send
    // backSwipeFinished is no longer in front (the application closed or
    // crashed, delayTimer closed it with the display off, another came to
    // the front), nothing finishes it, and the home screen stayed under
    // the dismiss scrim with the application layer shown (dismissing)
    on_TopWindowItemChanged: {
        if (transitions.anywhereActive && !anywhereClose.running && !anywhereSettle.running) {
            transitions.anywhereActive = false
            transitions.anywhereValue = 0
            Desktop.desktop.aboutToMinimize = false
        }
    }

    Connections {
        target: transitions._topWindowItem
        ignoreUnknownSignals: true
        function onBackSwipeStarted() {
            if (closeAnim.running || edgeSwipe.active)
                return
            anywhereSettle.stop()
            anywhereClose.stop()
            transitions.anywhereValue = 0
            transitions.anywhereActive = true
            Desktop.desktop.aboutToMinimize = true
        }
        function onBackSwipeMoved(value) {
            if (transitions.anywhereActive && !anywhereClose.running && !anywhereSettle.running)
                transitions.anywhereValue = Math.min(value, root.width)
        }
        function onBackSwipeFinished(value, velocity) {
            if (!transitions.anywhereActive)
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
            target: transitions; property: "anywhereValue"; to: 0; duration: 200
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.settleEasing
        }
        ScriptAction {
            script: {
                transitions.anywhereActive = false
                Desktop.desktop.aboutToMinimize = false
            }
        }
    }

    SequentialAnimation {
        id: anywhereClose
        NumberAnimation {
            target: transitions; property: "anywhereValue"; to: root.width; duration: 200
            easing.type: Easing.BezierSpline; easing.bezierCurve: root.settleEasing
        }
        ScriptAction {
            script: {
                var app = comp.topmostWindow
                comp.setCurrentWindow(null)
                if (app && app.window)
                    Lipstick.compositor.closeClientForWindowId(app.window.windowId)
                transitions.anywhereActive = false
                transitions.anywhereValue = 0
                Desktop.desktop.aboutToMinimize = false
            }
        }
    }

    function closeTopmost() {
        if (closeAnim.running || edgeSwipe.active || !comp.topmostWindow)
            return
        Desktop.desktop.aboutToClose = true
        closeAnim.start()
    }

    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: transitions
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
                transitions.closeProgress = 0
                Desktop.desktop.aboutToClose = false
            }
        }
    }
}
