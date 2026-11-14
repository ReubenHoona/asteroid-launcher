/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import "facekit.js" as Kit

/*
 * The three hands of an analog eos face. The pivot is the middle of the face; the
 * angles and shapes are facekit.js (hourAngle, minuteAngle, secondAngle, HANDS). The
 * item named secondHand is what the launcher hides when Seconds is off and in the
 * always-on screen (WatchfaceReloader: an id starting with "second"), and what makes
 * the home screen tick every second while it shows (the face declares eosUsesSeconds).
 * In the always-on screen the hour and minute hands are thinner and dimmer.
 * The hands turn in the AP's always-on frame (once a minute); no hub drawing for them yet.
 */
Item {
    id: hands
    anchors.fill: parent

    property Item owner
    property color hourColor: owner ? owner.accent : "white"
    property color minuteColor: owner ? owner.accent : "white"
    property color secondColor: "white"
    property color ambientColor: owner ? owner.accentAmbient : "#b3b3b3"
    readonly property real k: owner ? owner.k : 1
    readonly property real blend: owner ? owner.blend : 0
    readonly property real thin: 1 - (1 - Kit.HAND_AMBIENT_WIDTH) * blend

    readonly property real hourDeg: owner ? Kit.hourAngle(owner.hour24, owner.minute) : 0
    readonly property real minuteDeg: owner ? Kit.minuteAngle(owner.minute, owner.second) : 0
    readonly property real secondDeg: owner ? Kit.secondAngle(owner.second, 0) : 0

    // the colour towards its always-on dimming (Kit.AMBIENT_DIM) with the blend
    function dimmed(c) { return Qt.tint(c, Qt.rgba(0, 0, 0, (1 - Kit.AMBIENT_DIM) * blend)) }

    component Hand: Item {
        id: hand
        property var spec
        property real angle: 0
        property color color: "white"
        property real thin: 1
        width: 0
        height: 0
        anchors.centerIn: parent
        rotation: angle
        Rectangle {
            objectName: "eosHandBar"
            x: -width / 2
            y: -hand.spec.length * hands.k
            width: Math.max(1, hand.spec.width * hands.k * hand.thin)
            height: (hand.spec.length + hand.spec.tail) * hands.k
            radius: width / 2
            color: hand.color
        }
    }

    Hand {
        objectName: "eosHourHand"
        spec: Kit.HANDS.hour
        angle: hands.hourDeg
        color: hands.dimmed(hands.hourColor)
        thin: hands.thin
    }
    Hand {
        objectName: "eosMinuteHand"
        spec: Kit.HANDS.minute
        angle: hands.minuteDeg
        color: hands.dimmed(hands.minuteColor)
        thin: hands.thin
    }
    Hand {
        id: secondHand
        objectName: "eosSecondHand"
        spec: Kit.HANDS.second
        angle: hands.secondDeg
        color: hands.secondColor
        visible: hands.blend < 1
    }
}
