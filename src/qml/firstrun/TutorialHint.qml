/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "tutorial.js" as Tut

/* The gesture hints of the tutorial (setup-wizard-01): a fingertip that does the gesture over a faint track,
 * looping every 2 s: vertical 40 x 96 dp (swipe up or down), horizontal 140 x 40 dp (left, right or both ways),
 * the crown press 60 x 44 dp (0.75 s) and the side button press (the same pill, at the side). Stock plays
 * Lottie files of these; these are our own drawings with the stock sizes and loops.
 *
 * Power (M1): one number animation, running only while `running` (the display on, the step shown). */
Item {
    id: hint
    objectName: "tutorialHint"

    // "vertical", "horizontal", "crown" or "side"
    property string kind: "vertical"
    // "up", "down", "left", "right" or "both"
    property string dir: "up"
    property bool running: true
    // 0 .. 1 over one loop
    property real t: 0

    readonly property real trackW: kind === "vertical" ? Theme.dp(Tut.hints.vertical.widthDp)
                                   : kind === "horizontal" ? Theme.dp(Tut.hints.horizontal.widthDp)
                                   : Theme.dp(Tut.hints.crown.widthDp)
    readonly property real trackH: kind === "vertical" ? Theme.dp(Tut.hints.vertical.heightDp)
                                   : kind === "horizontal" ? Theme.dp(Tut.hints.horizontal.heightDp)
                                   : Theme.dp(Tut.hints.crown.heightDp)
    readonly property int loopMs: kind === "crown" || kind === "side" ? Tut.hints.crown.loopMs : Tut.hints.loopMs
    readonly property real fingerSize: Theme.dp(kind === "vertical" || kind === "horizontal" ? 20 : 16)
    // the finger's place along the track, 0 .. 1, in the direction of the gesture; both ways = out and back
    readonly property real along: {
        if (dir === "both")
            return t < 0.5 ? t * 2 : 2 - t * 2
        return t
    }
    // the touch: the finger fades in at the start and out at the end of each pass
    readonly property real touch: t < 0.12 ? t / 0.12 : (t > 0.88 ? (1 - t) / 0.12 : 1)

    width: trackW
    height: trackH

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: "transparent"
        border.width: Theme.dp(2)
        border.color: Theme.color.onSurfaceVariant
        opacity: 0.45
    }

    Rectangle {
        id: finger
        objectName: "tutorialHintFinger"
        width: hint.fingerSize
        height: width
        radius: width / 2
        color: Theme.color.primary
        opacity: 0.9 * hint.touch
        scale: hint.kind === "crown" || hint.kind === "side" ? 1 - 0.25 * Math.sin(hint.t * Math.PI) : 1
        x: {
            if (hint.kind === "horizontal") {
                var f = hint.dir === "right" ? hint.along : 1 - hint.along
                if (hint.dir === "both") f = hint.along
                return (hint.width - width) * f
            }
            return (hint.width - width) / 2
        }
        y: {
            if (hint.kind === "vertical") {
                var f = hint.dir === "up" ? 1 - hint.along : hint.along
                return (hint.height - height) * f
            }
            return (hint.height - height) / 2
        }
    }

    NumberAnimation {
        target: hint
        property: "t"
        from: 0
        to: 1
        duration: hint.loopMs
        loops: Animation.Infinite
        running: hint.running && !Motion.reduceMotion
        easing.type: Easing.Linear
        onRunningChanged: if (!running) hint.t = 0
    }
}
