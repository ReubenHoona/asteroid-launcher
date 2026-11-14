/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* The low battery gate (setup-wizard-12), as stock's battery level screen: below 20 % setup starts with a
 * ring that is full just before the 20 % mark (8 dp stroke, 1 dp gaps; the arc 270 .. 339.5 degrees fills
 * with level / 100 / 0.19, the arc 344.5 .. 270 is an empty track, a tick marks 20 %) in primaryDim on
 * surfaceContainerLow, a 20 dp bolt in primary 43 dp from the top while charging, the level in the large
 * numeral style (50 sp) in primary and "Charge to 20% to get started" (12 sp) in the middle.
 *
 * `level` and `charging` come from mce's battery signals (no polling): the setup moves on when the level
 * is 20 or more. */
Item {
    id: page
    objectName: "setupCharge"

    // percent, -1 when not known
    property int level: -1
    property bool charging: false
    readonly property alias ring: fill
    readonly property alias levelLabel: levelLabel
    readonly property alias message: message
    readonly property alias bolt: bolt
    readonly property alias tick: tick
    readonly property real strokeWidth: Theme.dp(Setup.gate.strokeDp)

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    // the track: the empty part, from just past the mark all the way round to the start of the filled arc
    ProgressArc {
        id: track
        objectName: "setupChargeTrack"
        anchors.fill: parent
        strokeWidth: page.strokeWidth
        color: Theme.color.surfaceContainerLow
        startAngle: Setup.gate.trackStart
        sweepAngle: Setup.gateTrackSweep()
    }

    // the filled part, 270 .. 339.5 at most
    ProgressArc {
        id: fill
        objectName: "setupChargeFill"
        anchors.fill: parent
        strokeWidth: page.strokeWidth
        color: Theme.color.primaryDim
        startAngle: Setup.gate.fillStart
        sweepAngle: Setup.gateFillSweep(page.level < 0 ? 0 : page.level)
        visible: sweepAngle > 0
    }

    // the mark at 20 %: a short line across the ring in the gap between the two arcs
    Rectangle {
        id: tick
        objectName: "setupChargeTick"
        readonly property real r: Math.min(page.width, page.height) / 2
        readonly property real a: Setup.gate.markDeg * Math.PI / 180
        width: page.strokeWidth * 1.6
        height: Theme.dp(2)
        color: "#ffaefa"
        rotation: Setup.gate.markDeg
        x: page.width / 2 + Math.cos(a) * (r - page.strokeWidth / 2) - width / 2
        y: page.height / 2 + Math.sin(a) * (r - page.strokeWidth / 2) - height / 2
    }

    Icon {
        id: bolt
        objectName: "setupChargeBolt"
        x: (page.width - width) / 2
        y: Theme.dp(Setup.gate.boltTopDp)
        width: Theme.dp(Setup.gate.boltDp)
        height: width
        name: "ios-flash"
        color: Theme.color.primary
        visible: page.charging
    }

    Column {
        id: textColumn
        x: (page.width - width) / 2
        // in the middle, but under the bolt
        y: Math.max((page.height - height) / 2, bolt.y + bolt.height + Theme.dp(2))
        width: page.width * 0.7
        Label {
            id: levelLabel
            objectName: "setupChargeLevel"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            role: "numeralLarge"
            color: Theme.color.primary
            text: page.level < 0 ? "" : page.level + "%"
        }
        Label {
            id: message
            objectName: "setupChargeText"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "bodySmall"
            color: Theme.color.onBackground
            //% "Charge to %1% to get started"
            text: qsTrId("id-setup-charge-to").arg(Setup.minBattery) + localeManager.changesObserver
        }
    }
}
