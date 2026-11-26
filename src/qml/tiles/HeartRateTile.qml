/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import QtSensors
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher
import "tilecontent.js" as TC

/*
 * Daily heart rate, as the Fitbit tile (tiles-individual-20, -21, health-fitness-04; ega.java:821-848,
 * aapt.java:27-32, aapu.java:52-110): one graphic data card (#29303D, corner 52 px) with a line chart of the last
 * 2 hours in 3 minute means (40 buckets from asteroid-sensorlogd's log, HealthLog's window mode; the line #94D6FF over
 * a soft gradient), the highest mean with its dot and label in red (#E46962), the lowest in blue (#2BC7F7), and the
 * window as the caption ("11:53 AM - 1:53 PM", in the 12 or 24 hour format of Settings). Without readings in the
 * window: "No heart rate data has been collected in the last 2 hrs.". Bottom text: "Current bpm" over the heart icon
 * (#FFBA2B) and the live heart rate, "--" until the sensor has one. No edge button; a tap on the card opens the
 * Health app on the heart rate page.
 *
 * Battery (M1, DECISIONS Q14): the live reading runs the heart rate sensor only while the tile is on screen with
 * the display awake (HrmSensor.active = awake), never in ambient or behind an app. Nothing else runs: the log is
 * read when the tile comes on screen and when sensorlogd writes.
 */
TileBase {
    id: tile
    //% "Heart rate"
    title: qsTrId("id-tile-heart-rate") + localeManager.changesObserver
    backgroundTap: false
    //% "Current bpm"
    bottomLabel: qsTrId("id-tile-current-bpm") + localeManager.changesObserver
    bottomValue: tile.bpm > 0 ? String(tile.bpm) : "--"
    bottomIcon: "ms-favorite"
    bottomIconColor: TC.HR_ICON

    function openHeartRate() {
        // asteroid-health opens its heart rate page on today when this is set (and recent) on its
        // start, or when it changes while it runs
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
        objectName: "hrLog"
        sensor: "heartrateMonitor"
        buckets: TC.HR_BUCKETS
        windowMinutes: TC.HR_WINDOW_MINUTES
        active: tile.live && !tile.preview
    }

    // the live reading: the sensor runs while the tile is on screen, awake and has stayed 300 ms (a tile that only
    // passes by in a swipe, or is drawn small in the editor, never starts it: one single shot, only while awake)
    property int bpm: 0
    property bool settled: false
    readonly property var sensorItem: hrm
    Timer {
        id: settle
        objectName: "hrSettle"
        interval: 300
        repeat: false
        running: tile.awake && !tile.preview && !tile.settled
        onTriggered: tile.settled = true
    }
    HrmSensor {
        id: hrm
        objectName: "hrSensor"
        active: tile.settled && tile.awake && !tile.preview
        onReadingChanged: tile.bpm = reading ? TC.liveBpm(reading.bpm) : 0
    }
    onAwakeChanged: if (!awake) { settled = false; bpm = 0 }

    readonly property var chart: TC.chartPoints(log.values, plot.width, plot.height)
    readonly property bool hasData: log.hasData && chart.points.length > 0
    // 12 or 24 hour as Settings says: the window "11:53 AM - 1:53 PM"
    readonly property string windowText: log.windowStart.getTime() > 0 ? TimeFormat.range(log.windowStart, log.windowEnd) : ""

    TileCard {
        id: card
        objectName: "hrCard"
        width: tile.body.width
        height: Math.min(Theme.dp(72), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: TC.CARD
        contentColor: Theme.color.onSurface
        radius: Theme.dp(26)
        preview: tile.preview
        //% "Heart rate in past 2 hours, highest %1 bpm, lowest %2 bpm"
        accessibleName: tile.hasData ? qsTrId("id-tile-hr-description").replace("%1", tile.chart.max).replace("%2", tile.chart.min)
                                     : tile.title
        onClicked: tile.openHeartRate()

        Item {
            id: plot
            objectName: "hrPlot"
            visible: tile.hasData
            x: Theme.dp(14)
            y: Theme.dp(17)
            width: card.width - 2 * x
            height: Theme.dp(20)

            Shape {
                anchors.fill: parent
                ShapePath {
                    strokeColor: "transparent"
                    strokeWidth: 0
                    fillGradient: LinearGradient {
                        y1: 0
                        y2: plot.height
                        GradientStop { position: 0; color: Qt.rgba(0.58, 0.839, 1, 0.35) }
                        GradientStop { position: 1; color: Qt.rgba(0.58, 0.839, 1, 0) }
                    }
                    PathPolyline { path: tile.fillPath }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: TC.HR_LINE
                    strokeWidth: Theme.dp(2)
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: tile.linePath }
                }
            }

            // the highest mean: dot and label in red over it
            Rectangle {
                id: highDot
                objectName: "hrHighDot"
                readonly property var p: tile.chart.maxAt >= 0 ? tile.chart.points[tile.chart.maxAt] : null
                visible: p !== null
                width: Theme.dp(6)
                height: width
                radius: width / 2
                color: TC.HR_HIGH
                x: p ? p.x - width / 2 : 0
                y: p ? p.y - height / 2 : 0
            }
            Label {
                id: highLabel
                objectName: "hrHighLabel"
                visible: highDot.visible
                text: tile.chart.max
                role: "bodySmall"
                color: TC.HR_HIGH
                x: highDot.p ? Math.max(-plot.x / 2, Math.min(plot.width - width + plot.x / 2, highDot.p.x - width / 2)) : 0
                y: highDot.p ? Math.max(-plot.y + Theme.dp(2), highDot.p.y - height - Theme.dp(1)) : 0
            }
            // the lowest: blue, label under it
            Rectangle {
                id: lowDot
                objectName: "hrLowDot"
                readonly property var p: tile.chart.minAt >= 0 ? tile.chart.points[tile.chart.minAt] : null
                visible: p !== null && tile.chart.minAt !== tile.chart.maxAt
                width: Theme.dp(6)
                height: width
                radius: width / 2
                color: TC.HR_LOW
                x: p ? p.x - width / 2 : 0
                y: p ? p.y - height / 2 : 0
            }
            Label {
                id: lowLabel
                objectName: "hrLowLabel"
                visible: lowDot.visible
                text: tile.chart.min
                role: "bodySmall"
                color: TC.HR_LOW
                x: lowDot.p ? Math.max(-plot.x / 2, Math.min(plot.width - width + plot.x / 2, lowDot.p.x - width / 2)) : 0
                y: lowDot.p ? lowDot.p.y + Theme.dp(1) : 0
            }
        }

        // the window of the chart
        Label {
            id: caption
            objectName: "hrCaption"
            visible: tile.hasData
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.dp(4)
            text: tile.windowText
            role: "bodySmall"
            color: "#BEC8C6"
            maximumLineCount: 1
        }

        Label {
            id: empty
            objectName: "hrEmpty"
            visible: !tile.hasData
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(18)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            //% "No heart rate data has been collected in the last 2 hrs."
            text: qsTrId("id-tile-hr-empty") + localeManager.changesObserver
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
        }
    }

    // the chart's line, and the polygon under it for the fill
    readonly property var linePath: {
        var out = []
        for (var i = 0; i < chart.points.length; i++)
            out.push(Qt.point(chart.points[i].x, chart.points[i].y))
        return out
    }
    readonly property var fillPath: {
        var out = linePath.slice()
        if (out.length > 0) {
            out.push(Qt.point(out[out.length - 1].x, plot.height))
            out.push(Qt.point(out[0].x, plot.height))
        }
        return out
    }
}
