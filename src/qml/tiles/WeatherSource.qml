/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Connman
import org.asteroid.utils
import "tilecontent.js" as TC
import "file:///usr/share/asteroid-weather/weatherdata.js" as WD

/*
 * The forecast the weather tiles (Forecast, Solar, UV Index) show, one place: the extended forecast of Gadgetbridge
 * or eos-weather (dconf /org/asteroidos/weather/extended), the old five-day keys as the fallback, the day logic and
 * the unit conversion of the Weather app (weatherdata.js, installed by it under /usr/share/asteroid-weather), and the
 * state of the tile: "ok", "loading", "noconnection", "nolocation" or "downloadfailed" (the app's screenState).
 * refresh() asks eos-weather for a new forecast (/org/asteroidos/weather/refresh-request, as the app's Refresh and
 * Retry). The time the model is built for is taken again when `live` turns true and when the data changes; the one
 * timer is the 30 s wait of a request (or of no forecast yet), a single shot that runs only while `awake`.
 */
Item {
    id: source
    visible: false

    // the tile is on screen / on screen with the display on
    property bool live: false
    property bool awake: false
    // the wall clock in ms: which day is today, the sun's next event (the tile's TileBase.clock)
    property var clock: function () { return Date.now() }

    readonly property alias city: city
    readonly property alias fahrenheit: fahrenheit
    ConfigurationValue { id: city; key: "/org/asteroidos/weather/city-name"; defaultValue: "" }
    ConfigurationValue { id: extended; key: "/org/asteroidos/weather/extended"; defaultValue: "" }
    ConfigurationValue { id: day0Stamp; key: "/org/asteroidos/weather/timestamp-day0"; defaultValue: 0 }
    ConfigurationValue { id: d0id; key: "/org/asteroidos/weather/day0/id"; defaultValue: 0 }
    ConfigurationValue { id: d1id; key: "/org/asteroidos/weather/day1/id"; defaultValue: 0 }
    ConfigurationValue { id: d2id; key: "/org/asteroidos/weather/day2/id"; defaultValue: 0 }
    ConfigurationValue { id: d3id; key: "/org/asteroidos/weather/day3/id"; defaultValue: 0 }
    ConfigurationValue { id: d4id; key: "/org/asteroidos/weather/day4/id"; defaultValue: 0 }
    ConfigurationValue { id: d0min; key: "/org/asteroidos/weather/day0/min-temp"; defaultValue: 0 }
    ConfigurationValue { id: d1min; key: "/org/asteroidos/weather/day1/min-temp"; defaultValue: 0 }
    ConfigurationValue { id: d2min; key: "/org/asteroidos/weather/day2/min-temp"; defaultValue: 0 }
    ConfigurationValue { id: d3min; key: "/org/asteroidos/weather/day3/min-temp"; defaultValue: 0 }
    ConfigurationValue { id: d4min; key: "/org/asteroidos/weather/day4/min-temp"; defaultValue: 0 }
    ConfigurationValue { id: d0max; key: "/org/asteroidos/weather/day0/max-temp"; defaultValue: 0 }
    ConfigurationValue { id: d1max; key: "/org/asteroidos/weather/day1/max-temp"; defaultValue: 0 }
    ConfigurationValue { id: d2max; key: "/org/asteroidos/weather/day2/max-temp"; defaultValue: 0 }
    ConfigurationValue { id: d3max; key: "/org/asteroidos/weather/day3/max-temp"; defaultValue: 0 }
    ConfigurationValue { id: d4max; key: "/org/asteroidos/weather/day4/max-temp"; defaultValue: 0 }
    ConfigurationValue { id: fahrenheit; key: "/org/asteroidos/settings/use-fahrenheit"; defaultValue: false }
    // where the watch knows a place from, and the request for a new forecast
    ConfigurationValue { id: userCity; key: "/org/asteroidos/weather/location/city"; defaultValue: "" }
    ConfigurationValue { id: userLat; key: "/org/asteroidos/weather/location/latitude"; defaultValue: 0 }
    ConfigurationValue { id: phoneLat; key: "/org/asteroidos/weather/phone-location/latitude"; defaultValue: 0 }
    ConfigurationValue { id: refreshRequest; key: "/org/asteroidos/weather/refresh-request"; defaultValue: 0 }

    readonly property var legacy: ({
        city: city.value,
        ts: day0Stamp.value,
        ids: [d0id.value, d1id.value, d2id.value, d3id.value, d4id.value],
        mins: [d0min.value, d1min.value, d2min.value, d3min.value, d4min.value],
        maxs: [d0max.value, d1max.value, d2max.value, d3max.value, d4max.value]
    })
    readonly property var forecast: WD.parseExtended(String(extended.value))
    property var now: new Date(clock())
    readonly property var weather: WD.build(forecast, legacy, now)
    readonly property var today: WD.today(weather)
    // the sun's next event for the Solar tile, with the time
    readonly property var solar: WD.solarInfo(weather, Math.floor(now.getTime() / 1000))
    onForecastChanged: now = new Date(clock())
    onLegacyChanged: now = new Date(clock())
    onLiveChanged: if (live) now = new Date(clock())

    readonly property bool placeKnown: String(city.value) !== "" || String(userCity.value) !== ""
                                       || Number(userLat.value) !== 0 || Number(phoneLat.value) !== 0
    BluetoothStatus { id: bluetooth }
    NetworkTechnology { id: wifi; path: "/net/connman/technology/wifi" }

    // a request for a new forecast: it ends when a newer one arrives or after the wait
    property bool refreshing: false
    property bool timedOut: false
    property real refreshBase: 0
    property int waitMs: 30000
    readonly property real updated: weather.updated
    onUpdatedChanged: {
        if (refreshing && updated !== refreshBase) {
            refreshing = false
            timedOut = false
        }
    }
    function refresh() {
        refreshBase = weather.updated
        timedOut = false
        refreshing = true
        var stamp = Math.floor(Date.now() / 1000)
        refreshRequest.value = Number(refreshRequest.value) === stamp ? stamp + 1 : stamp
    }
    Timer {
        id: waitTimer
        objectName: "weatherWait"
        interval: source.waitMs
        repeat: false
        running: source.awake && (source.refreshing || (!source.weather.hasData && !source.timedOut))
        onTriggered: {
            source.timedOut = !source.weather.hasData
            source.refreshing = false
        }
    }

    readonly property string screenState: TC.weatherState({
        hasData: weather.hasData,
        refreshing: refreshing,
        timedOut: timedOut,
        phoneConnected: bluetooth.connected,
        wifiConnected: wifi.powered && wifi.connected,
        placeKnown: placeKnown
    })
}
