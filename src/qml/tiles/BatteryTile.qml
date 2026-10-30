/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import Nemo.DBus
import Nemo.Mce
import org.asteroid.controls

/*
 * The watch's battery and the phone's. Stock Wear OS has no battery tile
 * (its battery shows in quick settings and Settings > Battery: the
 * percentage on a ring, "Charging" while it charges); this is that ring,
 * as the steps tile's, with the phone's battery under it as the quick
 * settings' phone toggle shows it (asteroid-btsyncd's phone status). The
 * phone is asked when the tile comes on screen and followed while it shows.
 */
TileBase {
    id: tile
    //% "Battery"
    title: qsTrId("id-tile-battery") + localeManager.changesObserver
    accent: "#c3e88d"
    onClicked: desktop.launchByName("asteroid-settings", tile)

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

    Item {
        id: ring
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(tile.height * 0.01)
        width: Math.round(tile.height * 0.46)
        height: width
        readonly property real stroke: Math.round(tile.height * 0.028)
        readonly property color fill: tile.low ? "#f28b82" : tile.accent

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#33ffffff"
                strokeWidth: ring.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.stroke) / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: 270
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: ring.fill
                strokeWidth: ring.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.stroke) / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: Math.max(0.5, 270 * Math.max(0, tile.percent) / 100)
                }
            }
        }

        Column {
            anchors.centerIn: parent
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(tile.width * 0.005)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tile.charging
                    name: "ios-flash"
                    color: ring.fill
                    width: Math.round(tile.height * 0.065)
                    height: width
                }
                Label {
                    text: tile.percent >= 0 ? tile.percent + "%" : "--"
                    font.pixelSize: Math.round(tile.height * 0.11)
                    font.styleName: "SemiCondensed Medium"
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.7
                font.pixelSize: Math.round(tile.height * 0.045)
                //% "Charging"
                text: (tile.charging ? qsTrId("id-tile-charging")
                                     //% "Charged"
                                     : tile.full ? qsTrId("id-tile-charged")
                                                 //% "Watch"
                                                 : qsTrId("id-tile-watch")) + localeManager.changesObserver
            }
        }
    }

    // the phone, as the quick settings' toggle: its battery, or not connected
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: ring.bottom
        anchors.topMargin: Math.round(tile.height * 0.035)
        spacing: Math.round(tile.width * 0.02)
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "ios-phone-portrait"
            width: Math.round(tile.height * 0.07)
            height: width
            opacity: tile.phoneConnected ? 1 : 0.6
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: tile.phoneConnected && tile.phoneLevel >= 0
            text: tile.phoneLevel + "%"
            font.pixelSize: Math.round(tile.height * 0.07)
            font.styleName: "SemiCondensed Medium"
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: tile.phoneConnected && tile.phoneCharging
            name: "ios-flash"
            color: tile.accent
            width: Math.round(tile.height * 0.05)
            height: width
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            visible: !tile.phoneConnected || tile.phoneLevel < 0
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.05)
            //% "Phone not connected"
            text: (tile.phoneConnected ? "--" : qsTrId("id-tile-phone-disconnected")) + localeManager.changesObserver
        }
    }
}
