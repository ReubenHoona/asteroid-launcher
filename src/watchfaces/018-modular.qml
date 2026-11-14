// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Modular: the layout of Wear OS's default face (Utility, watch_face_numerique.xml),
 * our own artwork (watchface-catalogue-01, -31 of the audit's F1). The Day and date
 * line on top, the time across the middle in the accent, three 86 px bulbs below
 * (Steps goal ring, Health shortcut, Heart rate); Layout Modular I (default),
 * Modular II (a long Next event slot under a small time), Modular III (line, time,
 * long slot) or Minimal (the time alone); Color Lime; Bold Time off.
 * Always-on: the same layout, the time in the thin weight, drawn by the sensor
 * hub (eosHubHour / eosHubMinute: no AP wake per minute).
 */
EosFace {
    id: face

    eosOptions: [
        Kit.colorOption("lime"),
        Kit.listOption("layout", Kit.MODULAR_LAYOUTS, Kit.MODULAR_NAMES, "modular1"),
        Kit.boolOption("boldTime", false)
    ]
    readonly property var g: Kit.modular(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.modular

    EosTimeRow {
        objectName: "eosTime"
        owner: face
        box: face.g.time
        size: face.g.size
    }

    EosSlot {
        owner: face; slotId: "top"; shape: "text"; defaultSource: face.d.top
        spec: face.g.top; eosActive: face.g.top !== null
    }
    EosSlot {
        owner: face; slotId: "left"; shape: "bulb"; defaultSource: face.d.left
        spec: face.g.bulbs ? face.g.bulbs.left : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "center"; shape: "bulb"; defaultSource: face.d.center
        spec: face.g.bulbs ? face.g.bulbs.center : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "right"; shape: "bulb"; defaultSource: face.d.right
        spec: face.g.bulbs ? face.g.bulbs.right : null; eosActive: face.g.bulbs !== null
    }
    EosSlot {
        owner: face; slotId: "bottom"; shape: "long"; defaultSource: face.d.bottom
        spec: face.g.long; eosActive: face.g.long !== null
    }
}
