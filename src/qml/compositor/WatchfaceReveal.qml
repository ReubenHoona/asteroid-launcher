/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "windowmotion.js" as WM

/*
 * The stock way back to the watch face (WearOpenWatchfaceMixinTransition,
 * W2-launcher-window-motion): the crown in an app, the app list closing.
 *
 *   top (the closing app or list): scale 1 - 0.4 a on damping 1.0 /
 *       stiffness 500 (98 % at ~261 ms); alpha 1 -> 0 linearly over 50 ms
 *       starting at 100 ms
 *   face (home + wallpaper, over black): scale and alpha 0.5 + 0.5 q on
 *       damping 1.0 / stiffness 260 (98 % at ~362 ms)
 *
 * finished() when both springs have ended. Nothing runs unless started; with
 * Reduce animations on everything lands at once.
 */
Item {
    id: reveal
    visible: false
    width: 0
    height: 0

    readonly property real a: topSpring.value
    readonly property real q: faceSpring.value
    property real topAlpha: 1
    readonly property real topScale: 1 - WM.HOME.topDrop * a
    readonly property real faceScale: WM.HOME.faceStart + (1 - WM.HOME.faceStart) * q
    readonly property real faceAlpha: faceScale
    readonly property bool inProgress: topSpring.running || faceSpring.running

    signal finished()

    property int _pending: 0

    /* aFrom: where the top starts (0: full size); a list closing in the
     * middle of its opening continues from the size it has. */
    function start(aFrom) {
        var a0 = aFrom === undefined ? 0 : aFrom
        _pending = 2
        alphaAnim.stop()
        topAlpha = 1
        topSpring.snapTo(a0)
        faceSpring.snapTo(0)
        if (Motion.animationScale > 0)
            alphaAnim.start()
        topSpring.animateTo(1)
        faceSpring.animateTo(1)
    }

    // stops where it is (another motion takes over)
    function stop() {
        topSpring.stop()
        faceSpring.stop()
        alphaAnim.stop()
        _pending = 0
    }

    // the end at once (the display went off)
    function settle() {
        var was = _pending > 0
        topSpring.stop()
        faceSpring.stop()
        alphaAnim.stop()
        topSpring.snapTo(1)
        faceSpring.snapTo(1)
        topAlpha = 0
        _pending = 0
        if (was)
            finished()
    }

    function _one() {
        if (_pending > 0 && --_pending === 0) {
            alphaAnim.stop()
            topAlpha = 0
            finished()
        }
    }

    SequentialAnimation {
        id: alphaAnim
        PauseAnimation { duration: WM.HOME.fadeDelayMs }
        NumberAnimation {
            target: reveal
            property: "topAlpha"
            to: 0
            duration: WM.HOME.fadeMs
            easing.type: Easing.Linear
        }
    }

    WearSpring {
        id: topSpring
        stiffness: WM.HOME.top.stiffness
        dampingRatio: WM.HOME.top.dampingRatio
        stopAtFraction: WM.HOME.top.stopAtFraction
        visibilityThreshold: 0.001
        onFinished: reveal._one()
    }

    WearSpring {
        id: faceSpring
        stiffness: WM.HOME.face.stiffness
        dampingRatio: WM.HOME.face.dampingRatio
        stopAtFraction: WM.HOME.face.stopAtFraction
        visibilityThreshold: 0.001
        onFinished: reveal._one()
    }
}
