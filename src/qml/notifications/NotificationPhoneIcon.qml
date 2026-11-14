/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick

/*
 * The open-on-phone symbol, our own drawing (stock's is a Material symbol we do
 * not copy): a phone outline with an arrow leaving it to the upper right.
 * size is the square it fits in (24 dp = 48 px in the Open on phone button).
 */
Item {
    id: icon

    property real size: 48
    property color color: "white"
    readonly property real stroke: Math.max(2, Math.round(size / 12))

    width: size
    height: size

    // the phone: a rounded outline in the left two thirds
    Rectangle {
        x: icon.size * 0.10
        y: icon.size * 0.14
        width: icon.size * 0.46
        height: icon.size * 0.72
        radius: icon.size * 0.09
        color: "transparent"
        border.width: icon.stroke
        border.color: icon.color
        // its speaker slit
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - icon.stroke * 3
            width: parent.width * 0.3
            height: icon.stroke
            radius: height / 2
            color: icon.color
        }
    }

    // the arrow: a shaft up to the right and a head of two strokes
    Rectangle {
        id: shaft
        x: icon.size * 0.50
        y: icon.size * 0.30
        width: icon.size * 0.40
        height: icon.stroke
        radius: height / 2
        color: icon.color
        antialiasing: true
        transformOrigin: Item.Left
        rotation: -45
    }
    Rectangle {
        // the head's stroke to the left of the tip
        x: icon.size * 0.50 + icon.size * 0.40 * Math.SQRT1_2 + icon.stroke * 0.5 - width
        y: icon.size * 0.30 - icon.size * 0.40 * Math.SQRT1_2 - icon.stroke * 0.5
        width: icon.size * 0.24
        height: icon.stroke
        radius: height / 2
        color: icon.color
        antialiasing: true
        transformOrigin: Item.Left
        rotation: 0
    }
    Rectangle {
        // and its stroke down from the tip
        x: icon.size * 0.50 + icon.size * 0.40 * Math.SQRT1_2 + icon.stroke * 0.5
        y: icon.size * 0.30 - icon.size * 0.40 * Math.SQRT1_2 - icon.stroke * 0.5
        width: icon.size * 0.24
        height: icon.stroke
        radius: height / 2
        color: icon.color
        antialiasing: true
        transformOrigin: Item.Left
        rotation: 90
    }
}
