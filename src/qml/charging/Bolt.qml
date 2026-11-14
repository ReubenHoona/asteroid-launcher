/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import "charging.js" as Charging

/* The charging bolt, drawn here (our own glyph; stock's ic_power and its Lottie
 * intro are not copied). A filled bolt in a 24 x 24 box, 20 units tall, and an
 * outline drawn from the top to the tip along both sides (`trace`, 0..1): the
 * intro of the charging screen traces it, fades the fill in and the outline out
 * (charging-battery-06). At rest only the fill shows, `size` px wide and tall
 * (24 dp on the screen). Nothing here animates by itself. */
Item {
    id: bolt
    objectName: "eosBolt"

    // the edge of the box, px
    property real size: 48
    // the share of the outline drawn, 0..1, and its width in box units
    property real trace: 0
    property real stroke: 0
    property real outlineOpacity: 0
    property real fillOpacity: 1
    property color fillColor: "white"
    property color outlineColor: "white"

    width: size
    height: size

    readonly property var halves: Charging.boltHalves()

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, c.a * a) }

    Shape {
        width: Charging.BOLT.box
        height: Charging.BOLT.box
        scale: bolt.size / Charging.BOLT.box
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.GeometryRenderer
        antialiasing: true

        ShapePath {
            objectName: "eosBoltFill"
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: bolt.withAlpha(bolt.fillColor, bolt.fillOpacity)
            PathPolyline { path: Charging.boltClosed() }
        }
        ShapePath {
            objectName: "eosBoltOutlineA"
            strokeWidth: bolt.stroke > 0.001 && bolt.trace > 0 ? bolt.stroke : -1
            strokeColor: bolt.withAlpha(bolt.outlineColor, bolt.outlineOpacity)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: Charging.partial(bolt.halves.a, bolt.trace) }
        }
        ShapePath {
            objectName: "eosBoltOutlineB"
            strokeWidth: bolt.stroke > 0.001 && bolt.trace > 0 ? bolt.stroke : -1
            strokeColor: bolt.withAlpha(bolt.outlineColor, bolt.outlineOpacity)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: Charging.partial(bolt.halves.b, bolt.trace) }
        }
    }
}
