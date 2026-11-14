/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import Nemo.Mce
import org.asteroid.controls

/*
 * The watch's battery and the phone's. Stock Wear OS has no battery tile
 * (its battery is in quick settings and Settings > Battery); the user keeps
 * ours, in the add list only (DECISIONS Q27, tiles-individual-30,
 * charging-battery-24). It wears the stock frame: the carousel's app icon
 * on top, the title in white, the watch in one stadium data card (a ring of
 * the level, the percentage and "Charging" / "Charged" / "Watch") and the
 * phone's level as the bottom text, as the quick settings' phone toggle
 * shows it (asteroid-btsyncd's phone status). A tap on the card opens
 * Settings > Battery (page "battery"). The phone is asked when the tile
 * comes on screen and followed while it shows.
 */
TileBase {
    id: tile
    //% "Battery"
    title: qsTrId("id-tile-battery") + localeManager.changesObserver
    backgroundTap: false
    //% "Phone"
    bottomLabel: (tile.phoneConnected && tile.phoneLevel >= 0 ? qsTrId("id-tile-phone")
                                                               //% "Phone not connected"
                                                               : qsTrId("id-tile-phone-disconnected")) + localeManager.changesObserver
    bottomValue: tile.phoneConnected && tile.phoneLevel >= 0 ? tile.phoneLevel + "%" : ""

    MceBatteryLevel { id: mceLevel }
    MceBatteryState { id: mceState }
    readonly property int percent: mceLevel.percent
    readonly property bool charging: mceState.value === MceBatteryState.Charging
    readonly property bool full: mceState.value === MceBatteryState.Full
    readonly property bool low: percent >= 0 && percent <= 15 && !charging

    property bool phoneConnected: false
    property int phoneLevel: -1
    property bool phoneCharging: false
    onLiveChanged: if (live) askPhone()
    Component.onCompleted: askPhone()
    function askPhone() {
        phone.typedCall("Connected", [], function (c) { tile.phoneConnected = c }, function () { tile.phoneConnected = false })
        phone.typedCall("BatteryLevel", [], function (l) { tile.phoneLevel = l }, function () { tile.phoneLevel = -1 })
        phone.typedCall("Charging", [], function (c) { tile.phoneCharging = c }, function () { tile.phoneCharging = false })
    }
    DBusInterface {
        id: phone
        bus: DBus.SessionBus
        service: "org.asteroidos.btsyncd"
        path: "/org/asteroidos/btsyncd/phone"
        iface: "org.asteroidos.btsyncd.Phone"
        signalsEnabled: tile.live
        function rcConnectedChanged(connected: bool) {
            tile.phoneConnected = connected
        }
        function rcBatteryChanged(level: int, charging: bool) {
            tile.phoneLevel = level
            tile.phoneCharging = charging
        }
    }

    // the watch: one stadium data card, ring left, level and state right
    TileCard {
        id: card
        objectName: "batteryCard"
        width: tile.body.width
        height: Math.min(Theme.dp(60), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        accessibleName: tile.title
        onClicked: desktop.openSettings("battery")

        CircularProgressIndicator {
            id: ring
            objectName: "batteryRing"
            x: Theme.dp(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.dp(48)
            height: width
            displayOn: tile.awake
            color: tile.low ? Theme.color.error : Theme.color.primary
            trackColor: Theme.color.surfaceContainerHigh
            progress: Math.max(0, tile.percent) / 100
        }
        Column {
            x: ring.x + ring.width + Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - Theme.dp(14)
            Row {
                spacing: Theme.dp(2)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tile.charging
                    name: "ios-flash"
                    color: Theme.color.primary
                    width: Theme.dp(12)
                    height: width
                }
                Label {
                    objectName: "batteryPercent"
                    text: tile.percent >= 0 ? tile.percent + "%" : "--"
                    role: "displaySmall"
                    font.weight: Font.Medium
                    font.features: Theme.tabularNumerals
                    color: tile.low ? Theme.color.error : Theme.color.onSurface
                    maximumLineCount: 1
                }
            }
            Label {
                objectName: "batteryState"
                width: parent.width
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
                //% "Charging"
                text: (tile.charging ? qsTrId("id-tile-charging")
                                     //% "Charged"
                                     : tile.full ? qsTrId("id-tile-charged")
                                                 //% "Watch"
                                                 : qsTrId("id-tile-watch")) + localeManager.changesObserver
            }
        }
    }
}
