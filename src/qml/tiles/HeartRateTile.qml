/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.launcher

// The latest heart rate asteroid-sensorlogd logged and today's in hourly
// averages, as Wear OS's heart rate tile
TileBase {
    id: tile
    //% "Heart rate"
    title: qsTrId("id-tile-heart-rate") + localeManager.changesObserver
    accent: "#f28b82"
    //% "Measure"
    chipText: qsTrId("id-tile-measure") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-hrm", null)

    HealthLog {
        id: log
        sensor: "heartrateMonitor"
        buckets: 24
        active: tile.live
    }

    Column {
        anchors.centerIn: parent
        spacing: Math.round(tile.height * 0.01)

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(tile.width * 0.02)
            Icon {
                name: "ios-heart"
                color: tile.accent
                width: Math.round(tile.height * 0.08)
                height: width
                anchors.verticalCenter: value.verticalCenter
            }
            Label {
                id: value
                text: log.hasData ? log.lastValue : "--"
                font.pixelSize: Math.round(tile.height * 0.16)
                font.styleName: "SemiCondensed Medium"
            }
            Label {
                //% "bpm"
                text: qsTrId("id-tile-bpm") + localeManager.changesObserver
                opacity: 0.7
                font.pixelSize: Math.round(tile.height * 0.055)
                anchors.baseline: value.baseline
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.05)
            //% "No reading today"
            text: (log.hasData ? Qt.formatTime(log.lastTime, Qt.locale().timeFormat(Locale.ShortFormat))
                               : qsTrId("id-tile-no-reading")) + localeManager.changesObserver
        }

        // today in 24 hourly bars, scaled between the day's lowest and highest
        Row {
            id: graph
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.max(1, Math.round(tile.width * 0.004))
            height: Math.round(tile.height * 0.12)
            visible: log.hasData
            readonly property real barWidth: Math.floor((tile.width * 0.5 - spacing * 23) / 24)
            Repeater {
                model: 24
                delegate: Item {
                    width: graph.barWidth
                    height: graph.height
                    readonly property int v: log.values.length > index ? log.values[index] : 0
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        radius: width / 2
                        visible: parent.v > 0
                        height: Math.max(width, parent.height * (log.maxValue > log.minValue
                                                                 ? 0.25 + 0.75 * (parent.v - log.minValue) / (log.maxValue - log.minValue)
                                                                 : 0.5))
                        color: tile.accent
                        opacity: 0.85
                    }
                }
            }
        }
    }
}
