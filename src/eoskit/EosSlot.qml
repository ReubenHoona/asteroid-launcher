/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * A complication slot of an eos face (ComplicationView.qml documents the
 * contract): the launcher draws the chosen source in it. `spec` is a box of
 * facekit.js ({x, y, w, h} in px of the 384 px screen) that `owner` (the face)
 * scales. `eosActive` is false while the face's layout has no such slot: the
 * slot is hidden and the editor does not list it (ComplicationSources.slotsOf).
 * In the always-on screen the slot is dimmed by the face's blend.
 */
Item {
    id: slot
    objectName: "eosComplication"

    property Item owner
    property var spec: null
    property bool eosActive: true

    property string slotId: ""
    property string shape: "bulb"
    property string defaultSource: "empty"
    property color tint: owner ? owner.accent : "white"
    property string fontFamily: Kit.FONT
    // arc slots: the slot is the whole face (see ComplicationView)
    property real arcStart: 20
    property real arcSweep: 50
    property real arcRadius: 170
    property real arcStroke: 12
    // ring slots: the ring's diameter in px of a 384 px screen
    property real ringRadius: 172
    property real ringStroke: 32

    readonly property real k: owner ? owner.k : 1
    x: spec ? spec.x * k : 0
    y: spec ? spec.y * k : 0
    width: spec ? spec.w * k : 0
    height: spec ? spec.h * k : 0
    visible: eosActive
    opacity: owner ? 1 - (1 - Kit.AMBIENT_SLOT_ALPHA) * owner.blend : 1
}
