/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher
import org.asteroid.sensorlogd
import "tilecontent.js" as TC
import "../system/goals.js" as Goals

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
 *
 * The goal is the main goal (R5 E-18): stock's tile follows the account's primary goal type (PrimaryGoalType STEPS,
 * CALORIES, DISTANCE, FLOORS, AZM; aflu.java:D), which the phone sets in /org/asteroidos/health/goals/main
 * (asteroid-sensorlogd metrics/goals.h, its keys and defaults: tilecontent.js MAIN_GOAL_*). For calories, distance,
 * floors and Active Zone Minutes the title is the metric's (the celebration's names), the count the day's value from
 * HealthMetricsLoader.summary() (read while the tile is on screen and when health.db changes), the distance in the
 * phone's unit system (else the locale's), the ring the metric's icon, Daily Goal the goal as the celebration writes it.
 */
TileBase {
    id: tile
    title: (goalType === "steps"
            //% "Steps"
            ? qsTrId("id-tile-steps")
            : goalType === "calories" ? qsTrId("id-goal-calories")
            : goalType === "distance" ? qsTrId("id-goal-distance")
            : goalType === "floors" ? qsTrId("id-goal-floors")
            : qsTrId("id-goal-azm")) + localeManager.changesObserver
    backgroundTap: false
    //% "Daily Goal"
    bottomLabel: qsTrId("id-tile-daily-goal") + localeManager.changesObserver
    bottomValue: goalType === "steps" ? Number(goal.value).toLocaleString(Qt.locale(), "f", 0)
                                      : Goals.valueText({ metric: goalType, value: target }, Qt.locale(), imperial, formats)
                                        + localeManager.changesObserver
    bottomValueColor: TC.GREEN

    // ---- the main goal's type and target (R5 E-18) ----
    ConfigurationValue { id: mainGoal; key: "/org/asteroidos/health/goals/main"; defaultValue: "steps" }
    ConfigurationValue { id: caloriesGoal; key: "/org/asteroidos/health/goals/calories"; defaultValue: 0 }
    ConfigurationValue { id: distanceGoal; key: "/org/asteroidos/health/goals/distance-m"; defaultValue: 0 }
    ConfigurationValue { id: floorsGoal; key: "/org/asteroidos/health/goals/floors"; defaultValue: 0 }
    ConfigurationValue { id: azmGoal; key: "/org/asteroidos/health/goals/azm"; defaultValue: 0 }
    readonly property string goalType: TC.mainGoalType(mainGoal.value)
    readonly property real target: TC.mainGoalTarget(goalType,
                                                      goalType === "steps" ? goal.value
                                                      : goalType === "calories" ? caloriesGoal.value
                                                      : goalType === "distance" ? distanceGoal.value
                                                      : goalType === "floors" ? floorsGoal.value : azmGoal.value)
    // the distance in the phone's unit system (asteroid-btsyncd's settings/imperial-units), else the locale's
    ConfigurationValue {
        id: units
        key: "/org/asteroidos/settings/imperial-units"
        defaultValue: tile.localeImperial(localeManager.localeRevision)
    }
    function localeImperial(revision) { return Qt.locale().measurementSystem !== Locale.MetricSystem }
    readonly property bool imperial: units.value === true || units.value === "true"
    readonly property var formats: ({
        cal: qsTrId("id-goal-cal-value"),
        floors: qsTrId("id-goal-floors-value"),
        azm: qsTrId("id-goal-azm-value"),
        hours: qsTrId("id-goal-hours-value"),
        km: qsTrId("id-goal-km-value"),
        mi: qsTrId("id-goal-mi-value")
    })

    // the day's summary, for a main goal that is not steps: read only while the tile is on screen
    property var summary: ({})
    property var metrics: null
    onLiveChanged: {
        if (live) {
            Qt.callLater(reload)
        } else {
            if (metrics) {
                metrics.destroy()
                metrics = null
            }
            summary = ({})
        }
    }
    onGoalTypeChanged: Qt.callLater(reload)
    Component.onCompleted: Qt.callLater(reload)
    function reload() {
        if (!live || preview || goalType === "steps") {
            if (metrics) {
                metrics.destroy()
                metrics = null
            }
            return
        }
        if (!metrics)
            metrics = metricsComponent.createObject(tile, { "objectName": "mainGoalLoader" })
        summary = metrics.summary(new Date(tile.clock()))
    }
    Component {
        id: metricsComponent
        HealthMetricsLoader {
            onDataChanged: tile.reload()
        }
    }

    HealthLog {
        id: log
        sensor: "stepCounter"
        buckets: 24
        active: tile.live && !tile.preview && tile.goalType === "steps"
    }

    ConfigurationValue {
        id: goal
        key: "/org/asteroidos/ux/steps-goal"
        defaultValue: 10000
    }

    // Health opens on its steps page (CR-36, health-fitness-30): "steps@<ms>" before the start,
    // as the heart rate tile and the steps complication ask for their pages
    ConfigurationValue {
        id: openRequest
        key: "/org/asteroidos/health/ui/open"
        defaultValue: ""
    }
    // the main goal's page: steps (and distance, as the distance complication), energy, floors, azm
    function openSteps() {
        var page = goalType === "calories" ? "energy" : goalType === "floors" ? "floors" : goalType === "azm" ? "azm" : "steps"
        openRequest.value = page + "@" + Date.now()
        desktop.launchByName("asteroid-health", tile)
    }

    readonly property int steps: log.hasData ? log.lastValue : 0
    // the day's value of the main goal's metric (steps: the log's count)
    readonly property real value: TC.mainGoalValue(goalType, summary, steps)
    readonly property var standing: TC.goalState(value, target)
    readonly property string pillText: {
        var n = TC.mainGoalNumber(goalType, standing.n, imperial, Qt.locale())
        if (goalType === "distance")
            n = (imperial ? formats.mi : formats.km).replace("%1", n)
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
        onClicked: tile.openSteps()

        Column {
            x: Theme.dp(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.dp(2)
            Label {
                id: countLabel
                objectName: "goalCount"
                text: TC.mainGoalNumber(tile.goalType, tile.value, tile.imperial, Qt.locale())
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
                    objectName: "goalIcon"
                    anchors.centerIn: parent
                    name: tile.goalType === "steps" ? "ms-directions_walk" : Goals.metric(tile.goalType).icon
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
