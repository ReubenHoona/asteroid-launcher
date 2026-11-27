// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Analog Arcs: the layout of Wear OS's Analog Arcs face (watch_face_analog_arc.xml,
 * AnalogArcWatchFaceService), a favourite of the CP3A fresh carousel; our own drawing
 * (A-08). Analog hands over a ring of indices, four round bulbs inside it and arcs on
 * the rim (preview_analog_arc.png):
 *  - Layout: Max Four (default: four bulbs, four quarter arcs), Max Two (four bulbs, the
 *    upper and the lower half arcs), Minimal Four and Minimal Two (a line slot instead of
 *    the bulbs), Numerals Four and Numerals Two (12, 3, 6 and 9 instead of the slots);
 *  - Styles: Ring Indices (two thin circles, the minute ticks between them, the hour
 *    indices across) or Simple Indices (the hour indices alone); Seconds on; Color Stream;
 *  - the slots' sources as stock's defaults: Heart rate, Health, Day and date, Steps; the
 *    line Day and date; the arcs Sunrise and sunset, UV, Calories, Weather (Two: Weather
 *    above, UV below).
 * The numbers are Kit.analogArcs, ARCS_RING, ARCS_SIMPLE, ARCS_NUMERALS.
 * Always-on: the hands are drawn by the AP once a minute (no hub drawing of hands yet,
 * A-05), as the other analog faces (eosHubDrawn false); the indices, the numerals, the
 * slots and the hands go thin and dim.
 */
EosFace {
    id: face

    eosHubDrawn: false
    readonly property bool eosUsesSeconds: true

    eosOptions: [
        Kit.colorOption("stream"),
        Kit.listOption("layout", Kit.ARCS_LAYOUTS, Kit.ARCS_LAYOUT_NAMES, "max4"),
        Kit.listOption("styles", Kit.ARCS_STYLES, Kit.ARCS_STYLE_NAMES, "ring"),
        Kit.boolOption("seconds", true)
    ]
    readonly property var g: Kit.analogArcs(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.arcs
    readonly property bool ring: opt("styles") !== "simple"
    readonly property var idx: ring ? Kit.ARCS_RING : Kit.ARCS_SIMPLE
    readonly property color indexColor: face.blend > 0.5 ? face.accentAmbient : face.accent
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // ---- the indices ----
    // Ring Indices: the two circles
    Repeater {
        model: face.ring ? [Kit.ARCS_RING.inner, Kit.ARCS_RING.outer] : []
        delegate: Rectangle {
            objectName: "eosArcsCircle"
            x: face.cx - width / 2
            y: face.cy - height / 2
            width: 2 * (modelData + Kit.ARCS_RING.stroke / 2) * face.k
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Kit.ARCS_RING.stroke * face.k
            border.color: face.indexColor
            opacity: Kit.ARCS_RING.alpha
            antialiasing: true
        }
    }
    // the ticks: 60 places, the hour indices at every fifth, the minute ticks between (Ring Indices only)
    Repeater {
        model: 60
        delegate: Item {
            objectName: index % 5 === 0 ? "eosArcsHourIndex" : "eosArcsMinuteTick"
            readonly property bool hour: index % 5 === 0
            readonly property var span: hour ? face.idx.hour : Kit.ARCS_RING.minute
            visible: hour || face.ring
            x: face.cx
            y: face.cy
            width: 0
            height: 0
            rotation: index * 6
            Rectangle {
                x: -width / 2
                y: -parent.span[1] * face.k
                width: (parent.hour ? face.idx.hourWidth : Kit.ARCS_RING.minuteWidth) * face.k
                height: (parent.span[1] - parent.span[0]) * face.k
                color: face.indexColor
                opacity: face.idx.alpha
                antialiasing: true
            }
        }
    }

    // ---- the numerals of the Numerals layouts ----
    Repeater {
        model: face.g.numerals ? Kit.ARCS_NUMERALS.at : []
        delegate: Text {
            objectName: "eosNumeral"
            readonly property real px: Kit.ARCS_NUMERALS.size * face.k
            text: modelData.text
            color: face.blend > 0.5 ? face.whiteAmbient : face.white
            renderType: Text.NativeRendering
            font.family: Kit.FONT
            font.weight: face.blend > 0.5 ? Font.Thin : Font.Light
            font.pixelSize: Math.round(px)
            x: modelData.cx * face.k - width / 2
            y: modelData.cy * face.k - Kit.DIGIT_CENTER * px
        }
    }

    // ---- the slots ----
    EosSlot {
        owner: face; slotId: "left"; shape: "bulb"; defaultSource: face.d.left
        spec: face.g.bulbs ? face.g.bulbs.left : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "top"; shape: "bulb"; defaultSource: face.d.top
        spec: face.g.bulbs ? face.g.bulbs.top : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "right"; shape: "bulb"; defaultSource: face.d.right
        spec: face.g.bulbs ? face.g.bulbs.right : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "bottom"; shape: "bulb"; defaultSource: face.d.bottom
        spec: face.g.bulbs ? face.g.bulbs.bottom : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "line"; shape: "text"; defaultSource: face.d.line
        spec: face.g.line; eosActive: face.g.line !== null
    }
    // the arcs: each slot is the whole face with its part of the rim (clockwise from 3 o'clock)
    EosSlot {
        owner: face; slotId: "northwest"; shape: "arc"; defaultSource: face.d.northwest
        arcStart: 180; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: face.g.four
    }
    EosSlot {
        owner: face; slotId: "northeast"; shape: "arc"; defaultSource: face.d.northeast
        arcStart: -90; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: face.g.four
    }
    EosSlot {
        owner: face; slotId: "southwest"; shape: "arc"; defaultSource: face.d.southwest
        arcStart: 90; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: face.g.four
    }
    EosSlot {
        owner: face; slotId: "southeast"; shape: "arc"; defaultSource: face.d.southeast
        arcStart: 0; arcSweep: 90; x: 0; y: 0; width: face.width; height: face.height
        eosActive: face.g.four
    }
    EosSlot {
        owner: face; slotId: "upper"; shape: "arc"; defaultSource: face.d.upper
        arcStart: 180; arcSweep: 180; x: 0; y: 0; width: face.width; height: face.height
        eosActive: !face.g.four
    }
    EosSlot {
        owner: face; slotId: "lower"; shape: "arc"; defaultSource: face.d.lower
        arcStart: 0; arcSweep: 180; x: 0; y: 0; width: face.width; height: face.height
        eosActive: !face.g.four
    }

    EosHands {
        owner: face
        hourColor: face.white
        minuteColor: face.white
        secondColor: face.accent
    }
}
