/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "tilecontent.js" as TC
import "file:///usr/share/asteroid-weather/weatherdata.js" as WD
import "file:///usr/share/asteroid-weather/icons.js" as WI

/*
 * Forecast, as Pixel Weather's tile (tiles-individual-14, -15, weather-calendar-15; ForecastTileService, hlh.java:41-196):
 * the title is the city (white, the frame's); under it three cards in the 344 x 180 px of the middle: on the left a
 * tall card (164 px, corner 52 px) in the colour of the condition (the app's own art, icons.js) with the current
 * temperature (60 px) and "Feels 12°" (24 px); on the right two 172 x 86 px pills 8 px apart: the day's high
 * and low with arrows (tertiary container), and "UV 3" on the colour of its band (0-2 #BEEFBB, 3-5 #FFE07C, 6-7 #FFB683,
 * 8-10 #FF8983, 11+ #C597FF) or, when the chance of rain is above 5 %, "40%" on #A1C9FF. No edge button; each card is
 * its own click target and opens the Weather app. A field the source does not have shows "--".
 *
 * The data and the day logic are the Weather app's (weatherdata.js, installed with its icons under
 * /usr/share/asteroid-weather: the extended forecast of Gadgetbridge or eos-weather, the old five-day keys as the
 * fallback, units converted once). States as the stock tile: "Loading Weather…" while nothing has come; "Can’t
 * download weather data" and "Couldn’t retrieve your location" with the edge button Retry (a request for eos-weather,
 * /org/asteroidos/weather/refresh-request, as the app's Refresh); "Couldn’t connect to internet..." with Settings.
 *
 * Battery: nothing runs but the 30 s wait of a request, one single shot, only while the tile is awake on screen.
 */
TileBase {
    id: tile
    title: (src.city.value !== "" ? String(src.city.value)
                              //% "Forecast"
                              : qsTrId("id-tile-forecast")) + localeManager.changesObserver
    backgroundTap: false
    accent: Theme.color.primary
    chipText: tile.screenState === "ok" ? "" : TC.weatherStateButton(tile.screenState)
    onChipClicked: {
        if (tile.screenState === "noconnection")
            desktop.openSettings("connectivity")
        else
            tile.refresh()
    }

    // the forecast, its day logic and its state (the Weather app's), shared with the Solar and UV tiles
    WeatherSource {
        id: src
        clock: tile.clock
        live: tile.live
        awake: tile.awake && !tile.preview
    }
    readonly property alias source: src
    readonly property string screenState: src.screenState
    readonly property var weather: src.weather
    function refresh() { src.refresh() }

    // what the cards show
    readonly property var current: weather.now
    readonly property var today: src.today
    readonly property bool fahr: src.fahrenheit.value === true
    readonly property string tempText: TC.degrees(current ? current.c : null, fahr)
    readonly property string feelsText: TC.degrees(current ? current.feels : null, fahr)
    readonly property string highText: TC.degrees(today ? today.hi : (current ? current.hi : null), fahr)
    readonly property string lowText: TC.degrees(today ? today.lo : (current ? current.lo : null), fahr)
    readonly property var pill: TC.forecastPill(current ? current.pop : null, current && current.uv !== null ? current.uv : (today ? today.uv : null))
    readonly property string conditionKey: current ? current.key : "not_available"
    readonly property bool isDay: current ? current.isDay : true

    // the three cards, in the middle slot: 344 x 180 px
    Item {
        id: cards
        objectName: "weatherCards"
        visible: tile.screenState === "ok"
        width: tile.body.width
        height: Math.min(Theme.dp(90), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        readonly property real gap: Theme.dp(4)
        readonly property real leftWidth: Math.round(width * 0.4767)
        readonly property real rightHeight: (height - gap) / 2

        TileCard {
            id: leftCard
            objectName: "weatherNow"
            width: cards.leftWidth
            height: cards.height
            radius: Theme.dp(26)
            containerColor: WI.backgroundColor(tile.conditionKey, tile.isDay)
            contentColor: "#FFFFFF"
            preview: tile.preview
            accessibleName: tile.title + ", " + tile.tempText
            onClicked: desktop.launchByName("asteroid-weather", leftCard)

            // the art: the condition's colour darkening towards the bottom
            Rectangle {
                anchors.fill: parent
                radius: leftCard.radius
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#59000000" }
                }
            }
            Image {
                id: conditionIcon
                objectName: "weatherIcon"
                x: (parent.width - width) / 2
                y: Theme.dp(8)
                width: Theme.dp(28)
                height: width
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectFit
                source: "file:///usr/share/asteroid-weather/icons/" + WI.iconPath(tile.conditionKey, tile.isDay, false)
            }
            Label {
                id: tempLabel
                objectName: "weatherTemp"
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.dp(38)
                text: tile.tempText
                role: "numeralSmall"
                font.features: Theme.tabularNumerals
                color: "#FFFFFF"
                maximumLineCount: 1
            }
            Label {
                id: feelsLabel
                objectName: "weatherFeels"
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.dp(68)
                width: parent.width - Theme.dp(8)
                horizontalAlignment: Text.AlignHCenter
                //% "Feels %1"
                text: qsTrId("id-tile-feels-like").replace("%1", tile.feelsText) + localeManager.changesObserver
                role: "bodySmall"
                color: "#FFFFFF"
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        // the day's high and low, arrows before them
        TileCard {
            id: highLowCard
            objectName: "weatherHighLow"
            x: cards.leftWidth + cards.gap
            width: cards.width - x
            height: cards.rightHeight
            containerColor: Theme.color.tertiaryContainer
            contentColor: Theme.color.onTertiaryContainer
            preview: tile.preview
            //% "High of %1 and low of %2"
            accessibleName: qsTrId("id-tile-high-low").replace("%1", tile.highText).replace("%2", tile.lowText)
            onClicked: desktop.launchByName("asteroid-weather", highLowCard)

            Row {
                anchors.centerIn: parent
                spacing: Theme.dp(10)
                Row {
                    spacing: Theme.dp(1)
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "ms-arrow_upward"
                        color: Theme.color.onTertiaryContainer
                        width: Theme.dp(14)
                        height: width
                    }
                    Label {
                        objectName: "weatherHigh"
                        text: tile.highText
                        role: "titleMedium"
                        font.features: Theme.tabularNumerals
                        color: Theme.color.onTertiaryContainer
                    }
                }
                Row {
                    spacing: Theme.dp(1)
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "ms-arrow_downward"
                        color: Theme.color.onTertiaryContainer
                        width: Theme.dp(14)
                        height: width
                    }
                    Label {
                        objectName: "weatherLow"
                        text: tile.lowText
                        role: "titleMedium"
                        font.features: Theme.tabularNumerals
                        color: Theme.color.onTertiaryContainer
                    }
                }
            }
        }

        // UV on the colour of its band, or the chance of rain above 5 %
        TileCard {
            id: pillCard
            objectName: "weatherPill"
            x: cards.leftWidth + cards.gap
            y: cards.rightHeight + cards.gap
            width: cards.width - x
            height: cards.rightHeight
            readonly property bool rain: tile.pill.kind === "rain"
            readonly property var band: tile.pill.uv !== null ? TC.uvBand(tile.pill.uv) : null
            containerColor: rain ? TC.PRECIP_BG : (band ? band.bg : Theme.color.surfaceContainer)
            contentColor: rain ? TC.PRECIP_FG : (band ? band.fg : Theme.color.onSurface)
            preview: tile.preview
            accessibleName: pillLabel.text
            onClicked: desktop.launchByName("asteroid-weather", pillCard)

            Row {
                anchors.centerIn: parent
                spacing: Theme.dp(4)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: pillCard.rain ? "ms-rainy" : "ms-sunny"
                    color: pillCard.contentColor
                    width: Theme.dp(14)
                    height: width
                }
                Label {
                    id: pillLabel
                    objectName: "weatherPillText"
                    text: pillCard.rain
                          //% "%1%"
                          ? qsTrId("id-tile-percent").replace("%1", tile.pill.pop)
                          //% "UV %1"
                          : qsTrId("id-tile-uv-index").replace("%1", tile.pill.uv !== null ? tile.pill.uv : "--")
                    role: "titleMedium"
                    font.features: Theme.tabularNumerals
                    color: pillCard.contentColor
                }
            }
        }
    }

    // not ready: the text in the middle, Retry or Settings as the edge button
    Label {
        id: stateLabel
        objectName: "weatherState"
        visible: tile.screenState !== "ok"
        anchors.centerIn: parent
        width: parent.width - Theme.dp(8)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: TC.weatherStateText(tile.screenState) + localeManager.changesObserver
        role: "bodyMedium"
        color: tile.screenState === "loading" ? Theme.color.onSurfaceVariant : Theme.color.onSurface
    }
}
