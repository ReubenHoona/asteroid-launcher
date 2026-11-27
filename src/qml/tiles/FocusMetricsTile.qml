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

/*
 * Focus Metrics, as the Fitbit tile (R5 E-17; TileFocusMetricsService, xly.java b(): the title 0x7f140886 "Focus
 * Metrics", three metric cards and the edge button 0x7f140c14 "More" in the secondary container colour). The cards
 * are stock's three (ync.java a(), the tile's preview): cardio load, steps and sleep, each a progress ring round the
 * metric's icon with its number and a second line under it; a tap opens the Health app on that metric (stock: Today
 * at DETAILS for it), "More" opens the Health app.
 * - Cardio load (tps.java / tpr.java): "N%" of the target (0x7f140dd8 "%1$d%%"; "- -" 0x7f140dd5 without one) and
 *   "+N" the load (0x7f140db1). Stock's card is the week's load against the account's weekly target; asteroid-sensorlogd
 *   keeps a daily load and a daily target (R5 E-09: TRIMP, 0.8-1.3 x the 28-day mean), so the card is the day's:
 *   N% = the load over the top of the target, the ring the same, at most full.
 * - Steps (zaq.java case 4): the day's steps (0x7f14038f "Steps"), the ring steps over the steps goal.
 * - Sleep (aahn.java, aahd SleepLogsAvailableWithGoal): the last night's score and its assessment (0x7f140cf9
 *   Excellent, 0x7f140cfb Good, 0x7f140cfa Fair, 0x7f140cfc Poor: Fitbit's 90 / 80 / 60 bands), the ring the time
 *   asleep over the sleep goal; without a night "- -" over "No data" (0x7f140d22; the card's column is too narrow
 *   for it as the number).
 * The data are asteroid-sensorlogd's (HealthMetricsLoader.cardioLoad(today), the steps log, SleepDataLoader.lastNight())
 * read only while the tile is on screen and again when health.db changes; nothing runs otherwise, previews read nothing.
 * Stock enables the tile behind a flag (syh.java:172); here it is in the add list, not a default tile.
 */
TileBase {
    id: tile
    objectName: "focusMetricsTile"
    //% "Focus Metrics"
    title: qsTrId("id-tile-focus-metrics") + localeManager.changesObserver
    backgroundTap: false
    chipText: qsTrId("id-tile-more") + localeManager.changesObserver
    chipColor: Theme.color.secondaryContainer
    chipContentColor: Theme.color.onSecondaryContainer
    onChipClicked: tile.open("")

    // ---- the data: read only while the tile is on screen ----
    property var cardio: ({})
    property var night: ({})
    property var metrics: null
    property var sleepLoader: null
    onLiveChanged: {
        if (live) {
            Qt.callLater(reload)
        } else {
            // nothing stays: no loader while the tile is off screen
            if (metrics) {
                metrics.destroy()
                metrics = null
            }
            if (sleepLoader) {
                sleepLoader.destroy()
                sleepLoader = null
            }
            cardio = ({})
            night = ({})
        }
    }
    Component.onCompleted: Qt.callLater(reload)
    function reload() {
        if (!live || preview)
            return
        if (!metrics)
            metrics = metricsComponent.createObject(tile, { "objectName": "focusMetricsLoader" })
        if (!sleepLoader)
            sleepLoader = sleepComponent.createObject(tile, { "objectName": "focusSleepLoader" })
        cardio = metrics.cardioLoad(new Date(tile.clock()))
        night = sleepLoader.lastNight()
    }
    Component {
        id: metricsComponent
        HealthMetricsLoader {
            onDataChanged: tile.reload()
        }
    }
    Component {
        id: sleepComponent
        SleepDataLoader {
            onDataChanged: tile.reload()
        }
    }
    HealthLog {
        id: stepsLog
        sensor: "stepCounter"
        buckets: 1
        active: tile.live && !tile.preview
    }
    ConfigurationValue {
        id: stepsGoal
        key: "/org/asteroidos/ux/steps-goal"
        defaultValue: 10000
    }
    // the Health app on a metric's page ("" its first page)
    ConfigurationValue {
        id: openRequest
        key: "/org/asteroidos/health/ui/open"
        defaultValue: ""
    }
    function open(page) {
        if (page !== "")
            openRequest.value = page + "@" + Date.now()
        desktop.launchByName("asteroid-health", tile)
    }

    readonly property var cardioCard: TC.focusCardio(cardio)
    readonly property int steps: stepsLog.hasData ? stepsLog.lastValue : 0
    readonly property var sleepCard: TC.focusSleep(night)
    readonly property string sleepWord: {
        switch (sleepCard.word) {
        //% "Excellent"
        case "excellent": return qsTrId("id-tile-sleep-excellent") + localeManager.changesObserver
        //% "Good"
        case "good": return qsTrId("id-tile-sleep-good") + localeManager.changesObserver
        //% "Fair"
        case "fair": return qsTrId("id-tile-sleep-fair") + localeManager.changesObserver
        //% "Poor"
        case "poor": return qsTrId("id-tile-sleep-poor") + localeManager.changesObserver
        }
        return ""
    }

    // ---- three cards in a row ----
    component MetricCard: Item {
        id: mc
        property string name: ""
        property string icon: ""
        property color ringColor: TC.GOAL_RING
        property real progress: 0
        property string value: ""
        property string second: ""
        property string page: ""
        width: (tile.body.width - 2 * Theme.dp(4)) / 3
        height: ring.height + Theme.dp(4) + valueLabel.height + secondLabel.height
        Accessible.role: Accessible.Button
        Accessible.name: name + ", " + value + (second !== "" ? ", " + second : "")

        CircularProgressIndicator {
            id: ring
            objectName: mc.objectName + "Ring"
            width: Theme.dp(40)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter
            displayOn: tile.awake
            strokeWidth: Theme.dp(4)
            color: mc.ringColor
            trackColor: Qt.rgba(1, 1, 1, 0.14)
            progress: Math.max(0, Math.min(1, mc.progress))
            Icon {
                anchors.centerIn: parent
                name: mc.icon
                color: mc.ringColor
                width: Theme.dp(20)
                height: width
            }
        }
        Label {
            id: valueLabel
            objectName: mc.objectName + "Value"
            anchors.top: ring.bottom
            anchors.topMargin: Theme.dp(4)
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: mc.value
            font.pixelSize: Theme.dp(16)
            font.weight: Font.Medium
            font.features: Theme.tabularNumerals
            color: Theme.color.onSurface
            maximumLineCount: 1
            elide: Text.ElideRight
        }
        Label {
            id: secondLabel
            objectName: mc.objectName + "Second"
            anchors.top: valueLabel.bottom
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: mc.second
            font.pixelSize: Theme.dp(12)
            color: TC.LAST_DAY
            maximumLineCount: 1
            elide: Text.ElideRight
        }
        MouseArea {
            anchors.fill: parent
            enabled: !tile.preview
            onClicked: tile.open(mc.page)
        }
    }

    Row {
        id: cards
        objectName: "focusCards"
        anchors.centerIn: parent
        spacing: Theme.dp(4)
        MetricCard {
            objectName: "focusCardio"
            name: qsTrId("id-comp-cardio-load")
            icon: "ms-monitor_heart"
            ringColor: TC.CARDIO
            progress: tile.cardioCard.ratio
            value: tile.cardioCard.known ? qsTrId("id-tile-percent").replace("%1", String(tile.cardioCard.percent)) : "- -"
            //% "+%1"
            second: tile.cardioCard.known ? qsTrId("id-tile-plus").replace("%1", String(tile.cardioCard.load)) : ""
            page: "cardioload"
        }
        MetricCard {
            objectName: "focusSteps"
            name: qsTrId("id-tile-steps")
            icon: "eos-health-steps"
            ringColor: TC.STEPS
            progress: stepsGoal.value > 0 ? tile.steps / stepsGoal.value : 0
            value: Number(tile.steps).toLocaleString(Qt.locale(), "f", 0)
            second: qsTrId("id-tile-steps") + localeManager.changesObserver
            page: "steps"
        }
        MetricCard {
            objectName: "focusSleep"
            name: qsTrId("id-tile-sleep")
            icon: "ms-bedtime"
            ringColor: TC.SLEEP_RING
            progress: tile.sleepCard.ratio
            value: tile.sleepCard.valid && tile.sleepCard.score > 0 ? String(tile.sleepCard.score) : "- -"
            second: tile.sleepCard.valid ? tile.sleepWord : qsTrId("id-tile-no-data") + localeManager.changesObserver
            page: "sleep"
        }
    }
}
