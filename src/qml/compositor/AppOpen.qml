/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "windowmotion.js" as WM

/*
 * The stock app launch motion (WearAppLaunchMixinTransition, W2-launcher-window-motion):
 * two springs, the baseline (damping 1.0, stiffness 260, the last 2 % skipped)
 * and the fade (damping 1.0, stiffness 5000), both 0 -> 1 from start().
 *
 *   scale       0.45 + 0.55 p   the opening window or list, about the centre
 *   alpha       fade            its opacity
 *   behindScale 1 - 0.3 p       what it opens over (the face, the app list)
 *   behindDim   0.5 p           the black dim on that
 *
 * From a complication or the ongoing-activity chip it is the origin launch
 * instead (motion A2, windowmotion.js ORIGIN): armOrigin(rect) before the
 * launch, and the next start() grows the window out of that rect (dx, dy: its
 * offset from the centre), the face going to 0.85 with no dim.
 *
 * Nothing runs unless started, and with Reduce animations on the springs land
 * at once. inProgress is true only while a spring moves.
 */
Item {
    id: open
    visible: false
    width: 0
    height: 0

    readonly property real p: base.value
    readonly property real fade: fadeSpring.value
    // the origin launch is running (else the launch from the centre)
    property bool fromOrigin: false
    property real _ox: 0
    property real _oy: 0
    property real _ok: 1
    property real _oAlpha: 1
    readonly property var _o: fromOrigin ? WM.origin(posSpring.value, sizeSpring.value, faceSpring.value, _ox, _oy, _ok) : null
    readonly property real scale: _o ? _o.scale : WM.LAUNCH.startScale + (1 - WM.LAUNCH.startScale) * p
    readonly property real dx: _o ? _o.dx : 0
    readonly property real dy: _o ? _o.dy : 0
    readonly property real alpha: _o ? _oAlpha : fade
    readonly property real behindScale: _o ? _o.behindScale : 1 - WM.LAUNCH.behindDrop * p
    readonly property real behindDim: _o ? 0 : WM.LAUNCH.behindDim * p
    readonly property bool inProgress: base.running || fadeSpring.running
                                       || posSpring.running || sizeSpring.running || faceSpring.running || originFade.running

    signal finished()

    property int _pending: 0
    property var _armed: null

    /* The next start() is an origin launch out of rect (in screen px; a screen
     * w x h); null: it is not. A launch arms it just before it starts. */
    function armOrigin(rect, w, h) {
        _armed = null
        if (!rect || !(rect.width > 0) || !(rect.height > 0) || !(w > 0) || !(h > 0))
            return
        // a big element has the intermediate player in stock: the launch from the centre here
        if (rect.width * rect.height > WM.ORIGIN.maxArea * w * h)
            return
        _armed = { x: rect.x + rect.width / 2 - w / 2, y: rect.y + rect.height / 2 - h / 2,
                   k: Math.min(1, Math.max(rect.width, rect.height) / w) }
    }

    /* From `from` (0: closed) to open. A list pulled in by a finger starts
     * where the finger left it. */
    function start(from) {
        var f = from === undefined ? 0 : from
        _stopOrigin()
        if (_armed && f === 0) {
            _ox = _armed.x
            _oy = _armed.y
            _ok = _armed.k
            _armed = null
            fromOrigin = true
            _pending = 4
            base.snapTo(1)
            fadeSpring.snapTo(1)
            posSpring.snapTo(0)
            sizeSpring.snapTo(0)
            faceSpring.snapTo(0)
            _oAlpha = 0
            posSpring.animateTo(1)
            sizeSpring.animateTo(1)
            faceSpring.animateTo(1)
            originFade.start()
            return
        }
        _armed = null
        _pending = 2
        base.snapTo(f)
        fadeSpring.snapTo(f)
        base.animateTo(1)
        fadeSpring.animateTo(1)
    }

    function _stopOrigin() {
        posSpring.stop()
        sizeSpring.stop()
        faceSpring.stop()
        originFade.stop()
        fromOrigin = false
        _oAlpha = 1
    }

    // stops where it is (another motion takes over)
    function stop() {
        base.stop()
        fadeSpring.stop()
        _stopOrigin()
        _pending = 0
    }

    // the end at once (the display went off, a cancel)
    function settle() {
        var was = _pending > 0
        base.stop()
        fadeSpring.stop()
        _stopOrigin()
        base.snapTo(1)
        fadeSpring.snapTo(1)
        _pending = 0
        if (was)
            finished()
    }

    function _one() {
        if (_pending > 0 && --_pending === 0) {
            fromOrigin = false
            _oAlpha = 1
            finished()
        }
    }

    // the origin launch (A2): position, size, the face, and the 50 ms fade after 50 ms
    WearSpring {
        id: posSpring
        stiffness: WM.ORIGIN.position.stiffness
        dampingRatio: WM.ORIGIN.position.dampingRatio
        visibilityThreshold: WM.ORIGIN.visibleChange
        onFinished: if (open.fromOrigin) open._one()
    }
    WearSpring {
        id: sizeSpring
        stiffness: WM.ORIGIN.size.stiffness
        dampingRatio: WM.ORIGIN.size.dampingRatio
        visibilityThreshold: WM.ORIGIN.visibleChange
        onFinished: if (open.fromOrigin) open._one()
    }
    WearSpring {
        id: faceSpring
        stiffness: WM.ORIGIN.face.stiffness
        dampingRatio: WM.ORIGIN.face.dampingRatio
        visibilityThreshold: WM.ORIGIN.visibleChange
        onFinished: if (open.fromOrigin) open._one()
    }
    SequentialAnimation {
        id: originFade
        PauseAnimation { duration: Motion.duration(WM.ORIGIN.fadeDelayMs) }
        NumberAnimation {
            target: open; property: "_oAlpha"; to: 1
            duration: Motion.duration(WM.ORIGIN.fadeMs); easing.type: Easing.Linear
        }
        ScriptAction { script: if (open.fromOrigin) open._one() }
    }

    WearSpring {
        id: base
        stiffness: WM.LAUNCH.baseline.stiffness
        dampingRatio: WM.LAUNCH.baseline.dampingRatio
        stopAtFraction: WM.LAUNCH.baseline.stopAtFraction
        visibilityThreshold: 0.001
        onFinished: open._one()
    }

    WearSpring {
        id: fadeSpring
        stiffness: WM.LAUNCH.fade.stiffness
        dampingRatio: WM.LAUNCH.fade.dampingRatio
        stopAtFraction: WM.LAUNCH.fade.stopAtFraction
        visibilityThreshold: 0.001
        onFinished: open._one()
    }
}
