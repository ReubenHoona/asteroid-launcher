// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "eos"
import "eos/facekit.js" as Kit

/*
 * Large: the layout of Wear OS's Large Scale face (watch_face_accessible.xml), our
 * own artwork (watchface-catalogue-34, the audit's F5; large print for the eyes). A
 * very large time, glyphs about 31-352 x 84-180 px, and one 148 px bulb (Heart
 * rate) under it. Layout Circular (default), Linear (a top line with the date),
 * Stacked Time (hours over minutes, the bulb at the right) or Just Time.
 * Color: stock's default is Spring, a colour of its long list whose value the
 * firmware extract does not give; ours starts on Spearmint, a green of the 35.
 * Bold Time is not offered (stock has none).
 * Always-on: the digits drawn by the sensor hub.
 */
EosFace {
    id: face

    eosOptions: [
        Kit.colorOption("spearmint"),
        Kit.listOption("layout", Kit.LARGE_LAYOUTS, Kit.LARGE_NAMES, "circular")
    ]
    readonly property var g: Kit.large(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.large

    // one line of time (Circular, Linear, Just Time)
    EosTimeRow {
        objectName: "eosTime"
        visible: !face.g.stacked
        owner: face
        box: face.g.hour
        size: face.g.size
    }
    // hours over minutes (Stacked Time)
    EosTimeStack {
        objectName: "eosTimeStacked"
        visible: face.g.stacked
        owner: face
        hourBox: face.g.hour
        minuteBox: face.g.minute ? face.g.minute : face.g.hour
        size: face.g.size
    }

    EosSlot {
        owner: face; slotId: "bulb"; shape: "bulb"; defaultSource: face.d.bulb
        spec: face.g.bulb; eosActive: face.g.bulb !== null
    }
    EosSlot {
        owner: face; slotId: "top"; shape: "text"; defaultSource: face.d.top
        spec: face.g.top; eosActive: face.g.top !== null
    }
}
