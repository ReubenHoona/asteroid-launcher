/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import "tilecontent.js" as TC
import "exercisetypes.js" as Types

/*
 * Last activity, as the Fitbit tile (tiles-individual-24, health-fitness E60; TileLastActivityService: zpj.java:451-505,
 * acbe.java:1567-1650 and 1741-1790, adho.java:868-930, tile_last_activity_preview.xml): the title is the exercise of
 * the newest workout that ended ("Run"), one graphic data card (#29303D, a stadium up to 88 dp tall) with the day it
 * began ("Today", "Yesterday", the weekday's name in this week, else the date), its main number large and the
 * unit under it ("3.60", "km"), and the edge button "Start" (#A8C7FA) that starts that exercise again.
 * No workout yet: the title "Exercise", "Track an exercise to see your achievements!" (0x7f140db8) in the card, and
 * "Start" opens the Exercise app. While a workout runs "Start" opens the app on it (stock: the workout's
 * NoSwipeActivity). A tap on the card opens the Exercise app. In the add list, not a default tile (as stock).
 *
 * The workout is asteroid-sensorlogd's (health.db, WorkoutLoader.last(): the newest one that ended). The main number is
 * its distance when it has one (two decimals, km or mi by the locale's measurement system, as the Exercise app's
 * summary), else its active time (m:ss, h:mm:ss): stock picks a stat per exercise type in code not traced (ulu.A),
 * this rule is ours. The week of "the weekday's name" starts on Monday, as sensorlogd's Active Zone Minutes week
 * (stock: the account's first day of the week).
 * Battery (M1): the reader (LastActivitySource.qml) is made, and health.db read, only while the tile is on screen,
 * and again when sensorlogd writes health.db (a workout ended); nothing runs otherwise, previews read nothing.
 */
TileBase {
    id: tile
    objectName: "lastActivityTile"
    title: (sum.valid ? tile.exerciseName
                        //% "Exercise"
                      : qsTrId("id-tile-exercise")) + localeManager.changesObserver
    backgroundTap: false
    //% "Start"
    chipText: qsTrId("id-tile-start") + localeManager.changesObserver
    chipColor: TC.LAST_CHIP
    chipContentColor: TC.LAST_CHIP_TEXT
    onChipClicked: start()

    ConfigurationValue { id: startRequest; key: "/org/asteroidos/exercise/start-request"; defaultValue: "" }

    // the newest workout that ended ({} for none) and what the tile shows of it
    property var workout: ({})
    readonly property bool imperial: Qt.locale().measurementSystem !== Locale.MetricSystem
    readonly property var sum: TC.lastActivity(workout, tile.clock(), imperial)
    readonly property var type: sum.valid ? Types.find(sum.type) : null
    readonly property string exerciseName: type ? type.name : sum.type
    readonly property string dayText: dayWord(sum, workout) + localeManager.changesObserver
    function dayWord(s, w) {
        if (!s.valid)
            return ""
        var at = new Date(Number(w.startMs))
        switch (s.day) {
        case "today":
            //% "Today"
            return qsTrId("id-comp-today")
        case "yesterday":
            //% "Yesterday"
            return qsTrId("id-tile-yesterday")
        case "weekday":
            return at.toLocaleString(Qt.locale(), "dddd")
        }
        // stock: the date in the medium style (FormatStyle.MEDIUM)
        return at.toLocaleString(Qt.locale(), "d MMM yyyy")
    }
    readonly property string valueText: !sum.valid ? "" : sum.distance ? Number(sum.value).toLocaleString(Qt.locale(), "f", 2)
                                                                       : sum.clock

    // the reader: LastActivitySource.qml (sensorlogd's WorkoutLoader), made when the tile is first on screen and
    // let go when it leaves; a test sets its own component
    property Component sourceComponent: null
    property var dataLoader: null
    property Component _component: null

    // a workout running: the Exercise app's ongoing activity (as Quick start)
    property var ongoing: null
    readonly property bool running: {
        var list = ongoing && ongoing.entries ? ongoing.entries : []
        for (var i = 0; i < list.length; i++)
            if (list[i] && list[i].app === "asteroid-exercise")
                return true
        return false
    }

    onLiveChanged: {
        if (live) {
            // after the editor has said it is a picture (a preview reads nothing)
            Qt.callLater(reload)
        } else {
            // nothing stays: no loader while the tile is off screen
            if (dataLoader) {
                dataLoader.destroy()
                dataLoader = null
            }
            workout = ({})
        }
    }
    Component.onCompleted: {
        ongoing = typeof ongoingRegistry !== "undefined" ? ongoingRegistry : null
        Qt.callLater(reload)
    }
    function reload() {
        if (!live || preview)
            return
        if (!dataLoader) {
            var c = sourceComponent
            if (!c) {
                if (!_component)
                    _component = Qt.createComponent(Qt.resolvedUrl("LastActivitySource.qml"))
                c = _component
            }
            if (c.status !== Component.Ready) {
                console.warn("Last activity: no workout reader:", c.errorString())
                return
            }
            dataLoader = c.createObject(tile, { "objectName": "lastActivityLoader" })
            if (!dataLoader)
                return
            dataLoader.dataChanged.connect(tile.reload)
        }
        var w = dataLoader.last()
        workout = w ? w : ({})
    }

    // stock: the exercise of the last workout again (its type, as Quick start's buttons), else the app's start
    // screen; a workout on: the app, on it
    function start() {
        if (sum.valid && !running && type)
            startRequest.value = TC.exerciseRequest(sum.type, tile.clock())
        desktop.launchByName("asteroid-exercise", null)
    }

    TileCard {
        id: card
        objectName: "lastActivityCard"
        width: tile.body.width
        height: Math.min(Theme.dp(88), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: TC.CARD
        contentColor: Theme.color.onSurface
        radius: height / 2
        preview: tile.preview
        accessibleName: tile.title + ", " + (tile.sum.valid ? tile.dayText + ", " + tile.valueText + " " + tile.sum.unit
                                                            : empty.text)
        onClicked: desktop.launchByName("asteroid-exercise", card)

        Column {
            id: info
            objectName: "lastActivityData"
            visible: tile.sum.valid
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(20)
            spacing: 0
            Label {
                id: day
                objectName: "lastActivityDay"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.dayText
                role: "labelMedium"
                color: TC.LAST_DAY
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Label {
                id: value
                objectName: "lastActivityValue"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.valueText
                font.pixelSize: Theme.sp(30)
                font.weight: Font.Medium
                font.features: Theme.tabularNumerals
                color: "#FFFFFF"
                maximumLineCount: 1
            }
            Label {
                id: unit
                objectName: "lastActivityUnit"
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: tile.sum.unit
                role: "titleMedium"
                color: TC.LAST_UNIT
                maximumLineCount: 1
            }
        }

        Label {
            id: empty
            objectName: "lastActivityEmpty"
            visible: !tile.sum.valid
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(18)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            //% "Track an exercise to see your achievements!"
            text: qsTrId("id-tile-last-activity-empty") + localeManager.changesObserver
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
        }
    }
}
