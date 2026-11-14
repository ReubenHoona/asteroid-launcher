/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * The time on one line, "h:mm" or "HH:mm", centred in a box of facekit.js
 * (stock's StandardTimeElement: no AM/PM). The digits' middle is the box's
 * middle. Hours, colon and minutes are three EosNumbers in a Row; a one-digit
 * hour moves the group, as stock centres the text, and the hub's layout is
 * rebuilt at the digit count change (huboffload.h). Only the hours and the
 * minutes carry the hub's names.
 */
Item {
    id: row

    property Item owner
    property var box: ({ x: 0, y: 0, w: 384, h: 100 })
    property real size: 112             // px of the 384 px design
    property bool bold: owner ? owner.boldTime : false
    property color color: owner ? owner.accent : "white"
    property color ambientColor: owner ? owner.accentAmbient : "#b3b3b3"

    readonly property real px: size * (owner ? owner.k : 1)
    x: box.x * (owner ? owner.k : 1)
    y: box.y * (owner ? owner.k : 1)
    width: box.w * (owner ? owner.k : 1)
    height: box.h * (owner ? owner.k : 1)

    readonly property Item hourItem: hours
    readonly property Item minuteItem: minutes

    Row {
        id: group
        anchors.horizontalCenter: parent.horizontalCenter
        y: Kit.digitTop(row.height / 2, row.px)
        EosNumber {
            id: hours
            text: row.owner ? row.owner.hourStr : "10"
            hubName: "eosHubHour"
            pixelSize: row.px
            bold: row.bold
            color: row.color
            ambientColor: row.ambientColor
            blend: row.owner ? row.owner.blend : 0
        }
        EosNumber {
            id: colon
            text: ":"
            pixelSize: row.px
            bold: row.bold
            color: row.color
            ambientColor: row.ambientColor
            blend: row.owner ? row.owner.blend : 0
        }
        EosNumber {
            id: minutes
            text: row.owner ? row.owner.minuteStr : "08"
            hubName: "eosHubMinute"
            pixelSize: row.px
            bold: row.bold
            color: row.color
            ambientColor: row.ambientColor
            blend: row.owner ? row.owner.blend : 0
        }
    }
}
