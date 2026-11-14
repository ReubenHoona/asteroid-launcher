// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "eos"
import "eos/facekit.js" as Kit

/*
 * Classic: the layout of Wear OS's Classic face (watch_face_classica.xml), our own
 * artwork (watchface-catalogue-33, the audit's F4). Analog, with Arabic numerals on
 * a ring and four 86 px bulbs (Weather at the left, Health on top, the date at the
 * right, Steps at the bottom). Styles None, Arabic I (default), Arabic II, Roman I,
 * Roman II, Dashes, Dots; Seconds on; Color Cloud.
 * Always-on: the hands are drawn by the AP once a minute (no hub drawing for hands
 * yet, the audit's gap 09): the picker marks the face (eosHubDrawn false); the
 * numerals, the bulbs and the hands go thin and dim.
 */
EosFace {
    id: face

    eosHubDrawn: false
    readonly property bool eosUsesSeconds: true

    eosOptions: [
        Kit.colorOption("cloud"),
        Kit.listOption("styles", Kit.CLASSIC_STYLES, Kit.CLASSIC_STYLE_NAMES, "arabic1"),
        Kit.boolOption("seconds", true)
    ]
    readonly property var g: Kit.classic()
    readonly property var d: Kit.SLOT_DEFAULTS.classic
    readonly property string style: opt("styles")
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // the numerals of the style, on the ring
    Repeater {
        model: Kit.numerals(face.style)
        delegate: Text {
            objectName: "eosNumeral"
            readonly property real a: modelData.angle * Math.PI / 180
            readonly property real px: Kit.NUMERAL_SIZE * face.k * (modelData.text.length > 2 ? 0.7 : 1)
            text: modelData.text
            color: face.blend > 0.5 ? face.accentAmbient : face.accent
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.weight: face.blend > 0.5 ? Font.Light : Font.Normal
            font.pixelSize: Math.round(px)
            x: face.cx + Kit.NUMERAL_RADIUS * face.k * Math.sin(a) - width / 2
            y: face.cy - Kit.NUMERAL_RADIUS * face.k * Math.cos(a) - Kit.DIGIT_CENTER * px
        }
    }
    // the dashes and dots
    Repeater {
        model: Kit.ticks(face.style)
        delegate: Item {
            objectName: "eosTick"
            x: face.cx
            y: face.cy
            width: 0
            height: 0
            rotation: modelData.angle
            Rectangle {
                x: -width / 2
                y: -(face.width / 2 - 4 * face.k)
                width: modelData.width * face.k
                height: modelData.length * face.k
                radius: modelData.round ? width / 2 : 0
                color: face.blend > 0.5 ? face.accentAmbient : face.accent
            }
        }
    }

    EosSlot {
        owner: face; slotId: "left"; shape: "bulb"; defaultSource: face.d.left; spec: face.g.left
    }
    EosSlot {
        owner: face; slotId: "top"; shape: "bulb"; defaultSource: face.d.top; spec: face.g.top
    }
    EosSlot {
        owner: face; slotId: "right"; shape: "bulb"; defaultSource: face.d.right; spec: face.g.right
    }
    EosSlot {
        owner: face; slotId: "bottom"; shape: "bulb"; defaultSource: face.d.bottom; spec: face.g.bottom
    }

    EosHands {
        owner: face
        hourColor: face.white
        minuteColor: face.white
        secondColor: face.accent
    }
}
