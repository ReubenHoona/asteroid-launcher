/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes

/*
 * The corners of a square, outside its inscribed circle, painted `color`:
 * over a square snapshot of a face it leaves the round preview (a mask
 * without a shader or an offscreen layer). Size it to the square.
 */
Shape {
    id: mask
    property color color: "black"
    readonly property real r: Math.min(width, height) / 2

    ShapePath {
        fillRule: ShapePath.OddEvenFill
        fillColor: mask.color
        strokeColor: "transparent"
        strokeWidth: -1
        startX: 0
        startY: 0
        PathLine { x: mask.width; y: 0 }
        PathLine { x: mask.width; y: mask.height }
        PathLine { x: 0; y: mask.height }
        PathLine { x: 0; y: 0 }
        PathMove { x: mask.width / 2 + mask.r; y: mask.height / 2 }
        PathArc { x: mask.width / 2 - mask.r; y: mask.height / 2; radiusX: mask.r; radiusY: mask.r; useLargeArc: true }
        PathArc { x: mask.width / 2 + mask.r; y: mask.height / 2; radiusX: mask.r; radiusY: mask.r; useLargeArc: true }
    }
}
