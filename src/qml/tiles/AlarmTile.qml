/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import org.asteroid.controls
import "clocklogic.js" as Clock

/*
 * The Alarm tile, as stock Clock's (hnv.java:44-210, hnw.java:37-56): the
 * title "Alarm" and three states.
 *  - next alarm: one filled card (primary / onPrimary, corner 26 dp, 14 dp
 *    side and 12 dp top and bottom padding) for the alarm that rings next:
 *    its repeat text ("One time", the days, "Every day") with the alarm icon
 *    at the end, 8 dp, and the time at 40 sp weight 500 in tabular figures
 *    with the locale's AM/PM after it. A tap on the card opens the alarm
 *    clock; the green edge button "+" (Add alarm) opens its new-alarm picker.
 *    No switches, no "In 2 h" line, no second alarm.
 *  - none on: one filled button "Set new alarm" (52 dp tall, stadium) that
 *    opens the picker; no edge button.
 *  - snoozed (the alarm presenter re-armed it with the snooze trigger): a
 *    data card "Snoozed", the time it rings again and "was 7:00 AM", and the
 *    edge button "Open".
 * Each card is its own click target (tiles-individual-32); a tap on empty
 * black does nothing.
 *
 * The alarms are timed's, as the alarm clock sets them. The tile reads them
 * when it comes on screen and when they change; there is no timer (the
 * snooze is read from the trigger time that timed holds).
 *
 * Opening a page of the alarm clock: the tile writes dconf
 * /org/asteroidos/alarmclock/open as "<route>@<ms>" before it starts the
 * program, the way Settings is asked for a page (ui/open). Routes: "new"
 * (the time picker of a new alarm) and "alarm:<id>" (an alarm's own page).
 * The alarm clock reads it when it starts or comes forward; without that
 * (an older alarm clock) it simply opens its list.
 */
TileBase {
    id: tile
    //% "Alarm"
    title: qsTrId("id-tile-alarm") + localeManager.changesObserver
    backgroundTap: false
    // the green edge button of the clock tiles (tiles-individual-03)
    chipColor: Theme.color.tertiary
    chipContentColor: Theme.color.onTertiary
    chipIcon: tile.mode === "next" ? "ios-add" : ""
    //% "Open"
    chipText: tile.mode === "snoozed" ? qsTrId("id-tile-open") + localeManager.changesObserver : ""
    onChipClicked: tile.mode === "snoozed" ? tile.openApp("alarm:" + tile.pick.alarm.id) : tile.openApp("new")

    ConfigurationValue { id: openRequest; key: "/org/asteroidos/alarmclock/open"; defaultValue: "" }

    AlarmsModel {
        id: alarms
        onPopulatedChanged: if (tile.live) tile.refresh()
        onRowsInserted: if (tile.live) tile.refresh()
        onRowsRemoved: if (tile.live) tile.refresh()
        onDataChanged: if (tile.live) tile.refresh()
        onModelReset: if (tile.live) tile.refresh()
    }

    // { state: "none" | "next" | "snoozed", alarm, at, until }
    property var pick: ({ state: "none" })
    readonly property string mode: pick.state
    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()

    function refresh() {
        var list = []
        for (var i = 0; i < alarms.rowCount(); i++) {
            var a = alarms.data(alarms.index(i, 0), 0x0100)
            if (a)
                list.push(a)
        }
        pick = Clock.pick(list, Date.now())
    }

    function openApp(route) {
        if (route !== "")
            openRequest.value = route + "@" + Date.now()
        desktop.launchByName("asteroid-alarmclock", null)
    }

    // the card's texts
    readonly property var nextParts: mode === "next" ? TimeFormat.timeParts(new Date(pick.at)) : ({ time: "", marker: "", markerFirst: false })
    readonly property var alarmParts: mode !== "none" ? TimeFormat.timeParts(Clock.clockDate(pick.alarm.hour, pick.alarm.minute)) : ({ time: "", marker: "", markerFirst: false })
    readonly property var snoozeParts: mode === "snoozed" ? TimeFormat.timeParts(new Date(pick.until)) : ({ time: "", marker: "", markerFirst: false })
    readonly property string repeat: mode === "next"
        // the language changed: the day names are read again (locale-formats-02)
        ? (localeManager.localeRevision, Clock.repeatText(pick.alarm.daysOfWeek, Qt.locale(),
                                                          //% "One time"
                                                          qsTrId("id-tile-alarm-one-time"), qsTrId("id-tile-alarm-every-day")))
          + localeManager.changesObserver
        : ""

    // the card geometry, px (hnv.java:178 14 dp, :200 8 dp; hoa.java 40 sp)
    readonly property real cardPadH: Theme.dp(14)
    readonly property real cardPadV: Theme.dp(12)
    readonly property real cardIcon: Theme.dp(24)
    readonly property real cardGap: Theme.dp(8)

    // ---- next alarm ------------------------------------------------------
    TileCard {
        id: nextCard
        objectName: "alarmCard"
        visible: tile.mode === "next"
        width: tile.body.width
        // the content, not more than the main slot holds
        height: Math.min(2 * tile.cardPadV + tile.cardIcon + tile.cardGap + timeRow.height, tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.dp(26)
        containerColor: Theme.color.primary
        contentColor: Theme.color.onPrimary
        accessibleName: tile.repeat + ", " + tile.nextParts.time + " " + tile.nextParts.marker
        onClicked: tile.openApp("")

        Label {
            id: repeatLabel
            objectName: "alarmRepeat"
            x: tile.cardPadH
            y: tile.cardPadV + (tile.cardIcon - height) / 2
            width: nextCard.width - 2 * tile.cardPadH - tile.cardIcon - tile.cardGap
            text: tile.repeat
            role: "bodyMedium"
            font.weight: Font.Medium
            color: Theme.color.onPrimary
            maximumLineCount: 1
        }
        Icon {
            id: alarmIcon
            objectName: "alarmIcon"
            x: nextCard.width - tile.cardPadH - width
            y: tile.cardPadV
            width: tile.cardIcon
            height: width
            name: "ios-alarm"
            color: Theme.color.onPrimary
        }
        TileTime {
            id: timeRow
            objectName: "alarmTimeRow"
            x: tile.cardPadH
            y: tile.cardPadV + tile.cardIcon + tile.cardGap
            parts: tile.nextParts
            color: Theme.color.onPrimary
        }
    }

    // ---- no alarm on -----------------------------------------------------
    TileCard {
        id: newCard
        objectName: "alarmNew"
        visible: tile.mode === "none"
        width: tile.body.width
        height: Theme.dp(52)
        anchors.verticalCenter: parent.verticalCenter
        containerColor: Theme.color.primary
        contentColor: Theme.color.onPrimary
        //% "Add alarm"
        accessibleName: qsTrId("id-tile-add-alarm") + localeManager.changesObserver
        onClicked: tile.openApp("new")

        Label {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(14)
            horizontalAlignment: Text.AlignHCenter
            //% "Set new alarm"
            text: qsTrId("id-tile-set-alarm") + localeManager.changesObserver
            role: "labelMedium"
            color: Theme.color.onPrimary
            maximumLineCount: 1
        }
    }

    // ---- snoozed ---------------------------------------------------------
    TileCard {
        id: snoozeCard
        objectName: "alarmSnoozed"
        visible: tile.mode === "snoozed"
        width: tile.body.width
        height: Math.min(Theme.dp(90), tile.body.height)
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.dp(26)
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        onClicked: tile.openApp("")

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * tile.cardPadH
            spacing: 0
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //% "Snoozed"
                text: qsTrId("id-tile-snoozed") + localeManager.changesObserver
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
            TileTime {
                id: snoozeTime
                objectName: "snoozeTime"
                anchors.horizontalCenter: parent.horizontalCenter
                parts: tile.snoozeParts
                color: Theme.color.onSurface
            }
            Label {
                objectName: "snoozeWas"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //% "was %1"
                text: qsTrId("id-tile-alarm-was").arg((tile.alarmParts.markerFirst ? tile.alarmParts.marker + " " + tile.alarmParts.time
                                                                                     : tile.alarmParts.time + " " + tile.alarmParts.marker).trim())
                      + localeManager.changesObserver
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
            }
        }
    }
}
