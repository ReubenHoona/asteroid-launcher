/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher
import "tilecontent.js" as TC

/*
 * Main goal, as the Fitbit tile (tiles-individual-19, health-fitness-07; aflu.java:D, tile_primarygoal_preview.xml):
 * the title is the goal's metric, one graphic data card (stadium, #29303D, 344 x 124 px) with the day's count
 * large on the left and a pill under it ("3,760 left", "Goal met", "6,823 over goal", the pill green when the goal is
 * met) and on the right a 96 px ring of the progress (its second lap is the overflow, in #A8C7FA) round the walking
 * icon in a filled circle, with a check when the goal is met. Under the card the bottom text: "Daily Goal" and the
 * goal in green. No edge button and no catch-all tap: a tap on the card opens the Health app.
 *
 * Steps come from asteroid-sensorlogd's log (HealthLog, read only while the tile is on screen); the goal is the
 * one key of the Health app and sensorlogd (/org/asteroidos/ux/steps-goal, LoggerSettings.stepGoalTarget).
 */
TileBase {
    id: tile
    //% "Steps"
    title: qsTrId("id-tile-steps") + localeManager.changesObserver
    backgroundTap: false
    //% "Daily Goal"
    bottomLabel: qsTrId("id-tile-daily-goal") + localeManager.changesObserver
    bottomValue: Number(goal.value).toLocaleString(Qt.locale(), "f", 0)
    bottomValueColor: TC.GREEN

    HealthLog {
        id: log
        sensor: "stepCounter"
        buckets: 24
        active: tile.live && !tile.preview
    }

    ConfigurationValue {
        id: goal
        key: "/org/asteroidos/ux/steps-goal"
        defaultValue: 10000
    }

    readonly property int steps: log.hasData ? log.lastValue : 0
    readonly property var standing: TC.goalState(steps, goal.value)
    readonly property string pillText: {
        var n = Number(standing.n).toLocaleString(Qt.locale(), "f", 0)
        switch (standing.kind) {
        case "met":
            //% "Goal met"
            return qsTrId("id-tile-goal-met") + localeManager.changesObserver
        case "over":
            //% "%1 over goal"
            return qsTrId("id-tile-goal-over").replace("%1", n) + localeManager.changesObserver
        case "left":
            //% "%1 left"
            return qsTrId("id-tile-goal-left").replace("%1", n) + localeManager.changesObserver
        }
        return ""
    }

    TileCard {
        id: card
        objectName: "goalCard"
        width: tile.body.width
        height: Theme.dp(62)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: TC.CARD
        contentColor: Theme.color.onSurface
        preview: tile.preview
        accessibleName: tile.title + ", " + countLabel.text + ", " + tile.pillText
        onClicked: desktop.launchByName("asteroid-health", tile)

        Column {
            x: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.dp(2)
            Label {
                id: countLabel
                objectName: "goalCount"
                text: Number(tile.steps).toLocaleString(Qt.locale(), "f", 0)
                font.pixelSize: Theme.dp(24)
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: Theme.color.onSurface
                maximumLineCount: 1
            }
            Rectangle {
                id: pill
                objectName: "goalPill"
                visible: tile.pillText !== ""
                width: pillLabel.implicitWidth + Theme.dp(16)
                height: Theme.dp(18)
                radius: height / 2
                color: tile.standing.met ? TC.GREEN : TC.PILL
                Label {
                    id: pillLabel
                    objectName: "goalPillText"
                    anchors.centerIn: parent
                    text: tile.pillText
                    font.pixelSize: Theme.dp(12)
                    font.weight: Font.Medium
                    color: tile.standing.met ? "#00391C" : Theme.color.onSurface
                    maximumLineCount: 1
                }
            }
        }

        CircularProgressIndicator {
            id: ring
            objectName: "goalRing"
            width: Theme.dp(48)
            height: width
            anchors.right: parent.right
            anchors.rightMargin: Theme.dp(8)
            anchors.verticalCenter: parent.verticalCenter
            displayOn: tile.awake
            strokeWidth: Theme.dp(5)
            color: tile.standing.met ? TC.GREEN : TC.GOAL_RING
            trackColor: tile.standing.ratio > 1 ? Qt.rgba(0.659, 0.78, 0.98, 0.6) : Qt.rgba(1, 1, 1, 0.14)
            progress: tile.standing.ratio

            // the metric's icon in a filled circle, a check at the bottom when the goal is met
            Rectangle {
                id: disc
                anchors.centerIn: parent
                width: Theme.dp(28)
                height: width
                radius: width / 2
                color: tile.standing.met ? TC.GREEN : TC.GOAL_RING
                Icon {
                    anchors.centerIn: parent
                    name: "ms-directions_walk"
                    color: "#1B2A3F"
                    width: Theme.dp(18)
                    height: width
                }
            }
            Rectangle {
                id: check
                objectName: "goalCheck"
                visible: tile.standing.met
                width: Theme.dp(14)
                height: width
                radius: width / 2
                color: Theme.color.background
                x: parent.width / 2 - width / 2
                y: parent.height - height - Theme.dp(1)
                Icon {
                    anchors.centerIn: parent
                    name: "ms-check"
                    color: TC.GREEN
                    width: Theme.dp(10)
                    height: width
                }
            }
        }
    }
}
