/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "faceeditor.js" as FE

/*
 * The crown selector indicator of a list setting page: stock's RSBControl of
 * type "selector" (epq.java, RSBControl.java). A 51 degree track on the right
 * edge (6 dp wide, 8 dp from the edge, #4dffffff) and a thumb the length of one
 * option's share of it, in the primary colour, that moves to the new option in
 * 450 ms. It is hidden until the option changes: it then fades in with a scale
 * from 0.65 over 250 ms, stays 1.2 s and fades out (RSBControl.a(), epo.java).
 * It fills its parent; nothing runs while it is hidden.
 */
Item {
    id: sel

    // the number of options and the option on show
    property int count: 0
    property int index: 0
    // 0..1: how much of the indicator shows (opacity, and the scale from 0.65)
    property real level: 0
    // where the thumb is, in options (animated)
    property real position: index
    readonly property bool animating: moveAnim.running || showAnim.running

    anchors.fill: parent
    enabled: false
    opacity: level
    visible: level > 0
    transform: Scale {
        origin.x: sel.width / 2
        origin.y: sel.height / 2
        xScale: 1
        yScale: FE.SELECTOR_MIN_SCALE + (1 - FE.SELECTOR_MIN_SCALE) * sel.level
    }

    readonly property real stroke: Theme.dp(FE.SELECTOR_STROKE_DP)
    readonly property real radius: Math.min(width, height) / 2 - Theme.dp(FE.SELECTOR_OUTSIDE_DP) - stroke / 2
    readonly property var thumb: FE.selectorThumb(position, count)

    // the option changed: the thumb moves, the indicator shows
    onIndexChanged: {
        if (count < 2)
            return
        moveAnim.stop()
        moveAnim.from = position
        moveAnim.to = index
        moveAnim.duration = Motion.duration(FE.SELECTOR_MOVE_MS)
        moveAnim.restart()
        show()
    }
    function show() {
        showAnim.stop()
        fadeIn.duration = Math.round((1 - level) * FE.SELECTOR_FADE_MS * Motion.animationScale)
        fadeOut.duration = Math.round(FE.SELECTOR_FADE_MS * Motion.animationScale)
        hold.duration = Math.round(FE.SELECTOR_HOLD_MS * Motion.animationScale)
        showAnim.restart()
    }
    function hideNow() {
        showAnim.stop()
        moveAnim.stop()
        level = 0
        position = index
    }

    NumberAnimation {
        id: moveAnim
        target: sel
        property: "position"
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easing.legacy
    }
    SequentialAnimation {
        id: showAnim
        NumberAnimation { id: fadeIn; target: sel; property: "level"; to: 1; easing.type: Easing.OutCubic }
        PauseAnimation { id: hold }
        NumberAnimation { id: fadeOut; target: sel; property: "level"; to: 0; easing.type: Easing.OutCubic }
    }

    Shape {
        id: arcs
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: FE.SELECTOR_TRACK
            strokeWidth: sel.stroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: sel.width / 2; centerY: sel.height / 2
                radiusX: sel.radius; radiusY: sel.radius
                startAngle: -FE.SELECTOR_SWEEP / 2
                sweepAngle: FE.SELECTOR_SWEEP
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.color.primary
            strokeWidth: sel.stroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: sel.width / 2; centerY: sel.height / 2
                radiusX: sel.radius; radiusY: sel.radius
                startAngle: sel.thumb.start
                sweepAngle: sel.thumb.sweep
            }
        }
    }
}
