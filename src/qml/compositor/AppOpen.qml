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
    readonly property real scale: WM.LAUNCH.startScale + (1 - WM.LAUNCH.startScale) * p
    readonly property real alpha: fade
    readonly property real behindScale: 1 - WM.LAUNCH.behindDrop * p
    readonly property real behindDim: WM.LAUNCH.behindDim * p
    readonly property bool inProgress: base.running || fadeSpring.running

    signal finished()

    property int _pending: 0

    /* From `from` (0: closed) to open. A list pulled in by a finger starts
     * where the finger left it. */
    function start(from) {
        var f = from === undefined ? 0 : from
        _pending = 2
        base.snapTo(f)
        fadeSpring.snapTo(f)
        base.animateTo(1)
        fadeSpring.animateTo(1)
    }

    // stops where it is (another motion takes over)
    function stop() {
        base.stop()
        fadeSpring.stop()
        _pending = 0
    }

    // the end at once (the display went off, a cancel)
    function settle() {
        var was = _pending > 0
        base.stop()
        fadeSpring.stop()
        base.snapTo(1)
        fadeSpring.snapTo(1)
        _pending = 0
        if (was)
            finished()
    }

    function _one() {
        if (_pending > 0 && --_pending === 0)
            finished()
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
