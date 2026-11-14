/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "lock.js" as Lock

/*
 * The pattern pad (W3-launcher-a11y-security, accessibility-lock-security-08):
 * 3 x 3 dots, 19 % padding, M3 primary-fixed-dim colours (primaryDim here), a
 * padlock above it with a 5 dp top margin. The finger draws a line through
 * the dots it meets; a dot skipped in a straight line is taken as well
 * (0 to 2 takes 1). Lifting the finger gives the pattern, the dots in order
 * as a string ("0124"): fewer than 4 dots is "Connect at least 4 dots"
 * (tooShort(), not a try, and shown red 2000 ms); a wrong pattern shows red
 * for 2000 ms (stock LockPatternListener).
 *
 * `inputEnabled: false` (a wait after too many tries) dims the dots to 50 %
 * and takes no touch.
 */
Item {
    id: pad
    objectName: "patternPad"

    property bool inputEnabled: true
    // the dots touched so far, in order (0..8)
    property var dots: []
    // red for 2000 ms after a wrong or too short pattern
    property bool errorShown: false
    // the finger, in the pad's coordinates
    property point finger: Qt.point(0, 0)
    property bool drawing: false

    readonly property real side: Math.min(width, height)
    // the pad's own square: 19 % padding at the sides
    readonly property real boxPadding: Lock.PATTERN_PADDING * width
    readonly property real gridSize: Math.min(width - 2 * boxPadding, height - 2 * boxPadding)
    readonly property real cell: gridSize / 3
    readonly property real dotSize: Theme.dp(14)
    readonly property real hitRadius: cell * 0.4
    readonly property real gridLeft: (width - gridSize) / 2
    readonly property real gridTop: (height - gridSize) / 2
    readonly property real lineWidth: Theme.dp(4)
    readonly property color lineColor: errorShown ? Theme.color.errorDim : Theme.color.primaryDim
    readonly property alias errorTimer: errorTimer
    readonly property alias padlock: lockIcon

    // the pattern as a string, the finger lifted
    signal completed(string pattern)
    // fewer than 4 dots
    signal tooShort()

    function dotCenter(d) {
        return Qt.point(gridLeft + (d % 3 + 0.5) * cell, gridTop + (Math.floor(d / 3) + 0.5) * cell)
    }

    function dotAt(x, y) {
        for (var d = 0; d < 9; d++) {
            var c = dotCenter(d)
            var dx = x - c.x, dy = y - c.y
            if (dx * dx + dy * dy <= hitRadius * hitRadius)
                return d
        }
        return -1
    }

    function reset() {
        dots = []
        drawing = false
        errorShown = false
        errorTimer.stop()
    }

    function showError() {
        errorShown = true
        errorTimer.restart()
    }

    function touchDown(x, y) {
        if (!inputEnabled)
            return
        errorShown = false
        errorTimer.stop()
        dots = []
        drawing = true
        finger = Qt.point(x, y)
        touchMove(x, y)
    }

    function touchMove(x, y) {
        if (!drawing)
            return
        finger = Qt.point(x, y)
        var d = dotAt(x, y)
        if (d >= 0 && dots.indexOf(d) < 0) {
            dots = Lock.addDot(dots, d)
            Haptics.segmentTick()
        }
    }

    function touchUp() {
        if (!drawing)
            return
        drawing = false
        if (dots.length === 0)
            return
        if (dots.length < Lock.PATTERN_MIN_DOTS) {
            showError()
            tooShort()
            return
        }
        completed(Lock.patternString(dots))
    }

    Timer {
        id: errorTimer
        interval: Lock.PATTERN_ERROR_MS
        onTriggered: pad.reset()
    }

    // the padlock above the dots (it shakes for an error, as stock's lock animation)
    Icon {
        id: lockIcon
        objectName: "patternLock"
        width: Theme.dp(24)
        height: width
        x: (pad.width - width) / 2
        y: Theme.dp(Lock.PATTERN_LOCK_TOP_DP)
        name: "ms-lock"
        color: pad.lineColor
    }

    // the segments between the dots touched, and the one to the finger
    Item {
        anchors.fill: parent
        opacity: pad.inputEnabled ? 1 : 0.5
        Repeater {
            model: Math.max(0, pad.dots.length - 1)
            Rectangle {
                readonly property point a: pad.dotCenter(pad.dots[index])
                readonly property point b: pad.dotCenter(pad.dots[index + 1])
                x: a.x
                y: a.y - pad.lineWidth / 2
                width: Math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
                height: pad.lineWidth
                radius: height / 2
                color: pad.lineColor
                transformOrigin: Item.Left
                rotation: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI
            }
        }
        Rectangle {
            id: tail
            visible: pad.drawing && pad.dots.length > 0 && !pad.errorShown
            readonly property point a: pad.dots.length > 0 ? pad.dotCenter(pad.dots[pad.dots.length - 1]) : Qt.point(0, 0)
            x: a.x
            y: a.y - pad.lineWidth / 2
            width: Math.sqrt((pad.finger.x - a.x) * (pad.finger.x - a.x) + (pad.finger.y - a.y) * (pad.finger.y - a.y))
            height: pad.lineWidth
            radius: height / 2
            color: pad.lineColor
            transformOrigin: Item.Left
            rotation: Math.atan2(pad.finger.y - a.y, pad.finger.x - a.x) * 180 / Math.PI
        }
        Repeater {
            id: dotRepeater
            model: 9
            Rectangle {
                objectName: "patternDot" + index
                readonly property bool active: pad.dots.indexOf(index) >= 0
                readonly property point c: pad.dotCenter(index)
                width: active ? pad.dotSize * 1.5 : pad.dotSize
                height: width
                radius: width / 2
                x: c.x - width / 2
                y: c.y - height / 2
                color: active ? pad.lineColor : Theme.color.onSurfaceVariant
                Behavior on width { NumberAnimation { duration: 80 } }
            }
        }
    }

    MultiPointTouchArea {
        anchors.fill: parent
        enabled: pad.inputEnabled
        mouseEnabled: true
        maximumTouchPoints: 1
        touchPoints: [ TouchPoint { id: tp } ]
        onPressed: pad.touchDown(tp.x, tp.y)
        onUpdated: pad.touchMove(tp.x, tp.y)
        onReleased: pad.touchUp()
        onCanceled: pad.touchUp()
    }

    Accessible.role: Accessible.Pane
    //% "Draw pattern"
    Accessible.name: qsTrId("id-lock-draw-pattern")
}
