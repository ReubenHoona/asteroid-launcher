/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Amber.Mpris
import org.asteroid.controls

// What plays on the phone (asteroid-btsyncd's MPRIS player) or on the
// watch, with previous, play/pause and next, as Wear OS's media tile
TileBase {
    id: tile
    //% "Media"
    title: (mpris.identity && mpris.identity !== "Asteroid BLE Sync Daemon" ? mpris.identity
                                                                          : qsTrId("id-tile-media")) + localeManager.changesObserver
    accent: "#78d9ec"
    //% "Music"
    chipText: present ? "" : qsTrId("id-tile-music") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-music", null)

    MprisController { id: mpris }

    readonly property bool present: mpris.currentService !== "" && mpris.currentService !== undefined
                                    && (mpris.metaData.title !== undefined && mpris.metaData.title !== "")
    readonly property bool playing: present && mpris.playbackStatus === Mpris.Playing

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Math.round(tile.height * 0.02)
        visible: tile.present

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: mpris.metaData.title ? mpris.metaData.title : ""
            font.pixelSize: Math.round(tile.height * 0.065)
            font.styleName: "SemiCondensed Medium"
        }
        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            opacity: 0.7
            text: (mpris.metaData.contributingArtist || []).join(", ")
            font.pixelSize: Math.round(tile.height * 0.05)
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(tile.width * 0.03)
            Repeater {
                model: ["previous", "play", "next"]
                delegate: MouseArea {
                    readonly property bool main: modelData === "play"
                    width: Math.round(tile.width * (main ? 0.24 : 0.17))
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        Haptics.click()
                        if (modelData === "previous" && mpris.canGoPrevious) mpris.previous()
                        else if (modelData === "next" && mpris.canGoNext) mpris.next()
                        else if (modelData === "play") {
                            if (tile.playing && mpris.canPause) mpris.pause()
                            else if (mpris.canPlay) mpris.play()
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: main ? tile.accent : "#2d2d30"
                        opacity: parent.pressed ? 0.7 : 1
                    }
                    Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        color: main ? "#000000" : "#ffffff"
                        name: modelData === "previous" ? "ios-skip-backward"
                              : modelData === "next" ? "ios-skip-forward"
                              : tile.playing ? "ios-pause" : "ios-play"
                    }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: !tile.present
        spacing: Math.round(tile.height * 0.02)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "ios-musical-notes-outline"
            width: Math.round(tile.height * 0.12)
            height: width
            opacity: 0.7
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.055)
            //% "Nothing playing"
            text: qsTrId("id-tile-nothing-playing") + localeManager.changesObserver
        }
    }
}
