/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick

/*
 * The assistant's four dots, as on Wear OS: they rise as a row while it
 * waits for the microphone ("starting"), bounce with the voice while it
 * listens (each dot with its own phase, height from the microphone level),
 * and turn into a ring that spins while it works out the answer
 * ("thinking"). They animate only in those states (at the display rate, on
 * Qt Quick's animation driver): with a result on screen nothing moves.
 */
Item {
    id: dots

    // starting | listening | thinking | hidden
    property string mode: "hidden"
    // 0 .. 1, from the daemon's Level signal (about 25 a second)
    property real level: 0
    readonly property bool animating: visible && (mode === "starting" || mode === "listening" || mode === "thinking")

    readonly property real d: Math.round(width * 0.14)
    readonly property var colors: ["#4285f4", "#ea4335", "#fbbc04", "#34a853"]

    // the level eases in, so 25 updates a second still move smoothly
    property real smoothLevel: 0
    Behavior on smoothLevel { enabled: dots.animating; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
    onLevelChanged: smoothLevel = mode === "listening" ? level : 0
    onModeChanged: if (mode !== "listening") smoothLevel = 0

    // 0: a row, 1: a ring (thinking)
    property real ring: mode === "thinking" ? 1 : 0
    Behavior on ring { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] } }
    // 0: away, 1: shown
    property real presence: mode === "hidden" ? 0 : 1
    Behavior on presence { NumberAnimation { duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1] } }

    // one turn of the bounce / spin
    property real phase: 0
    NumberAnimation on phase {
        running: dots.animating
        loops: Animation.Infinite
        from: 0
        to: 2 * Math.PI
        duration: dots.mode === "thinking" ? 1100 : 1400
    }

    Repeater {
        model: 4
        Rectangle {
            readonly property real step: dots.d * 1.45
            readonly property real rowX: (index - 1.5) * step
            readonly property real angle: dots.phase + index * Math.PI / 2
            readonly property real ringR: dots.d * 1.1
            // listening: the dot grows into a bar with the voice
            readonly property real wave: 0.55 + 0.45 * Math.sin(dots.phase * 2 + index * 1.3)
            readonly property real stretch: dots.mode === "starting"
                                            ? 0.12 * (1 + Math.sin(dots.phase + index * 0.8))
                                            : 2.2 * dots.smoothLevel * wave
            width: dots.d
            height: dots.d * (1 + stretch * (1 - dots.ring))
            radius: width / 2
            color: dots.colors[index]
            x: dots.width / 2 - width / 2 + (rowX * (1 - dots.ring) + ringR * Math.cos(angle) * dots.ring)
            y: dots.height / 2 - height / 2 + ringR * Math.sin(angle) * dots.ring
               + (1 - dots.presence) * dots.d * 2
            opacity: dots.presence
            scale: 0.4 + 0.6 * dots.presence
            antialiasing: true
        }
    }
}
