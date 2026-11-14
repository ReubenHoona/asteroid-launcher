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
import Nemo.Configuration
import org.nemomobile.lipstick
import "../desktop.js" as Desktop
import "lifecycle.js" as Life

/* The applications' windows (split out of compositor.qml): lipstick's
 * Compositor, which window is in front, the home screen when none is, and
 * what becomes of an application that leaves the screen. Instantiated once
 * in compositor.qml as `comp` (the id the other parts use). Reads
 * compositor.qml's ids (root, appLayer, launchSplash, transitions, arbiter)
 * through the context. Owned by W2-launcher-keys-lifecycle.
 *
 * Wear OS (audit buttons-navigation-04, interruptions-01/02/14,
 * ambient-aod-03; rules and numbers in lifecycle.js):
 *  - Home, Back, the crown and a swipe at the root of an application move it
 *    to the background (leaveApp): the window and process stay, the window is
 *    only hidden. Nothing is destroyed. At most 4 hidden applications are
 *    kept (the least recently used goes first).
 *  - A hidden application is frozen (SIGSTOP of its process, lipstick
 *    freezeClientForWindowId) 5 s after it left the screen, and thawed before
 *    it is shown again. An application with an ongoing activity (a
 *    notification hint x-eos-ongoing, or a window flag `ongoing`) is never
 *    frozen and never expires. The one timer here runs only while a freeze is
 *    pending, and never while the display is off after the first 5 s.
 *  - After the display went off the application in front stays until
 *    Settings > Display > Go to watch face (default 1 minute) has passed. No
 *    timer runs for it: the time of the display off is kept, and the wake
 *    checks it (so no wake-up is ever armed). Then the application goes to
 *    the background, the overlays of the home screen close and the face
 *    shows. A short wake restarts the count, at most twice.
 *  - A firing alarm or timer (a system alert window: title "Alarm Presenter",
 *    category "alert" or a window flag systemAlert) is drawn over everything
 *    in arbiter.alertLayer. The application under it is kept, and is there
 *    again when the alert ends. */
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

    /* ---- the system alert in front (a firing alarm or timer) ---------- */

    // The wrapper of the alert window, or null
    property Item alertWindow: null
    // The crown sent the alert to the face: the alarm keeps ringing in its
    // own process, its window is no longer in front (DECISIONS.md Q49; stock
    // DeskClock keeps ringing when the activity leaves, buttons-navigation-22)
    property bool alertHidden: false
    readonly property bool alertShown: alertWindow !== null && !alertHidden
    function hideAlert() {
        if (!alertShown)
            return
        alertHidden = true
        if (topmostWindow && topmostWindow.window)
            topmostWindow.window.takeFocus()
    }

    function isSystemAlert(window) {
        return window.systemAlert === true || window.category === "alert"
               || window.title === "Alarm Presenter"
    }

    /* ---- settings and the clock --------------------------------------- */

    // Settings > Display > Go to watch face (ms; 0 = immediately, 86400000 =
    // never; interruptions-01)
    property QtObject goToFaceSetting: ConfigurationValue {
        key: "/org/asteroidos/settings/go-to-watch-face-ms"
        defaultValue: 60000
    }
    readonly property int goToFaceMs: Life.timeoutValue(goToFaceSetting.value)

    // boot-time clock in ms (it runs while the AP sleeps; lipstick
    // bootTimeMs), else the wall clock
    function nowMs() {
        var c = Lipstick.compositor
        return typeof c.bootTimeMs === "function" ? c.bootTimeMs() : Date.now()
    }

    /* ---- hidden applications ------------------------------------------ */

    // by window id: { id, key, hidden, dark, frozen, ongoing, hiddenAt,
    // lastUsed }. hidden: left the screen (leaveApp); dark: in front but the
    // display is off (frozen after 5 s too).
    property var meta: ({})
    // the keys of the applications with an ongoing activity (notifications)
    property var ongoingKeys: ({})
    // the status text of those activities (the hint x-eos-ongoing-status), by key: Recents' second line
    property var ongoingStatus: ({})
    // a short counter of the hidden apps, for tests and Recents
    property int hiddenCount: 0

    function winId(w) { return w && w.window ? w.window.windowId : -1 }
    function entry(w) {
        var id = winId(w)
        if (!meta[id])
            meta[id] = { id: id, key: "", hidden: false, dark: false, frozen: false,
                         ongoing: false, hiddenAt: 0, lastUsed: 0 }
        return meta[id]
    }
    function keyOf(w) {
        return w && w.window ? Life.appKey(w.window.appKey) : ""
    }
    function isOngoing(w) {
        if (!w || !w.window)
            return false
        return w.window.ongoing === true
               || Life.windowOngoing(w.window.appKey, w.window.title, ongoingKeys)
    }
    function wrapperForId(id) {
        var o = comp.windowForId(id)
        return o ? o.userData : null
    }
    function listOf(pred) {
        var r = []
        for (var id in meta) {
            var m = meta[id]
            if (!m.closing && pred(m))
                r.push({ id: m.id, hiddenAt: m.hiddenAt, frozen: m.frozen,
                         ongoing: m.ongoing, lastUsed: m.lastUsed })
        }
        return r
    }
    function offscreenList() { return listOf(function (m) { return m.hidden || m.dark }) }
    function hiddenList() { return listOf(function (m) { return m.hidden }) }
    function countHidden() { hiddenCount = hiddenList().length }

    function setFrozen(id, on) {
        var m = meta[id]
        if (!m || m.frozen === on)
            return
        var c = Lipstick.compositor
        if (typeof c.freezeClientForWindowId === "function")
            c.freezeClientForWindowId(id, on)
        m.frozen = on
    }

    // Freeze what is due now, and arm the timer for the next one
    function freezeDue() {
        var due = Life.dueToFreeze(offscreenList(), nowMs())
        for (var i = 0; i < due.length; i++) {
            // an app that would keep a sensor running frozen is closed
            if (Life.closesWhenHidden(meta[due[i]].key)) {
                var w = wrapperForId(due[i])
                if (w) {
                    closeWindow(w)
                    continue
                }
            }
            setFrozen(due[i], true)
        }
        scheduleFreeze()
    }
    function scheduleFreeze() {
        var d = Life.nextFreezeIn(offscreenList(), nowMs())
        if (d < 0) {
            freezeTimer.stop()
        } else {
            freezeTimer.interval = Math.max(1, d)
            freezeTimer.restart()
        }
    }
    property Timer freezeTimer: Timer {
        repeat: false
        onTriggered: comp.freezeDue()
    }

    // Close an application's window for good (its process quits): thawed
    // first, a stopped process cannot hear the quit
    function closeWindow(w) {
        var id = winId(w)
        if (id < 0)
            return
        setFrozen(id, false)
        // asked to quit: no longer listed or frozen while it winds down
        if (meta[id])
            meta[id].closing = true
        Lipstick.compositor.closeClientForWindowId(id)
    }

    // A window leaves the screen but stays alive: hidden, frozen in 5 s
    function hideWindow(w) {
        if (!w || !w.window)
            return
        var m = entry(w)
        m.key = keyOf(w)
        m.hidden = true
        m.dark = false
        m.hiddenAt = nowMs()
        m.lastUsed = m.hiddenAt
        m.ongoing = isOngoing(w)
        w.visible = false
        var ev = Life.evictions(hiddenList())
        for (var i = 0; i < ev.length; i++) {
            var o = wrapperForId(ev[i])
            if (o && o !== w)
                closeWindow(o)
        }
        countHidden()
        scheduleFreeze()
    }

    /* An application goes to the background (the crown, Back at its root,
     * the swipes of WindowTransitions): the home screen shows, the
     * application is kept. */
    function leaveApp(w) {
        var app = w ? w : topmostWindow
        if (!app)
            return
        if (topmostWindow == app)
            setCurrentWindow(null)
        hideWindow(app)
    }

    // Bring a hidden application back to the front (thawed first)
    function bringBack(w) {
        if (!w || !w.window)
            return false
        setCurrentWindow(w)
        return true
    }

    // The hidden application used last, or null
    function previousWindow() {
        var best = null, bestAt = -1
        for (var id in meta) {
            var m = meta[id]
            if (m.hidden && !m.closing && m.lastUsed >= bestAt) {
                var w = wrapperForId(m.id)
                if (w && w !== topmostWindow) {
                    best = w
                    bestAt = m.lastUsed
                }
            }
        }
        return best
    }

    /* Side button double press (Wear OS: the previous app, else the face):
     * the hidden application used last comes back, the one in front goes
     * to the background; none: the face. */
    function previousApp() {
        var p = previousWindow()
        if (p)
            return bringBack(p)
        if (appActive)
            leaveApp(topmostWindow)
        return false
    }

    /* Launching an application that is already running (desktop.launchApp):
     * its hidden window comes back, with the open motion. exec is the
     * launcher item's Exec line or its desktop id. */
    function resumeApp(exec) {
        var k = Life.appKey(exec)
        if (k === "")
            return false
        for (var id in meta) {
            var m = meta[id]
            if (m.hidden && !m.closing && m.key === k) {
                var w = wrapperForId(m.id)
                if (w)
                    return bringBack(w)
            }
        }
        // the application in front already is the one asked for
        return topmostWindow !== null && keyOf(topmostWindow) === k
    }

    // The applications for Recents, most recent first: the one in front,
    // then the hidden ones. [{ windowId, key, title, frozen, front }]
    function recents() {
        var r = []
        if (topmostWindow && topmostWindow.window)
            r.push({ windowId: winId(topmostWindow), key: keyOf(topmostWindow),
                     title: topmostWindow.window.title, frozen: false, front: true })
        var h = hiddenList().sort(function (a, b) { return b.lastUsed - a.lastUsed })
        for (var i = 0; i < h.length; i++) {
            var w = wrapperForId(h[i].id)
            if (w)
                r.push({ windowId: h[i].id, key: meta[h[i].id].key, title: w.window.title,
                         frozen: h[i].frozen, front: false })
        }
        return r
    }

    // Dismiss a hidden application from Recents
    function closeHidden(windowId) {
        var w = wrapperForId(windowId)
        if (w && meta[windowId] && meta[windowId].hidden)
            closeWindow(w)
    }

    /* ---- ongoing activities (ambient-aod-03) -------------------------- */

    function refreshOngoing() {
        var keys = {}
        var status = {}
        for (var i = 0; i < ongoingModel.itemCount; i++) {
            var n = ongoingModel.get(i)
            var k = Life.ongoingKey(n.hints, n.category, n.appName)
            if (k !== "") {
                keys[k] = true
                var st = n.hints ? n.hints["x-eos-ongoing-status"] : undefined
                if (typeof st === "string" && st !== "")
                    status[k] = st
            }
        }
        ongoingKeys = keys
        ongoingStatus = status
        var frontWas = topmostWindow ? entry(topmostWindow).ongoing : false
        for (var id in meta) {
            var m = meta[id]
            var w = wrapperForId(m.id)
            var on = w ? isOngoing(w) : false
            if (on && m.frozen)
                setFrozen(m.id, false)
            m.ongoing = on
        }
        // the activity in front ended while the display is off: the count
        // for the face starts again, 500 ms later
        if (topmostWindow && frontWas && !entry(topmostWindow).ongoing && displayIsOff)
            Life.ongoingEnded(episode, nowMs())
        scheduleFreeze()
    }
    property QtObject ongoingModel: NotificationListModel {
        onItemAdded: comp.refreshOngoing()
        onItemRemoved: comp.refreshOngoing()
        onPopulatedChanged: comp.refreshOngoing()
    }

    /* ---- the display and the way back to the face --------------------- */

    property bool displayIsOff: false
    // the go-to-watch-face count (lifecycle.js)
    property var episode: Life.newEpisode()
    // The wake came from the always-on display (the crown's Home action
    // runs only then, KeyRouter)
    property bool wakeFromAmbient: false
    property bool ambientWhileOff: false

    // Back to the face after the time away: the application in front goes
    // to the background, the home screen's overlays close, the face shows
    function goToFace() {
        if (appActive)
            leaveApp(topmostWindow)
        if (Desktop.desktop && Desktop.desktop.showWatchface)
            Desktop.desktop.showWatchface()
        Life.episodeEnd(episode)
        goneToFace()
    }
    signal goneToFace()

    // the front application with an ongoing activity never expires
    function frontExempt() {
        return appActive && isOngoing(topmostWindow)
    }

    // The application in front when the display is off: frozen 5 s later
    function markDark() {
        if (!topmostWindow)
            return
        var m = entry(topmostWindow)
        m.key = keyOf(topmostWindow)
        m.dark = true
        m.hiddenAt = nowMs()
        m.ongoing = isOngoing(topmostWindow)
        scheduleFreeze()
    }

    function wake() {
        if (!displayIsOff)
            return
        displayIsOff = false
        wakeFromAmbient = ambientWhileOff
        ambientWhileOff = false
        // thaw the application in front before it is shown
        for (var id in meta) {
            var m = meta[id]
            if (m.dark) {
                m.dark = false
                setFrozen(m.id, false)
            }
        }
        scheduleFreeze()
        if (frontExempt()) {
            Life.episodeEnd(episode)
            return
        }
        if (Life.displayOn(episode, nowMs(), goToFaceMs))
            goToFace()
    }

    // The 5 s after a display off: the hub's layout (the application in
    // front is no longer closed here: it is frozen, freezeTimer)
    property Timer delayTimer: Timer {
        interval: 5000
        repeat: false
        onTriggered: {
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
        var prev = topmostApplicationWindow
        topmostWindow = w; // null => the home screen is shown

        if (topmostWindow != null) {
            // a hidden or frozen application comes back: thawed first
            var m = entry(w)
            m.key = keyOf(w)
            m.hidden = false
            m.dark = displayIsOff
            m.lastUsed = nowMs()
            setFrozen(m.id, false)
            if (prev && prev != topmostWindow) {
                prev.visible = false
                // the application it replaces stays, in the background
                if (prev.window && meta[winId(prev)] && !meta[winId(prev)].hidden)
                    hideWindow(prev)
            }
            topmostApplicationWindow = topmostWindow
            topmostApplicationWindow.visible = true
            // the window opens with the app launch springs (over the launch
            // splash they are already running); WindowTransitions.openWindow
            if (!skipAnimation) transitions.openWindow(topmostApplicationWindow, launchSplash.active)
            launchSplash.finish()
            w.window.takeFocus()
            countHidden()
            scheduleFreeze()
        }
    }

    onDisplayOff: {
        var t = nowMs()
        displayIsOff = true
        ambientWhileOff = Lipstick.compositor.displayAmbient
        wakeFromAmbient = false
        delayTimer.start()
        Life.displayOff(episode, t, goToFaceMs)
        markDark()
        launchSplash.cancel()
        // 'Immediately': the face at once, there is nothing to see
        if (goToFaceMs === 0 && !frontExempt() && Life.expired(episode, t, 0))
            goToFace()
    }
    onDisplayAboutToBeOn: {
        delayTimer.stop()
        wake()
    }

    // An application that comes to the front while the display is off or
    // in low power mode asks for the unlock above when mce refuses it
    // (mce only unlocks with the display on or dimmed) and puts the lock
    // back. The application then sits under mce's lockscreen policy: it
    // blanks 10 s after the display comes on. Ask again once the display is
    // on, and give the application back the focus lipstick did not restore
    // while locked.
    onDisplayOn: {
        // A wake through the low-power (AOD) path does not always emit
        // displayAboutToBeOn: do the wake here as well (it is idempotent)
        delayTimer.stop()
        wake()
        if (appActive && lipstickSettings.lockscreenVisible) {
            lipstickSettings.lockscreenVisible = false
            if (topmostWindow && topmostWindow.window)
                topmostWindow.window.takeFocus()
        }
    }

    // two windows of one program: the older hidden one goes (a launch that
    // did not find it, resumeApp)
    function closeDuplicates(window) {
        var k = Life.appKey(window.appKey)
        if (k === "")
            return
        for (var id in meta) {
            var m = meta[id]
            if (m.hidden && m.key === k && Number(id) !== window.windowId) {
                var o = wrapperForId(m.id)
                if (o)
                    closeWindow(o)
            }
        }
    }

    onWindowAdded: (window) => {
        // The launcher's own UI (home screen + overlays) are plain items,
        // so every window here is a Wayland client application.
        var isDialogWindow = window.category === "dialog"
        var isAlert = isSystemAlert(window)

        // a firing alarm or timer is drawn over everything; the application
        // under it stays (interruptions-02, -09)
        var w = windowWrapper.createObject(isAlert ? arbiter.alertLayer : appLayer, { window: window })
        window.userData = w

        if (isAlert) {
            alertWindow = w
            alertHidden = false
            w.smoothBorders = false
            w.visible = true
            transitions.openWindow(w, false)
            window.takeFocus()
            return
        }

        if (!isDialogWindow) {
            closeDuplicates(window)
            // the application in front goes to the background (setCurrentWindow)
            appLayer.ready = false
            w.smoothBorders = Qt.binding(function() {
                return transitions.windowMoving || !appLayer.ready
            })
            // a new application ends a swipe still settling
            transitions.endEdgeSwipe()
            setCurrentWindow(w)
        }
    }

    onWindowRaised: (window) => windowToFront(window.windowId)

    onWindowRemoved: (window) => {
        var w = window.userData;
        var id = window.windowId
        if (alertWindow == w) {
            alertWindow = null
            alertHidden = false
            // the application under it is there again
            if (topmostWindow && topmostWindow.window)
                topmostWindow.window.takeFocus()
        } else if (comp.topmostWindow == w) {
            setCurrentWindow(null); // reveal the home screen underneath
        }
        if (topmostApplicationWindow == w)
            topmostApplicationWindow = null
        delete meta[id]
        countHidden()
        scheduleFreeze()

        if (window.userData)
            window.userData.destroy()
    }
}
