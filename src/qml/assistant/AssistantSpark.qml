/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes

/*
 * The assistant's mark at the top of its screen (stock shows its 20 dp spark
 * there): our own glyph, a four pointed star with hollow sides, filled with
 * the glow's two blues. It goes away (fade, 250 ms Ease (0.25, 0.1, 0.25, 1),
 * as stock's hide of the icon, rcg.java:70-110) when the microphone button
 * takes its place.
 */
Item {
    id: spark

    // shown: opacity 1; hidden: fades out
    property bool shown: true

    width: 40
    height: 40
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation {
            duration: 250
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.25, 0.1, 0.25, 1, 1, 1]
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: spark.width; y2: spark.height
                GradientStop { position: 0; color: "#CEE2FF" }
                GradientStop { position: 1; color: "#7FA9F9" }
            }
            startX: spark.width / 2; startY: 0
            PathQuad { x: spark.width; y: spark.height / 2; controlX: spark.width / 2; controlY: spark.height / 2 }
            PathQuad { x: spark.width / 2; y: spark.height; controlX: spark.width / 2; controlY: spark.height / 2 }
            PathQuad { x: 0; y: spark.height / 2; controlX: spark.width / 2; controlY: spark.height / 2 }
            PathQuad { x: spark.width / 2; y: 0; controlX: spark.width / 2; controlY: spark.height / 2 }
        }
    }
}
