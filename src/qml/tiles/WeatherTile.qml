/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "../weathericons.js" as IconTools

// Today's weather and the next three days, from the forecast the phone
// sends (asteroid-btsyncd writes it to dconf /org/asteroidos/weather)
TileBase {
    id: tile
    title: city.value !== "" ? city.value
                             //% "Weather"
                             : qsTrId("id-tile-weather") + localeManager.changesObserver
    accent: "#fdd663"
    //% "Forecast"
    chipText: qsTrId("id-tile-forecast") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-weather", null)

    ConfigurationValue { id: city; key: "/org/asteroidos/weather/city-name"; defaultValue: "" }
    ConfigurationValue { id: day0Stamp; key: "/org/asteroidos/weather/timestamp-day0"; defaultValue: 0 }
    ConfigurationValue { id: fahrenheit; key: "/org/asteroidos/settings/use-fahrenheit"; defaultValue: false }

    // which forecast day is today: the phone sends five days starting with
    // the day of its last update
    property int offset: 0
    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()
    function refresh() {
        var d0 = new Date(day0Stamp.value * 1000)
        d0.setHours(0, 0, 0, 0)
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        offset = Math.round((today - d0) / 86400000)
    }
    readonly property bool available: day0Stamp.value > 0 && offset >= 0 && offset < 5

    function temp(kelvin) {
        var c = kelvin - 273
        return (fahrenheit.value ? Math.round(c * 9 / 5 + 32) : Math.round(c)) + "°"
    }

    Repeater {
        id: days
        model: 4
        delegate: Item {
            ConfigurationValue { id: owm; key: "/org/asteroidos/weather/day" + (tile.offset + index) + "/id"; defaultValue: 0 }
            ConfigurationValue { id: lo; key: "/org/asteroidos/weather/day" + (tile.offset + index) + "/min-temp"; defaultValue: 273 }
            ConfigurationValue { id: hi; key: "/org/asteroidos/weather/day" + (tile.offset + index) + "/max-temp"; defaultValue: 273 }
            readonly property string icon: IconTools.getIconName(owm.value)
            readonly property string low: tile.temp(lo.value)
            readonly property string high: tile.temp(hi.value)
            readonly property bool known: tile.offset + index < 5
        }
    }

    Column {
        anchors.centerIn: parent
        visible: tile.available && days.count === 4
        spacing: Math.round(tile.height * 0.015)

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(tile.width * 0.03)
            Icon {
                name: days.count > 0 && days.itemAt(0) ? days.itemAt(0).icon : ""
                width: Math.round(tile.height * 0.17)
                height: width
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label {
                    text: days.count > 0 && days.itemAt(0) ? days.itemAt(0).high : ""
                    font.pixelSize: Math.round(tile.height * 0.12)
                    font.styleName: "SemiCondensed Medium"
                }
                Label {
                    text: days.count > 0 && days.itemAt(0) ? days.itemAt(0).low : ""
                    opacity: 0.7
                    font.pixelSize: Math.round(tile.height * 0.06)
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(tile.width * 0.05)
            Repeater {
                model: 3
                delegate: Column {
                    readonly property Item day: days.count === 4 ? days.itemAt(index + 1) : null
                    visible: day !== null && day.known
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var d = new Date()
                            d.setDate(d.getDate() + index + 1)
                            return d.toLocaleString(Qt.locale(), "ddd")
                        }
                        opacity: 0.7
                        font.pixelSize: Math.round(tile.height * 0.045)
                    }
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: parent.day ? parent.day.icon : ""
                        width: Math.round(tile.height * 0.07)
                        height: width
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: parent.day ? parent.day.high : ""
                        font.pixelSize: Math.round(tile.height * 0.045)
                    }
                }
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: !tile.available
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.7
        font.pixelSize: Math.round(tile.height * 0.055)
        //% "No forecast from the phone yet"
        text: qsTrId("id-tile-no-forecast") + localeManager.changesObserver
    }
}
