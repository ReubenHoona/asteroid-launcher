/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Amber.Mpris
import org.asteroid.controls

/*
 * What plays on the phone (asteroid-btsyncd's MPRIS player) or on the watch,
 * with previous, play/pause and next. Stock has no generic media tile (only
 * YouTube Music's Recents); the user keeps this one, in the add list only
 * (DECISIONS Q27, tiles-individual-31, media-controls-23). It wears the
 * stock frame: the carousel's app icon, the title in white, the three
 * buttons as Material 3 icon buttons (play/pause filled, 60 dp; previous
 * and next tonal, 52 dp; 4 dp apart: 344 px, the whole slot). Each button
 * is its own click target; a tap on empty black does nothing.
 */
TileBase {
    id: tile
    //% "Media"
    title: (mpris.identity && mpris.identity !== "Asteroid BLE Sync Daemon" ? mpris.identity
                                                                          : qsTrId("id-tile-media")) + localeManager.changesObserver
    backgroundTap: false
    //% "Music"
    chipText: present ? "" : qsTrId("id-tile-music") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-music", null)

    MprisController { id: mpris }
    // the player (the tests read what was asked of it)
    readonly property QtObject player: mpris

    readonly property bool present: mpris.currentService !== "" && mpris.currentService !== undefined
                                    && (mpris.metaData.title !== undefined && mpris.metaData.title !== "")
    readonly property bool playing: present && mpris.playbackStatus === Mpris.Playing

    function press(which) {
        if (which === "previous" && mpris.canGoPrevious) mpris.previous()
        else if (which === "next" && mpris.canGoNext) mpris.next()
        else if (which === "play") {
            if (tile.playing && mpris.canPause) mpris.pause()
            else if (mpris.canPlay) mpris.play()
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.dp(2)
        visible: tile.present

        Label {
            objectName: "mediaTrack"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: mpris.metaData.title ? mpris.metaData.title : ""
            role: "titleMedium"
            color: Theme.color.onSurface
            maximumLineCount: 1
        }
        Label {
            objectName: "mediaArtist"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: (mpris.metaData.contributingArtist || []).join(", ")
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
            maximumLineCount: 1
        }
        Item { width: 1; height: Theme.dp(2) }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.dp(4)
            Repeater {
                model: ["previous", "play", "next"]
                delegate: IconButton {
                    objectName: "media_" + modelData
                    readonly property bool main: modelData === "play"
                    anchors.verticalCenter: parent.verticalCenter
                    size: main ? Theme.size.iconButtonLarge : Theme.size.iconButton
                    variant: main ? "filled" : "tonal"
                    iconName: modelData === "previous" ? "ios-skip-backward"
                              : modelData === "next" ? "ios-skip-forward"
                              : tile.playing ? "ios-pause" : "ios-play"
                    onClicked: tile.press(modelData)
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: !tile.present
        spacing: Theme.dp(10)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "ios-musical-notes-outline"
            width: Theme.dp(24)
            height: width
            color: Theme.color.onSurfaceVariant
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            role: "bodyLarge"
            color: Theme.color.onSurfaceVariant
            //% "Nothing playing"
            text: qsTrId("id-tile-nothing-playing") + localeManager.changesObserver
        }
    }
}
