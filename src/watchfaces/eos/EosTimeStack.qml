/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * The time as hours over minutes (Index, Everyday, Track, Photos): two boxes of
 * facekit.js, each digit pair centred in its box with its middle at the box's
 * middle. The hours and the minutes carry the sensor hub's names.
 */
Item {
    id: stack

    property Item owner
    property var hourBox: ({ x: 96, y: 100, w: 192, h: 82 })
    property var minuteBox: ({ x: 96, y: 190, w: 192, h: 82 })
    property real size: 112
    property bool bold: owner ? owner.boldTime : false
    property color color: owner ? owner.accent : "white"
    property color minuteColor: color
    property color ambientColor: owner ? owner.accentAmbient : "#b3b3b3"
    property color minuteAmbientColor: ambientColor

    readonly property real k: owner ? owner.k : 1
    readonly property real px: size * k
    anchors.fill: parent

    readonly property Item hourItem: hours
    readonly property Item minuteItem: minutes

    EosNumber {
        id: hours
        x: stack.hourBox.x * stack.k + stack.hourBox.w * stack.k / 2 - width / 2
        y: Kit.digitTop((stack.hourBox.y + stack.hourBox.h / 2) * stack.k, stack.px)
        text: stack.owner ? stack.owner.hourStr : "10"
        hubName: "eosHubHour"
        pixelSize: stack.px
        bold: stack.bold
        color: stack.color
        ambientColor: stack.ambientColor
        blend: stack.owner ? stack.owner.blend : 0
    }
    EosNumber {
        id: minutes
        x: stack.minuteBox.x * stack.k + stack.minuteBox.w * stack.k / 2 - width / 2
        y: Kit.digitTop((stack.minuteBox.y + stack.minuteBox.h / 2) * stack.k, stack.px)
        text: stack.owner ? stack.owner.minuteStr : "08"
        hubName: "eosHubMinute"
        pixelSize: stack.px
        bold: stack.bold
        color: stack.minuteColor
        ambientColor: stack.minuteAmbientColor
        blend: stack.owner ? stack.owner.blend : 0
    }
}
