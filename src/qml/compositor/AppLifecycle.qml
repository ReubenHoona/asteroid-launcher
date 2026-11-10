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
import "../desktop.js" as Desktop

/* The applications' windows (split out of compositor.qml): lipstick's
 * Compositor, which window is in front, the home screen when none is,
 * and an application closed 5 s after the display goes off.
 * Instantiated once in compositor.qml as `comp` (the id the other parts
 * use). Reads compositor.qml's ids (root, appLayer, launchSplash,
 * transitions) through the context. Owned by W2-launcher-keys-lifecycle. */
Compositor {
    id: comp

    // The current foreground application window, or null when the home
    // screen (the persistent item underneath) is showing.
    property Item topmostWindow

    // Only used to change blank timeout when on watchface or elsewhere
    property bool longTimeout: homeActive
    Component.onCompleted: {
        longTimeout = Qt.binding(function() {
            // the assistant over the face is not the lock screen: with it, mce
        // blanked the display 10 s after the side button (its lock screen
        // timeout) and allowed no blanking pause, and a slow answer never
        // showed (the overlay closes with the display)
        return homeActive && Desktop.panelsGrid != null
                && Desktop.panelsGrid.currentVerticalPos == 0
                && Desktop.panelsGrid.currentHorizontalPos == 0
                && !root.assistantShown
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

    // each application window is wrapped (the open animation)
    property Component windowWrapper: Component {
        WindowWrapperBase { }
    }

    // the application in front is closed 5 s after the display goes off
    property Timer delayTimer: Timer {
        interval: 5000
        repeat: false
        onTriggered: {
            if (comp.topmostWindow && comp.topmostWindow.window)
                Lipstick.compositor.closeClientForWindowId(comp.topmostWindow.window.windowId)
            // eos: not while the sensor hub draws a current layout: it shows
            // the face whatever was open, and an update here was a second
            // handover and a layout resend at every display off (stock: one
            // handover per display off, a layout only when it changes)
            if (Lipstick.compositor.offloadAmbientUpdateWanted())
                Lipstick.compositor.setAmbientUpdatesEnabled(true)
        }
    }

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
                return transitions.gestureArea.active || root.anywhereActive || appLayer.opacity < 1.0 || !appLayer.ready
            })
            // a new application ends a swipe still settling
            transitions.endEdgeSwipe()
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
