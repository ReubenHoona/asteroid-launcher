// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick
import "../eoskit"
import "../eoskit/facekit.js" as Kit

/*
 * Stacked: the layout of Wear OS's Everyday face (watch_face_athletica.xml), our
 * own artwork (watchface-catalogue-32, the audit's F3). Day and date on top,
 * hours over minutes centred, a Heart rate bulb at the left and a Weather bulb at
 * the right. Layout Info (default) or Big (larger digits, no slots); Color Ocean;
 * Bold Time off. Always-on: the digits drawn by the sensor hub.
 */
EosFace {
    id: face

    eosOptions: [
        Kit.colorOption("ocean"),
        Kit.listOption("layout", Kit.STACKED_LAYOUTS, ["Info", "Big"], "info"),
        Kit.boolOption("boldTime", false)
    ]
    readonly property var g: Kit.stacked(opt("layout"))
    readonly property var d: Kit.SLOT_DEFAULTS.stacked

    EosTimeStack {
        objectName: "eosTime"
        owner: face
        hourBox: face.g.hour
        minuteBox: face.g.minute
        size: face.g.size
    }

    EosSlot {
        owner: face; slotId: "top"; shape: "text"; defaultSource: face.d.top
        spec: face.g.top; eosActive: face.g.top !== null
    }
    EosSlot {
        owner: face; slotId: "left"; shape: "bulb"; defaultSource: face.d.left
        spec: face.g.left; eosActive: face.g.left !== null
    }
    EosSlot {
        owner: face; slotId: "right"; shape: "bulb"; defaultSource: face.d.right
        spec: face.g.right; eosActive: face.g.right !== null
    }
}
