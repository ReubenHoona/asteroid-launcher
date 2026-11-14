/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "tilecontent.js" as TC

/*
 * UV Index, as Pixel Weather's tile (tiles-individual-17, weather-calendar-16; kbn.java:557-592, hls.java:164): the
 * title is the city ("UV Index" without one), one stadium card with "UV 3" and the band's word (Low, Moderate, High,
 * Very High, Extreme) in the band's label colour, on the right a ring in the band's colour (#80DA88, #FCBD00,
 * #FF8D41, #F55E57, #AD72FF) with a dot at the value; under the card the bottom text "Max UV" and the day's highest.
 * No UV in the forecast: "UV --" and "No data". A tap on the card opens the Weather app. In the add list only.
 *
 * The values are the forecast's now.uv and today's uv (the Weather app's data, WeatherSource). Nothing runs here.
 */
TileBase {
    id: tile
    title: (src.city.value !== "" ? String(src.city.value)
                                  //% "UV Index"
                                  : qsTrId("id-tile-uv-title")) + localeManager.changesObserver
    backgroundTap: false

    WeatherSource {
        id: src
        live: tile.live
        awake: tile.awake && !tile.preview
    }
    readonly property alias source: src

    readonly property var current: src.weather.now
    readonly property var today: src.today
    function _num(v) { return v === null || v === undefined || v === "" || !isFinite(Number(v)) ? null : Number(v) }
    readonly property var uv: _num(current && current.uv !== null ? current.uv : (today ? today.uv : null))
    readonly property var maxUv: _num(today ? today.uv : null)
    readonly property bool known: uv !== null
    readonly property var band: known ? TC.uvBand(uv) : null
    readonly property real fraction: known ? Math.min(1, uv / 11) : 0

    //% "Max UV"
    bottomLabel: qsTrId("id-tile-max-uv") + localeManager.changesObserver
    bottomLabelRole: "bodySmall"
    bottomValueRole: "labelSmall"
    bottomValue: maxUv !== null ? String(Math.round(maxUv)) : "--"

    TileCard {
        id: card
        objectName: "uvCard"
        width: tile.body.width
        height: Math.min(Theme.dp(62), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        preview: tile.preview
        accessibleName: indexLabel.text + " " + wordLabel.text
        onClicked: desktop.launchByName("asteroid-weather", card)

        Column {
            x: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.6
            Label {
                id: indexLabel
                objectName: "uvIndex"
                //% "UV %1"
                text: qsTrId("id-tile-uv-index").replace("%1", tile.known ? Math.round(tile.uv) : "--")
                font.pixelSize: Theme.dp(24)
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurface
                maximumLineCount: 1
            }
            Label {
                id: wordLabel
                objectName: "uvWord"
                //% "No data"
                text: tile.known ? TC.uvWord(tile.uv) : qsTrId("id-tile-no-data")
                role: "titleSmall"
                color: tile.known ? tile.band.label : Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
        }

        // the ring in the band's colour, the dot at the value (0 to 11 round three quarters)
        Item {
            id: dial
            objectName: "uvDial"
            width: Theme.dp(44)
            height: width
            anchors.right: parent.right
            anchors.rightMargin: Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            readonly property real stroke: Theme.dp(4)
            readonly property real radius: width / 2 - stroke / 2 - Theme.dp(2)
            readonly property real angle: (135 + 270 * tile.fraction) * Math.PI / 180
            Shape {
                anchors.fill: parent
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Theme.color.surfaceContainerHigh
                    strokeWidth: dial.stroke
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: dial.radius; radiusY: dial.radius; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: tile.known ? tile.band.ring : "transparent"
                    strokeWidth: dial.stroke
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: dial.radius; radiusY: dial.radius; startAngle: 135; sweepAngle: Math.max(0.5, 270 * tile.fraction) }
                }
            }
            Rectangle {
                objectName: "uvDot"
                visible: tile.known
                width: Theme.dp(8)
                height: width
                radius: width / 2
                color: "#FFFFFF"
                x: dial.width / 2 + dial.radius * Math.cos(dial.angle) - width / 2
                y: dial.height / 2 + dial.radius * Math.sin(dial.angle) - height / 2
            }
        }
    }
}
