/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "tilecontent.js" as TC

/*
 * Solar, as Pixel Weather's tile (tiles-individual-16, weather-calendar-16; SolarTileService, hmg.java:88-179): the
 * title is the city ("Solar" without one), one stadium card with "Sunrise in" (or "Sunset in"), the time left
 * ("6h 11m", "45m", "Now" under a minute) and the time of the event, on the right a half ring with the sun's
 * way through the day (or the night) and the sun at its place; under the card the bottom text with the event after
 * it ("Sunset" and its time). Without sun times: "No sunrise/sunset data". A tap on the card opens the Weather app.
 * Not in the stock default list (the retail one): the add list only.
 *
 * The sun times are the forecast's (the Weather app's data, WeatherSource). Battery: the countdown is told the
 * time again at each whole minute by a single-shot timer, only while the tile shows with the display on.
 */
TileBase {
    id: tile
    title: (src.city.value !== "" ? String(src.city.value)
                                  //% "Solar"
                                  : qsTrId("id-tile-solar")) + localeManager.changesObserver
    backgroundTap: false

    WeatherSource {
        id: src
        live: tile.live
        awake: tile.awake && !tile.preview
    }
    readonly property alias source: src

    readonly property var next: src.solar
    readonly property bool known: next.kind !== "none"
    readonly property var other: TC.otherSun(src.weather.days, next)
    readonly property real nowSec: Math.floor(src.now.getTime() / 1000)
    readonly property string eventWord: next.kind === "sunset"
        //% "Sunset"
        ? qsTrId("id-tile-sunset")
        //% "Sunrise"
        : qsTrId("id-tile-sunrise")
    readonly property string inText: next.kind === "sunset"
        //% "Sunset in"
        ? qsTrId("id-tile-sunset-in")
        //% "Sunrise in"
        : qsTrId("id-tile-sunrise-in")
    readonly property string remaining: known ? TC.solarDuration(next.inSec) : ""
    readonly property string eventTime: known ? TimeFormat.time(new Date(next.at * 1000)) : ""
    readonly property real progress: known ? next.frac : 0

    bottomLabel: (other.kind === "sunrise" ? qsTrId("id-tile-sunrise") : other.kind === "sunset" ? qsTrId("id-tile-sunset") : "")
                 + localeManager.changesObserver
    bottomValue: other.kind !== "none" ? TimeFormat.time(new Date(other.at * 1000)) : ""

    // one single shot to the next whole minute, only while the tile shows with the display on. A single-shot Timer
    // whose running is a binding is not restarted by the binding after it fired (its inputs do not change), so each
    // tick sets the time, works out the next interval and restarts itself (the reviewer's defect, W3 review fixes).
    // tickMs > 0 is a test hook: a fixed interval instead of the whole minute.
    property int tickMs: 0
    function msToNextMinute() {
        return tile.tickMs > 0 ? tile.tickMs : Math.max(1000, 60000 - (Date.now() % 60000) + 200)
    }
    Timer {
        id: minute
        objectName: "solarMinute"
        interval: tile.msToNextMinute()
        repeat: false
        running: tile.awake && !tile.preview && tile.known
        onRunningChanged: if (running) interval = tile.msToNextMinute()
        onTriggered: {
            src.now = new Date()
            interval = tile.msToNextMinute()
            if (tile.awake && !tile.preview && tile.known)
                restart()
        }
    }

    TileCard {
        id: card
        objectName: "solarCard"
        width: tile.body.width
        height: Math.min(Theme.dp(62), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        preview: tile.preview
        accessibleName: tile.known ? tile.inText + " " + tile.remaining + ", " + tile.eventTime : emptyLabel.text
        onClicked: desktop.launchByName("asteroid-weather", card)

        Column {
            id: texts
            visible: tile.known
            x: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.55
            Label {
                objectName: "solarIn"
                text: tile.inText + localeManager.changesObserver
                role: "bodySmall"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
            Label {
                objectName: "solarRemaining"
                text: tile.remaining
                font.pixelSize: Theme.dp(24)
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurface
                maximumLineCount: 1
            }
            Label {
                objectName: "solarTime"
                text: tile.eventTime
                role: "bodySmall"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
        }

        // the half ring: sunrise at the left end, sunset at the right, the sun at its place
        Item {
            id: arc
            objectName: "solarArc"
            visible: tile.known
            width: Theme.dp(44)
            height: Theme.dp(26)
            anchors.right: parent.right
            anchors.rightMargin: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            readonly property real stroke: Theme.dp(3)
            readonly property real radius: width / 2 - stroke / 2
            readonly property real angle: Math.PI * (1 + tile.progress)
            Shape {
                anchors.fill: parent
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.color.surfaceContainerHigh
                    strokeWidth: arc.stroke
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: arc.width / 2; centerY: arc.height - arc.stroke; radiusX: arc.radius; radiusY: arc.radius; startAngle: 180; sweepAngle: 180 }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: "#FCBD00"
                    strokeWidth: arc.stroke
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: arc.width / 2; centerY: arc.height - arc.stroke; radiusX: arc.radius; radiusY: arc.radius; startAngle: 180; sweepAngle: Math.max(0.5, 180 * tile.progress) }
                }
            }
            Rectangle {
                objectName: "solarSun"
                width: Theme.dp(8)
                height: width
                radius: width / 2
                color: "#FCBD00"
                x: arc.width / 2 + arc.radius * Math.cos(arc.angle) - width / 2
                y: arc.height - arc.stroke + arc.radius * Math.sin(arc.angle) - height / 2
            }
        }

        Label {
            id: emptyLabel
            objectName: "solarEmpty"
            visible: !tile.known
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(18)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            //% "No sunrise/sunset data"
            text: qsTrId("id-tile-no-sun") + localeManager.changesObserver
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
        }
    }
}
