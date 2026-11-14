// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "eos"
import "eos/facekit.js" as Kit

/*
 * Step ring: the layout of Wear OS's Track face (watch_face_soloring.xml), our own
 * artwork (watchface-catalogue-36, the audit's F7). A thick ring round the rim shows
 * the steps towards the goal (the one slot, ranged values only, drawn by the
 * launcher as the ring plus the count on a line above the time); the time is stacked
 * inside (Layout Stacked, default) or on one line (Linear). Bold Time on; Color Mint.
 * Always-on: the ring is hidden (its steps would be stale in the sensor hub's frame,
 * the audit's gap 08 phase 2) and the digits are drawn by the hub.
 */
EosFace {
    id: face

    eosOptions: [
        Kit.colorOption("mint"),
        Kit.listOption("layout", Kit.RING_LAYOUTS, ["Stacked", "Linear"], "stacked"),
        Kit.boolOption("boldTime", true)
    ]
    readonly property var g: Kit.ring(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.ring

    EosTimeStack {
        objectName: "eosTime"
        visible: face.g.stacked
        owner: face
        hourBox: face.g.hour
        minuteBox: face.g.minute ? face.g.minute : face.g.hour
        size: face.g.size
    }
    EosTimeRow {
        objectName: "eosTimeLinear"
        visible: !face.g.stacked
        owner: face
        box: face.g.hour
        size: face.g.size
    }

    EosSlot {
        owner: face; slotId: "ring"; shape: "ring"; defaultSource: face.d.ring
        spec: face.g.slot
        ringRadius: Kit.RING.radius
        ringStroke: Kit.RING.stroke
        arcStart: Kit.RING.start
        arcSweep: Kit.RING.sweep
    }
}
