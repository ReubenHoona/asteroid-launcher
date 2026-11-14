/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The glow of the assistant (the stock Assistant's glow on the bottom bezel,
 * PixelWatchAssistant qxb/qxf/qxk/qxj/qxo): a sweep of light centred at 6
 * o'clock that opens when the assistant starts, breathes while it waits,
 * widens with the voice, narrows when it is quiet, and carries a bead
 * through the arc while the answer is worked out.
 *
 * Five animated values drive one shader (shaders/assistant-glow.frag, one
 * quad, no offscreen layer): sweepAngle, flourishWidth, flavor,
 * beadPosition and the item's opacity. The timings are stock's
 * (qxf.java:17-31, qxk.java:8-18, qxn.java:6):
 *
 *   start      flourish 0 -> 1.7 in 800 ms (0.2, 0, 0, 1); sweep 0 -> 122.87
 *              degrees in 500 ms (0.2, 0, 0, 1), then -> 37.01 in 1000 ms
 *              (0.33, 0, 0.67, 1); flavor 0 until 600 ms, then -> 1 in 300 ms
 *              linear; then the idle loop 37.01 <-> 122.87 in 1167 ms legs
 *              (0.33, 0, 0.67, 1)
 *   wide       sweep -> 122.87 on a spring (damping 1, stiffness 1500), flavor
 *              -> 2 in 300 ms linear
 *   narrow     sweep -> 37.01 in 900 ms linear
 *   processing flavor -> 1, sweep -> 122.87, the 62 degree bead goes -1 -> 1
 *              in 1410 ms linear, again and again
 *   closed     fade out 160 ms linear, the sweep closes in the same time
 *   fade in    500 ms (0.2, 0, 0, 1)
 *
 * Battery: nothing runs while the mode is closed or the screen is off
 * (screenOn false pauses every animation); the springs and animations stop
 * their frame driver when they rest. Reduce animations jumps to the end
 * values and runs no loop.
 */
Item {
    id: glow

    // closed | idle | wide | narrow | processing
    property string mode: "closed"
    // false while the display is off or dimmed to ambient: everything pauses
    property bool screenOn: true

    // the five animated values (opacity is the item's own)
    property real sweepAngle: 0
    property real flourishWidth: 0
    property real flavor: 1
    property real beadPosition: -1

    // stock's numbers, for the tests and for whoever reads them
    readonly property var spec: ({
        wideDegrees: 122.87,
        narrowDegrees: 37.01,
        beadDegrees: 62,
        flourishTo: 1.7,
        flourishMs: 800,
        sweepOpenMs: 500,
        sweepSettleMs: 1000,
        flavorDelayMs: 600,
        flavorMs: 300,
        idleLoopMs: 1167,
        narrowMs: 900,
        springStiffness: 1500,
        springDamping: 1.0,
        beadMs: 1410,
        fadeInMs: 500,
        fadeOutMs: 160,
        bandHeight: 0.14,
        lineDp: 6
    })
    readonly property bool open: mode !== "closed"
    readonly property bool animating: open && screenOn && !Motion.reduceMotion
        && (sweepStart.running || idleLoop.running || narrowAnim.running || wideSpring.running
            || procSweep.running || beadLoop.running || flavorAnim.running || flourishAnim.running)

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Motion.duration(glow.open ? glow.spec.fadeInMs : glow.spec.fadeOutMs)
            easing.type: glow.open ? Easing.BezierSpline : Easing.Linear
            easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
    }

    // Everything pauses while the display is off (an animation can only be paused while it runs)
    function _applyPause() {
        var all = [flourishAnim, sweepStart, idleLoop, flavorStart, flavorAnim, narrowAnim, procSweep, beadLoop]
        for (var i = 0; i < all.length; i++)
            if (all[i].running)
                all[i].paused = !screenOn
    }
    onScreenOnChanged: _applyPause()

    property string _was: "closed"
    onModeChanged: {
        var from = _was
        _was = mode
        _enter(mode, from)
        _applyPause()
    }

    function _stopAll() {
        sweepStart.stop()
        idleLoop.stop()
        narrowAnim.stop()
        wideSpring.stop()
        procSweep.stop()
        beadLoop.stop()
        flavorStart.stop()
        flavorAnim.stop()
        closeAnim.stop()
    }
    function _reset() {
        sweepAngle = 0
        flourishWidth = 0
        flavor = 1
        beadPosition = -1
    }
    function _flavorTo(v) {
        flavorAnim.stop()
        if (Motion.reduceMotion) {
            flavor = v
            return
        }
        if (flavor === v)
            return
        flavorAnim.to = v
        flavorAnim.start()
    }

    function _enter(m, from) {
        if (m === "closed") {
            _stopAll()
            flourishAnim.stop()
            if (from === "closed" || Motion.reduceMotion || sweepAngle <= 0)
                _reset()
            else
                closeAnim.start()
            return
        }
        if (m === "idle") {
            _stopAll()
            flourishAnim.stop()
            _reset()
            if (Motion.reduceMotion) {
                sweepAngle = spec.wideDegrees
                return
            }
            flavor = 0
            flourishAnim.start()
            sweepStart.start()
            flavorStart.start()
            return
        }
        // the voice and the answer arrive while the start may still run
        sweepStart.stop()
        idleLoop.stop()
        flavorStart.stop()
        narrowAnim.stop()
        wideSpring.stop()
        procSweep.stop()
        beadLoop.stop()
        closeAnim.stop()
        if (from === "closed")
            _reset()
        if (m === "wide") {
            _flavorTo(2)
            if (Motion.reduceMotion) {
                sweepAngle = spec.wideDegrees
                return
            }
            wideSpring.snapTo(sweepAngle)
            wideSpring.animateTo(spec.wideDegrees)
        } else if (m === "narrow") {
            _flavorTo(2)
            if (Motion.reduceMotion) {
                sweepAngle = spec.narrowDegrees
                return
            }
            narrowAnim.from = sweepAngle
            narrowAnim.start()
        } else if (m === "processing") {
            _flavorTo(1)
            beadPosition = -1
            if (Motion.reduceMotion) {
                sweepAngle = spec.wideDegrees
                beadPosition = 0
                return
            }
            procSweep.from = sweepAngle
            procSweep.start()
            beadLoop.start()
        }
    }

    // ---- the animations ----------------------------------------------------

    NumberAnimation {
        id: flourishAnim
        target: glow; property: "flourishWidth"
        from: 0; to: glow.spec.flourishTo
        duration: glow.spec.flourishMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    SequentialAnimation {
        id: sweepStart
        NumberAnimation {
            target: glow; property: "sweepAngle"
            from: 0; to: glow.spec.wideDegrees
            duration: glow.spec.sweepOpenMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
        }
        NumberAnimation {
            target: glow; property: "sweepAngle"
            to: glow.spec.narrowDegrees
            duration: glow.spec.sweepSettleMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.33, 0, 0.67, 1, 1, 1]
        }
        ScriptAction { script: { idleLoop.start(); glow._applyPause() } }
    }
    SequentialAnimation {
        id: idleLoop
        loops: Animation.Infinite
        NumberAnimation {
            target: glow; property: "sweepAngle"
            to: glow.spec.wideDegrees; duration: glow.spec.idleLoopMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.33, 0, 0.67, 1, 1, 1]
        }
        NumberAnimation {
            target: glow; property: "sweepAngle"
            to: glow.spec.narrowDegrees; duration: glow.spec.idleLoopMs
            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.33, 0, 0.67, 1, 1, 1]
        }
    }
    SequentialAnimation {
        id: flavorStart
        PauseAnimation { duration: glow.spec.flavorDelayMs }
        NumberAnimation {
            target: glow; property: "flavor"
            to: 1; duration: glow.spec.flavorMs
        }
    }
    NumberAnimation {
        id: flavorAnim
        target: glow; property: "flavor"
        duration: glow.spec.flavorMs
    }
    WearSpring {
        id: wideSpring
        target: glow; property: "sweepAngle"
        stiffness: glow.spec.springStiffness
        dampingRatio: glow.spec.springDamping
    }
    NumberAnimation {
        id: narrowAnim
        target: glow; property: "sweepAngle"
        to: glow.spec.narrowDegrees; duration: glow.spec.narrowMs
    }
    NumberAnimation {
        id: procSweep
        target: glow; property: "sweepAngle"
        to: glow.spec.wideDegrees; duration: glow.spec.sweepOpenMs
        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    SequentialAnimation {
        id: beadLoop
        loops: Animation.Infinite
        PropertyAction { target: glow; property: "beadPosition"; value: -1 }
        NumberAnimation {
            target: glow; property: "beadPosition"
            to: 1; duration: glow.spec.beadMs
        }
    }
    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: glow; property: "sweepAngle"
            to: 0; duration: glow.spec.fadeOutMs
        }
        ScriptAction { script: if (glow.mode === "closed") glow._reset() }
    }

    // the light: one quad, drawn by the GPU only while it shows
    ShaderEffect {
        anchors.fill: parent
        visible: glow.visible
        property real sweep: glow.sweepAngle
        property real flourish: glow.flourishWidth
        property real flavor: glow.flavor
        property real bead: glow.beadPosition
        property real sizePx: width
        property real linePx: Theme.dp(glow.spec.lineDp) / 2
        fragmentShader: "qrc:/shaders/assistant-glow.frag.qsb"
        blending: true
    }
}
