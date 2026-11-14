/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.sensorlogd
import "tilecontent.js" as TC

/*
 * Sleep, as the Fitbit tile (tiles-individual-22, health-fitness-32; aarf.java:431-560, tile_sleep_preview.xml): the
 * title "Sleep", one graphic data card (#29303D, corner 52 px) with the time asleep large ("7h 31m"), under it the
 * bedtime and the wake time each with its icon, and on the right a ring (lavender #E5C7FF) towards the sleep goal
 * round a moon, "2x" at twice the goal or more. Under the card the bottom text "Sleep score" and the score in green
 * ("- -" without one). No recent night: "No recent data. Wear your watch to sleep." in the card. A tap on the
 * card opens the Health app on its sleep card.
 *
 * The night is asteroid-sensorlogd's estimate (SleepDataLoader.lastNight(): steps and heart rate, no sleep stage
 * sensor: the time asleep, bedtime and wake time are estimates and the score is ours; stock's come from Fitbit).
 * Battery (M1): the loader is made, and the files read, only while the tile is on screen; nothing runs otherwise.
 */
TileBase {
    id: tile
    //% "Sleep"
    title: qsTrId("id-tile-sleep") + localeManager.changesObserver
    backgroundTap: false
    //% "Sleep score"
    bottomLabel: (sum.valid ? qsTrId("id-tile-sleep-score") : "") + localeManager.changesObserver
    bottomValue: sum.valid ? (sum.score > 0 ? String(sum.score) : "- -") : ""
    bottomValueColor: TC.GREEN
    // 24 / 26 px: a line of 14 characters has to fit between the round screen's edges (28 px is the frame's default)
    bottomLabelRole: "bodySmall"
    bottomValueRole: "labelSmall"

    onLiveChanged: {
        if (live) {
            // after the editor has said it is a picture (a preview reads nothing)
            Qt.callLater(reload)
        } else {
            // nothing stays: no loader and no file watcher while the tile is off screen
            if (dataLoader) {
                dataLoader.destroy()
                dataLoader = null
            }
            night = ({})
        }
    }
    Component.onCompleted: Qt.callLater(reload)
    function reload() {
        if (!live || preview)
            return
        if (!dataLoader)
            dataLoader = loaderComponent.createObject(tile, { "objectName": "sleepLoader" })
        night = dataLoader.lastNight()
    }
    property var night: ({})
    property var dataLoader: null
    readonly property var sum: TC.sleepSummary(night)

    Component {
        id: loaderComponent
        SleepDataLoader {
            onDataChanged: tile.reload()
        }
    }

    TileCard {
        id: card
        objectName: "sleepCard"
        width: tile.body.width
        height: Math.min(Theme.dp(66), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: TC.CARD
        contentColor: Theme.color.onSurface
        radius: Theme.dp(26)
        preview: tile.preview
        accessibleName: tile.title + ", " + (tile.sum.valid ? duration.text : empty.text)
        onClicked: {
            openRequest.value = "sleep@" + Date.now()
            desktop.launchByName("asteroid-health", card)
        }

        Column {
            id: left
            visible: tile.sum.valid
            x: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.dp(1)
            Label {
                id: duration
                objectName: "sleepDuration"
                text: tile.sum.valid ? TC.durationText(tile.sum.asleepMin) : ""
                font.pixelSize: Theme.dp(22)
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurface
                maximumLineCount: 1
            }
            Row {
                spacing: Theme.dp(3)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "ms-bedtime"
                    color: TC.SLEEP_RING
                    width: Theme.dp(10)
                    height: width
                }
                Label {
                    objectName: "sleepBed"
                    text: tile.sum.valid ? TimeFormat.time(tile.sum.bed) : ""
                    font.pixelSize: Theme.dp(11)
                    color: Theme.color.onSurfaceVariant
                    maximumLineCount: 1
                }
            }
            Row {
                spacing: Theme.dp(3)
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "ms-sunny"
                    color: TC.SLEEP_RING
                    width: Theme.dp(10)
                    height: width
                }
                Label {
                    objectName: "sleepWake"
                    text: tile.sum.valid ? TimeFormat.time(tile.sum.wake) : ""
                    font.pixelSize: Theme.dp(11)
                    color: Theme.color.onSurfaceVariant
                    maximumLineCount: 1
                }
            }
        }

        CircularProgressIndicator {
            id: ring
            objectName: "sleepRing"
            visible: tile.sum.valid
            width: Theme.dp(48)
            height: width
            anchors.right: parent.right
            anchors.rightMargin: Theme.dp(10)
            anchors.verticalCenter: parent.verticalCenter
            displayOn: tile.awake
            strokeWidth: Theme.dp(5)
            color: TC.SLEEP_RING
            trackColor: TC.SLEEP_TRACK
            progress: tile.sum.valid ? tile.sum.ring : 0
            Icon {
                anchors.centerIn: parent
                name: "ms-bedtime"
                color: TC.SLEEP_RING
                width: Theme.dp(22)
                height: width
            }
            // "2x" at twice the goal or more
            Rectangle {
                objectName: "sleepTimes"
                visible: tile.sum.valid && tile.sum.times >= 2
                width: timesLabel.implicitWidth + Theme.dp(8)
                height: Theme.dp(12)
                radius: height / 2
                color: TC.SLEEP_RING
                x: (parent.width - width) / 2
                y: parent.height - height / 2 - Theme.dp(2)
                Label {
                    id: timesLabel
                    anchors.centerIn: parent
                    //% "%1x"
                    text: qsTrId("id-tile-sleep-times").replace("%1", tile.sum.times)
                    font.pixelSize: Theme.dp(9)
                    font.weight: Font.Medium
                    color: "#1B1B1F"
                }
            }
        }

        Label {
            id: empty
            objectName: "sleepEmpty"
            visible: !tile.sum.valid
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(18)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            //% "No recent data. Wear your watch to sleep."
            text: qsTrId("id-tile-sleep-empty") + localeManager.changesObserver
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
        }
    }

    ConfigurationValue { id: openRequest; key: "/org/asteroidos/health/ui/open"; defaultValue: "" }
}
