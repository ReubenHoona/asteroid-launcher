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
import "windowmotion.js" as WM

/* How application windows come and go (split out of compositor.qml), as the
 * stock Wear OS shell does it (W2-launcher-window-motion):
 *
 *  - the launch (WearAppLaunchMixinTransition): the opening window, or the
 *    launch splash that stands for it, zooms 0.45 -> 1 about the centre on a
 *    spring (damping 1.0, stiffness 260) with a quick fade (stiffness 5000),
 *    while the face or the app list behind it shrinks to 0.70 under a black
 *    dim of 0.5. `launch` holds those springs (AppOpen).
 *  - the crown in an app (WearOpenWatchfaceMixinTransition): the app shrinks
 *    to 0.60 on stiffness 500 and fades out (50 ms from 100 ms) while the
 *    face grows from 0.5 on stiffness 260 over black. `reveal`.
 *  - the swipe right (CrossTaskBackAnimation), from the edge
 *    (BorderGestureArea) or from anywhere (lipstick's backSwipe*): the app
 *    shrinks to 0.70 with its right edge on the screen's right edge, the face
 *    behind grows 0.85 -> 0.93, both dimmed; past the commit rule the app's
 *    left edge springs off the screen (stiffness 600); else the progress
 *    springs back (stiffness 1500).
 *
 * What the compositor draws is read from the properties below (appScale,
 * appX, appAlpha, appDim for the application layer; homeScale, homeAlpha,
 * homeDim, homeMoving for the home screen); compositor.qml applies them.
 * Nothing runs unless a transition does: the springs sit still at rest and
 * there is no timer. Instantiated once in compositor.qml as `transitions` at
 * z 5 (the edge swipe's z), under the corner mask (6). Reads compositor.qml's
 * ids (root, comp, appLayer) through the context. Owned by
 * W2-launcher-window-motion. */
Item {
    id: transitions
    anchors.fill: parent
    z: 5

    readonly property Item gestureArea: edgeSwipe
    readonly property QtObject launch: launchMotion
    readonly property QtObject reveal: revealMotion
    readonly property real w: root ? root.width : Dims.w(100)

    /* ---- what the layers do now ------------------------------------- */

    // a back swipe is going on (the finger, the way back or the way off)
    property bool backActive: false
    // it was let go past the commit rule: the app's left edge springs off
    property bool committing: false
    // the crown in an app: the way back to the face
    property bool closing: false
    readonly property bool launching: launchMotion.inProgress

    // "": nothing moves; launch, home (the crown), swipe, commit
    readonly property string layerMode: backActive ? (committing ? "commit" : "swipe")
                                        : (closing ? "home" : (launching ? "launch" : ""))
    // the window leaves under a finger or on its own (the circle mask is on)
    readonly property bool windowMoving: backActive || closing
    readonly property bool homeMoving: layerMode !== ""

    // the swipe's geometry at the smoothed progress, or in the commit
    property real _commitLeft0: 0
    property real _commitHomeDim0: 0
    property real _commitAppDim0: 0
    readonly property var _back: committing
        ? WM.commit(commitSpring.value, _commitLeft0, _commitHomeDim0, _commitAppDim0, w)
        : WM.back(backSpring.value, w)

    // the application layer
    readonly property real appScale: backActive ? _back.appScale : (closing ? revealMotion.topScale : 1)
    // the left edge at appLeft: the scaled window's own left edge is w (1 - s) / 2
    readonly property real appX: backActive ? _back.appLeft - w * (1 - _back.appScale) / 2 : 0
    readonly property real appAlpha: !backActive && closing ? revealMotion.topAlpha : 1
    readonly property real appDim: backActive ? _back.appDim : 0

    // the home screen
    readonly property real homeScale: backActive ? _back.homeScale
                                      : (closing ? revealMotion.faceScale : (launching ? launchMotion.behindScale : 1))
    readonly property real homeAlpha: !backActive && closing ? revealMotion.faceAlpha : 1
    readonly property real homeDim: backActive ? _back.homeDim
                                    : (!closing && launching ? launchMotion.behindDim : 0)

    /* ---- the launch ---------------------------------------------------- */

    AppOpen { id: launchMotion }

    // the window that opens with the launch springs (and its layer)
    property Item _opener: null
    property Item _openerLayer: null

    /* A window comes to the front. Over the launch splash the springs are
     * already running (the splash is the opening window); the window scales
     * with them. Without a splash (a hidden app coming back, an alarm) the
     * springs start now. Not with the display off: nothing is drawn. */
    function openWindow(win, overSplash) {
        if (!win)
            return
        var animate = !(comp && comp.displayIsOff)
        if (animate && !launchMotion.inProgress && !overSplash)
            launchMotion.start()
        var running = launchMotion.inProgress
        if (_opener && _opener !== win)
            _opener.opening = false
        win.motion = launchMotion
        win.opening = running
        _opener = running ? win : null
        _openerLayer = win.parent
        if (win.parent)
            win.parent.ready = !running
    }

    Connections {
        target: launchMotion
        function onFinished() {
            if (transitions._opener)
                transitions._opener.opening = false
            transitions._opener = null
            if (transitions._openerLayer)
                transitions._openerLayer.ready = true
        }
    }

    /* ---- the crown in an app: back to the face --------------------------- */

    WatchfaceReveal { id: revealMotion }

    /* The old name of the crown close's progress (0 -> 1) */
    readonly property real closeProgress: closing ? revealMotion.a : 0

    function closeTopmost() {
        if (closing || backActive || !comp.topmostWindow)
            return
        Desktop.desktop.aboutToClose = true
        closing = true
        revealMotion.start()
    }

    Connections {
        target: revealMotion
        function onFinished() {
            if (!transitions.closing)
                return
            // to the background, not closed (AppLifecycle.leaveApp)
            comp.leaveApp(comp.topmostWindow)
            transitions.closing = false
            Desktop.desktop.aboutToClose = false
        }
    }

    /* ---- the back swipe ---------------------------------------------------- */

    // the finger's progress (0..1 of the width) and what the smoothing spring makes of it
    property real backRaw: 0
    property bool _finger: false
    property bool _releasing: false
    property real _lastRaw: 0
    property bool _armed: false
    property real _lastClick: 0

    WearSpring {
        id: backSpring
        to: transitions.backRaw
        stiffness: WM.BACK.smooth.stiffness
        dampingRatio: WM.BACK.smooth.dampingRatio
        visibilityThreshold: 0.0005
        // the cancel came to rest
        onFinished: if (transitions._releasing && !transitions.committing) transitions._finishBack()
    }

    WearSpring {
        id: commitSpring
        stiffness: WM.BACK.commit.stiffness
        dampingRatio: WM.BACK.commit.dampingRatio
        stopAtFraction: WM.BACK.commit.stopAtFraction
        visibilityThreshold: WM.BACK.commit.visibleChange
        onFinished: if (transitions.committing) transitions._committed()
    }

    // a finger went down on a back swipe
    function beginBack() {
        commitSpring.stop()
        committing = false
        _releasing = false
        _lastRaw = 0
        _armed = false
        backRaw = 0
        backSpring.snapTo(0)
        _finger = true
        backActive = true
    }

    /* The finger is px to the right of where the swipe started. haptic:
     * the threshold click at 0.33 of the width (the edge swipe's own
     * BorderGestureArea plays it for the edge swipe) */
    function feedBack(px, haptic) {
        if (!_finger)
            return
        var r = Math.max(0, Math.min(1, px / w))
        if (haptic) {
            var armed = r > Motion.backGesture.commitFraction && r >= _lastRaw
            if (armed && !_armed) {
                var now = Date.now()
                if (now - _lastClick >= Motion.backGesture.hapticIntervalMs) {
                    _lastClick = now
                    Haptics.click()
                }
            }
            _armed = armed
        }
        _lastRaw = r
        backRaw = r
    }

    // the finger lifted: past the commit rule the app goes, else it comes back
    function endBack(commit) {
        if (!_finger)
            return
        _finger = false
        _releasing = true
        if (commit) {
            var b = WM.back(backSpring.value, w)
            _commitLeft0 = b.appLeft
            _commitHomeDim0 = b.homeDim
            _commitAppDim0 = b.appDim
            committing = true
            backSpring.stop()
            commitSpring.snapTo(b.appLeft)
            commitSpring.animateTo(w)
        } else {
            backRaw = 0
            if (backSpring.value < 0.001)
                _finishBack()
        }
    }

    function _committed() {
        // to the background, not closed (AppLifecycle.leaveApp)
        comp.leaveApp(comp.topmostWindow)
        _finishBack()
    }

    // the swipe is over: the layers are as they were
    function _finishBack() {
        commitSpring.stop()
        committing = false
        _releasing = false
        _finger = false
        backActive = false
        backRaw = 0
        backSpring.snapTo(0)
        anywhereActive = false
        anywhereValue = 0
        Desktop.desktop.aboutToMinimize = false
        Desktop.desktop.aboutToClose = false
        edgeSwipe.endGesture()
    }

    // a new application ends a swipe still settling (AppLifecycle)
    function endEdgeSwipe() {
        if (edgeSwipe.active)
            _finishBack()
    }

    // the display went off: what moves lands where it was going
    function settleAll() {
        launchMotion.settle()
        if (closing)
            revealMotion.settle()
        if (backActive && _releasing) {
            if (committing) {
                commitSpring.stop()
                _committed()
            } else {
                _finishBack()
            }
        }
    }

    Connections {
        target: comp
        ignoreUnknownSignals: true
        function onDisplayOff() { transitions.settleAll() }
    }

    BorderGestureArea {
        id: edgeSwipe
        enabled: comp ? comp.appActive && !root.assistantShown && !comp.alertShown && !root.systemModal : false
        z: 5
        anchors.fill: parent
        // stock has no system gesture from the top edge inside an app
        // (buttons-navigation-10, DECISIONS Q33: swipe-down-to-close removed)
        acceptsDown: false
        acceptsRight: comp != null && comp.topmostWindow != null && !comp.topmostWindowRequestsGesturesDisabled

        // The gesture (its direction and value) stays set until the
        // window has settled back or left: the animations above run on it
        function endGesture() {
            delayReset = false
            Desktop.desktop.aboutToClose = false
            Desktop.desktop.aboutToMinimize = false
        }

        onGestureStarted: (gesture) => {
            transitions.beginBack()
            delayReset = true
            if (gesture == "down") {
                Desktop.desktop.aboutToClose = true
            } else if(gesture == "right") {
                Desktop.desktop.aboutToMinimize = true
            }
        }

        // 1:1 with the finger (stock progress is dx / W, smoothed by backSpring)
        onValueChanged: transitions.feedBack(Math.abs(value), false)

        // the stock rule (BorderGestureArea.committed, set before this signal):
        // 500 dp/s or past lerp(0.33, 0.10, v / 500 dp/s) of the width
        onGestureFinished: (gesture) => {
            transitions.endBack((gesture == "down" || gesture == "right") && edgeSwipe.committed)
        }
    }

    /* Back from anywhere, as Wear OS at the root of an application: the
     * client allows it per touch (qml-asteroid Application.backFromAnywhere,
     * the gestures protocol's set_back_from_anywhere), lipstick takes a
     * swipe right from anywhere on the window (more than 32 px, within 45
     * degrees) and says so here; the window follows the finger as with the
     * edge swipe and goes on the same commit rule */
    property bool anywhereActive: false
    property real anywhereValue: 0
    readonly property Item _topWindowItem: comp.topmostWindow ? comp.topmostWindow.window : null
    // The swipe ends with its window: once the window that would send
    // backSwipeFinished is no longer in front (the application closed or
    // crashed, delayTimer closed it with the display off, another came to
    // the front), nothing finishes it, and the home screen stayed under
    // the dismiss dim with the application layer shown (dismissing)
    on_TopWindowItemChanged: {
        if (transitions.anywhereActive && !transitions._releasing)
            transitions._finishBack()
    }

    Connections {
        target: transitions._topWindowItem
        ignoreUnknownSignals: true
        function onBackSwipeStarted() {
            if (transitions.closing || edgeSwipe.active || transitions.backActive)
                return
            transitions.anywhereValue = 0
            transitions.anywhereActive = true
            transitions.beginBack()
            Desktop.desktop.aboutToMinimize = true
        }
        function onBackSwipeMoved(value) {
            if (transitions.anywhereActive && transitions._finger) {
                transitions.anywhereValue = Math.min(value, transitions.w)
                transitions.feedBack(value, true)
            }
        }
        function onBackSwipeFinished(value, velocity) {
            if (!transitions.anywhereActive || !transitions._finger)
                return
            // the stock decision (Motion.backShouldCommit; the last step is not
            // known here and counts as forward)
            transitions.endBack(Motion.backShouldCommit(value, velocity, 0, transitions.w, Theme.dp(1)))
        }
    }
}
