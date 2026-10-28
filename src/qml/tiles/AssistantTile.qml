/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "../desktop.js" as Desktop

// The Assistant tile, as Wear OS had it: suggestions to tap (asked as
// typed questions) and the edge button that starts listening.
TileBase {
    id: tile
    //% "Assistant"
    title: qsTrId("id-tile-assistant") + localeManager.changesObserver
    accent: "#a8c7fa"
    chipIcon: "ios-mic"
    //% "Speak"
    chipText: qsTrId("id-tile-speak") + localeManager.changesObserver
    onChipClicked: if (Desktop.compositorRoot) Desktop.compositorRoot.openAssistant("")

    function loc(id, en) {
        var s = qsTrId(id)
        return (s === id || s === "") ? en : s
    }
    readonly property var suggestions: [
        { text: loc("id-tile-asst-weather", "What's the weather?"), icon: "ios-cloudy-outline" },
        { text: loc("id-tile-asst-timer", "Set a timer for 5 minutes"), icon: "ios-timer-outline" },
        { text: loc("id-tile-asst-alarm", "When is my next alarm?"), icon: "ios-alarm-outline" }
    ]

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Math.round(tile.height * 0.022)
        Repeater {
            model: tile.suggestions
            delegate: MouseArea {
                width: parent.width
                height: Math.round(tile.height * 0.13)
                onClicked: {
                    Haptics.click()
                    if (Desktop.compositorRoot)
                        Desktop.compositorRoot.openAssistant(modelData.text)
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "#2d2d30"
                    opacity: parent.pressed ? 0.7 : 1
                }
                Row {
                    anchors.centerIn: parent
                    spacing: Math.round(tile.width * 0.02)
                    Icon {
                        name: modelData.icon
                        color: tile.accent
                        width: Math.round(tile.height * 0.05)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: modelData.text
                        font.pixelSize: Math.round(tile.height * 0.046)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
