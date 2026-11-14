/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/* A check mark in a scalloped badge that draws itself in `duration` ms (stock: a Lottie of a check in a
 * scalloped shape, 1000 ms; ours is made of three rotated rounded squares, which make a 12 lobed scallop, and
 * the mark of the icon set). Used by Setup complete (122 dp) and the tutorial (96 dp). Nothing runs once the
 * animation has ended; under Reduce animations it is drawn finished at once. */
Item {
    id: check
    objectName: "setupCheck"

    property real size: Theme.dp(122)
    property int duration: 1000
    property color badgeColor: Theme.color.primary
    property color markColor: Theme.color.onPrimary
    // 0 .. 1 over `duration`
    property real progress: 0
    readonly property bool running: anim.running
    // the scalloped badge is drawn in the middle of the box, as the Lottie's art sits inside its canvas
    readonly property real badgeSize: size * 0.62
    readonly property real badgeScale: _out(Math.min(1, progress / 0.55))
    readonly property real markProgress: Math.max(0, Math.min(1, (progress - 0.4) / 0.6))

    width: size
    height: size

    // ease out with a little overshoot
    function _out(x) {
        var c1 = 1.2, c3 = c1 + 1
        return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2)
    }

    function play() {
        progress = 0
        anim.restart()
    }

    Repeater {
        model: 3
        Rectangle {
            required property int index
            anchors.centerIn: parent
            width: check.badgeSize * 0.78
            height: width
            radius: width * 0.3
            rotation: index * 30
            color: check.badgeColor
            scale: check.badgeScale
        }
    }

    Icon {
        id: mark
        anchors.centerIn: parent
        width: check.badgeSize * 0.62
        height: width
        name: "ios-checkmark"
        color: check.markColor
        opacity: check.markProgress
        scale: 0.6 + 0.4 * check.markProgress
    }

    NumberAnimation {
        id: anim
        target: check
        property: "progress"
        from: 0
        to: 1
        duration: Motion.duration(check.duration)
        easing.type: Easing.Linear
    }

    Accessible.role: Accessible.Graphic
    Accessible.ignored: true
}
