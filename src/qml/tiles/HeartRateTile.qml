/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher

// The latest heart rate asteroid-sensorlogd logged and when, today's range
// and resting heart rate, and today so far as a range bar an hour, as the
// stock heart rate tile (current heart rate over a graph of recent ones; on
// Fitbit's, the lowest and highest readings and the resting heart rate). A
// tap opens the Health app on today's heart rate, as the stock tile opens
// the heart rate app; the chip measures now.
TileBase {
    id: tile
    //% "Heart rate"
    title: qsTrId("id-tile-heart-rate") + localeManager.changesObserver
    accent: "#f28b82"
    //% "Measure"
    chipText: qsTrId("id-tile-measure") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-hrm", null)
    onClicked: {
        // asteroid-health opens its heart rate page on today when this is
        // set (and recent) on its start, or when it changes while it runs
        openRequest.value = "heartrate@" + Date.now()
        desktop.launchByName("asteroid-health", tile)
    }

    ConfigurationValue {
        id: openRequest
        key: "/org/asteroidos/health/ui/open"
        defaultValue: ""
    }

    HealthLog {
        id: log
        sensor: "heartrateMonitor"
        buckets: 24
        active: tile.live
        onChanged: tile.hour = new Date().getHours()
    }

    // the hour now: the chart runs from midnight to it
    property int hour: new Date().getHours()
    onLiveChanged: if (live) hour = new Date().getHours()

    Column {
        anchors.centerIn: parent
        spacing: Math.round(tile.height * 0.012)

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
            // bpm over the time of the reading
            Column {
                anchors.verticalCenter: value.verticalCenter
                visible: log.hasData
                Label {
                    //% "bpm"
                    text: qsTrId("id-tile-bpm") + localeManager.changesObserver
                    opacity: 0.7
                    font.pixelSize: Math.round(tile.height * 0.05)
                }
                Label {
                    text: log.hasData ? Qt.formatTime(log.lastTime, Qt.locale().timeFormat(Locale.ShortFormat)) : ""
                    opacity: 0.7
                    font.pixelSize: Math.round(tile.height * 0.05)
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.85
            font.pixelSize: Math.round(tile.height * 0.05)
            text: (log.hasData ?
                       //% "Range %1"
                       //: %1 is today's lowest to highest heart rate, as 58–112
                       qsTrId("id-tile-hr-range").arg(log.minValue === log.maxValue ? log.minValue : log.minValue + "–" + log.maxValue)
                       + (log.restingValue > 0 ?
                              "  ·  " +
                              //% "Resting %1"
                              //: %1 is today's resting heart rate in bpm
                              qsTrId("id-tile-hr-resting").arg(log.restingValue) : "") :
                       //% "No reading today"
                       qsTrId("id-tile-no-reading")) + localeManager.changesObserver
        }

        // today from midnight to now: a bar an hour from its lowest to its
        // highest reading, between the day's lowest (bottom) and highest (top)
        Item {
            id: graph
            anchors.horizontalCenter: parent.horizontalCenter
            visible: log.hasData
            width: Math.round(tile.width * 0.5)
            height: Math.round(tile.height * 0.1)
            readonly property int slots: Math.max(1, Math.min(24, tile.hour + 1))
            readonly property real slot: width / slots
            readonly property real barWidth: Math.max(2, Math.min(slot * 0.6, tile.width * 0.02))
            // inside the chart with the round ends of the bars
            function yOf(v) {
                var cap = barWidth / 2
                return log.maxValue > log.minValue
                        ? cap + (height - 2 * cap) * (1 - (v - log.minValue) / (log.maxValue - log.minValue))
                        : height / 2
            }
            Rectangle {
                // the baseline
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: "#ffffff"
                opacity: 0.25
            }
            Repeater {
                model: graph.slots
                delegate: Rectangle {
                    readonly property int lo: log.lows.length > index ? log.lows[index] : 0
                    readonly property int hi: log.highs.length > index ? log.highs[index] : 0
                    visible: hi > 0
                    x: graph.slot * index + (graph.slot - width) / 2
                    width: graph.barWidth
                    y: visible ? graph.yOf(hi) - width / 2 : 0
                    height: visible ? graph.yOf(lo) - graph.yOf(hi) + width : 0
                    radius: width / 2
                    color: tile.accent
                    opacity: index === tile.hour ? 1 : 0.75
                }
            }
        }

        // the chart's ends: midnight and now
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: log.hasData
            width: graph.width
            height: midnight.height
            Label {
                id: midnight
                anchors.left: parent.left
                opacity: 0.6
                font.pixelSize: Math.round(tile.height * 0.04)
                text: Qt.formatTime(new Date(2000, 0, 1, 0, 0), Qt.locale().timeFormat(Locale.ShortFormat))
            }
            Label {
                anchors.right: parent.right
                opacity: 0.6
                font.pixelSize: Math.round(tile.height * 0.04)
                //% "Now"
                text: qsTrId("id-tile-hr-now") + localeManager.changesObserver
            }
        }
    }
}
