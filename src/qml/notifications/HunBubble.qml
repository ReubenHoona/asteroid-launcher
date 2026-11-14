/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "headsup.js" as HU

/*
 * A new notification inside an app or any panel but the face: the icon
 * bubble (audit heads-up-alerts-03, -04, -08; stock CP3A SysUI
 * hun_window_view.xml, ktr.java:116-124, ktk.java:66-71, 149, 191-372,
 * kte.java:58-101): a full-width strip, 48 dp (96 px at 384) peeking up from
 * the bottom edge, a gradient from transparent at 12 dp to black at 48 dp,
 * the app icon centred (a 48 dp touch target with 12 dp padding: a 48 px
 * icon), no text.
 *
 * Springs of damping 1: it rises on stiffness 150 (the icon from scale 0.5 and
 * alpha 0.5 to 1 with it), stays 3000 ms, sinks on 100 (300 when another alert
 * waits) and is gone; the notification stays in the list. A tap on the icon,
 * or a drag up let go with the window top above 45 % of the screen height and
 * no downward fling, expands the full view over the app on stiffness 300 under
 * a black scrim that follows (progress - 96/384) / (1 - 96/384); let go lower
 * or flung down it sinks on 300. Touch counts in the centre +-48 dp and the
 * bottom 48 dp only. Closing the expanded view fades it out in 300 ms (cubic
 * 0, 0, 0.2, 1); the app underneath never closes.
 *
 * p is how high the window's top has come, as a fraction of the screen height:
 * 0 hidden, rest (96/384) the strip, 1 the full view. The full view itself is
 * the preview's (HeadsUpDetail): it follows p. One timer (the 3000 ms stay,
 * a single shot); nothing runs once the bubble is gone.
 */
Item {
    id: bubble

    property QtObject notification: null
    // another alert waits behind this one: it sinks faster (k = 300)
    property bool queued: false
    readonly property real u: width / 384

    property real p: 0
    readonly property real rest: HU.restProgress(height, u)
    // idle, rising, staying, sinking, expanding, expanded, closing
    property string phase: "idle"
    readonly property bool dragging: drag.active
    readonly property bool expanded: phase === "expanding" || phase === "expanded"
    // 1 .. 0 while the expanded view fades out
    property real closeOpacity: 1
    readonly property real scrim: HU.scrimOpacity(p, height, u)
    // the full view's window is up (the preview shows it)
    readonly property bool windowUp: p > rest + 0.001 && phase !== "idle"

    // the bubble is gone (sunk, closed, dismissed): the preview moves on
    signal finished()

    readonly property QtObject spring: pSpring
    readonly property Item hitArea: hit
    readonly property Item stripItem: strip
    readonly property Item iconItem: iconCircle
    readonly property Timer stayTimer: stay

    function accentOf(n) {
        var h = n && n.hints ? n.hints["x-asteroid-accent-color"] : undefined
        var c = h ? String(h).replace("#", "") : ""
        return /^[0-9a-fA-F]{6}$/.test(c) ? "#" + c : Theme.color.primary
    }
    function iconOf(n) {
        function none(s) { return s === "" || s === null || s === undefined }
        if (!n)
            return ""
        if (!none(n.icon)) return n.icon
        if (!none(n.appIcon)) return n.appIcon
        return "ios-mail-outline"
    }

    function _aim(stiffness, to) {
        pSpring.stiffness = stiffness
        pSpring.animateTo(to)
    }

    // from below the edge up to the strip
    function start() {
        stay.stop()
        closeFade.stop()
        closeOpacity = 1
        phase = "rising"
        pSpring.snapTo(0)
        _aim(HU.BUBBLE.riseStiffness, rest)
    }

    // down below the edge, and gone
    function sink() {
        if (phase === "idle" || phase === "sinking")
            return
        stay.stop()
        phase = "sinking"
        _aim(queued ? HU.BUBBLE.sinkQueuedStiffness : HU.BUBBLE.sinkStiffness, 0)
    }

    // up over the app: the full view
    function expand() {
        if (phase === "idle" || phase === "closing" || phase === "expanded" || phase === "expanding")
            return
        stay.stop()
        phase = "expanding"
        _aim(HU.BUBBLE.expandStiffness, 1)
    }

    // the expanded view closes: it fades out in 300 ms, the app stays
    function closeExpanded() {
        if (phase !== "expanded" && phase !== "expanding" && phase !== "rising" && phase !== "staying")
            return
        stay.stop()
        pSpring.stop()
        phase = "closing"
        closeFade.duration = Motion.duration(HU.BUBBLE.closeMs)
        closeFade.restart()
    }

    // away at once (the display went off, an alarm, the next face)
    function dismissNow() {
        stay.stop()
        pSpring.stop()
        closeFade.stop()
        if (phase !== "idle")
            _finish()
    }

    // the finger let go (vy px/s, + down): expand or sink, by stock's rule
    function release(vy) {
        stay.stop()
        pSpring.stop()
        if (HU.releaseExpands(height * (1 - p), vy, height)) {
            phase = "staying"
            expand()
        } else {
            phase = "staying"
            _aimSink()
        }
    }
    function _aimSink() {
        phase = "sinking"
        _aim(HU.BUBBLE.expandStiffness, 0)
    }

    function _finish() {
        phase = "idle"
        pSpring.stop()
        p = 0
        closeOpacity = 1
        finished()
    }

    WearSpring {
        id: pSpring
        target: bubble
        property: "p"
        dampingRatio: 1
        stiffness: HU.BUBBLE.riseStiffness
        visibilityThreshold: 0.001
        onFinished: {
            if (bubble.phase === "rising") {
                bubble.phase = "staying"
                stay.interval = HU.BUBBLE.stayMs
                stay.restart()
            } else if (bubble.phase === "sinking") {
                bubble._finish()
            } else if (bubble.phase === "expanding") {
                bubble.phase = "expanded"
            }
        }
    }

    // the strip stays 3000 ms, a single shot; a finger on it holds it
    Timer {
        id: stay
        repeat: false
        onTriggered: if (!drag.active) bubble.sink()
    }

    NumberAnimation {
        id: closeFade
        target: bubble
        property: "closeOpacity"
        from: 1
        to: 0
        easing.type: Easing.BezierSpline
        easing.bezierCurve: HU.BUBBLE.closeEasing
        onFinished: bubble._finish()
    }

    // the black scrim over the app that follows the window up; it takes the touches
    // once the window is up, so nothing under reaches the app
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: bubble.scrim * bubble.closeOpacity
        visible: opacity > 0
        MouseArea {
            anchors.fill: parent
            enabled: bubble.windowUp
        }
    }

    // the strip: transparent down to 12 dp, black at 48 dp
    Rectangle {
        id: strip
        width: bubble.width
        height: Math.round(HU.BUBBLE.stripHeight * bubble.u)
        y: bubble.height * (1 - bubble.p)
        visible: bubble.phase !== "idle"
        opacity: bubble.p <= bubble.rest ? 1 : Math.max(0, 1 - (bubble.p - bubble.rest) * 4)
        gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: HU.BUBBLE.gradientFrom / HU.BUBBLE.stripHeight; color: "#00000000" }
            GradientStop { position: 1; color: "#FF000000" }
        }

        // the icon grows from 0.5 / alpha 0.5 with the rise
        Rectangle {
            id: iconCircle
            readonly property real f: Math.max(0, Math.min(1, bubble.p / bubble.rest))
            width: Math.round(HU.BUBBLE.icon * bubble.u)
            height: width
            radius: width / 2
            x: (strip.width - width) / 2
            y: (strip.height - height) / 2
            color: bubble.accentOf(bubble.notification)
            scale: HU.BUBBLE.iconScaleFrom + (1 - HU.BUBBLE.iconScaleFrom) * f
            opacity: HU.BUBBLE.iconAlphaFrom + (1 - HU.BUBBLE.iconAlphaFrom) * f
            Icon {
                anchors.centerIn: parent
                width: Math.round(parent.width * 0.75)
                height: width
                name: bubble.iconOf(bubble.notification)
                color: Theme.color.onPrimary
            }
        }
    }

    // the touch area: the centre +-48 dp and the bottom 48 dp
    Item {
        id: hit
        x: (bubble.width - width) / 2
        y: bubble.height - height
        width: 2 * HU.BUBBLE.hitHalfWidth * bubble.u
        height: HU.BUBBLE.hitHeight * bubble.u
        enabled: bubble.phase === "rising" || bubble.phase === "staying"

        TapHandler {
            onTapped: bubble.expand()
        }
        DragHandler {
            id: drag
            target: null
            xAxis.enabled: false
            onTranslationChanged: {
                if (!active)
                    return
                pSpring.stop()
                var q = bubble.rest - translation.y / bubble.height
                bubble.p = Math.max(0, Math.min(1, q))
            }
            onActiveChanged: {
                if (active) {
                    stay.stop()
                    pSpring.stop()
                } else {
                    bubble.release(centroid.velocity.y)
                }
            }
        }
    }
}
