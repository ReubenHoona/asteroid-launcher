/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import org.asteroid.controls
import "clocklogic.js" as Clock

/*
 * The Alarm tile, as stock Clock's (hnv.java:44-210, hnw.java:37-56) in the
 * look of the Wear OS 6 emulator's Next Alarm tile (S14, S14-d): no title,
 * no app icon at rest (an expressive tile: the icon shows only while the
 * pager moves), three states.
 *  - next alarm: the time to go at the top ('22h 58m', labelSmall, white:
 *    S14-d's text is #FBFBFB), a 134 x 50 dp stadium from 69 dp with a
 *    horizontal gradient #FFF76D -> #FFEBAE holding the time of the alarm
 *    that rings next (displaySmall, tabular, #202124, the locale's AM/PM
 *    after it in labelSmall: S14-d's digits are 36 px tall), and under it
 *    the day it rings ('Today', 'Tomorrow', the day's name; labelSmall,
 *    yellow #FFFD66 as S14-d). A tap on the stadium opens the alarm clock.
 *    No '+' (the alarm clock still adds alarms), no switches, no second
 *    alarm; the repeat text is the screen reader's.
 *  - none on: 'No alarms' (labelMedium, #BDC1C6, capitals from 79 px) and
 *    a 134 x 60 dp #FDE293 stadium from 66 dp, 'Set new' (labelMedium,
 *    #202124), which opens the picker (S14).
 *  - snoozed (the alarm presenter re-armed it with the snooze trigger): a
 *    data card "Snoozed", the time it rings again and "was 7:00 AM" in the
 *    yellow of the stadium, and the pill "Open" (not captured: CP3A's card
 *    in the new colours).
 * Each card is its own click target (tiles-individual-32); a tap on empty
 * black does nothing. N61-28
 *
 * The alarms are timed's, as the alarm clock sets them. The tile reads them
 * when it comes on screen and when they change (the snooze is read from the
 * trigger time that timed holds). Battery: the time to go is re-drawn by ONE
 * single shot at the next whole minute, only while the tile is on screen and
 * awake (TileBase.awake) and an alarm is next; nothing otherwise.
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
    backgroundTap: false
    expressive: true
    // the pill of the snoozed card only
    pillColor: tile.yellow
    pillContentColor: tile.ink
    //% "Open"
    pillText: tile.mode === "snoozed" ? qsTrId("id-tile-open") + localeManager.changesObserver : ""
    onPillClicked: tile.openApp("alarm:" + tile.pick.alarm.id)

    // the Clock tiles' colours (S14, S14-d)
    readonly property color yellow: "#FDE293"
    readonly property color ink: "#202124"
    readonly property color grey: "#BDC1C6"
    readonly property color dayYellow: "#FFFD66"
    readonly property color gradientFrom: "#FFF76D"
    readonly property color gradientTo: "#FFEBAE"

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
    // the time the time to go is counted from (set by refresh() and the minute tick)
    property real nowMs: Date.now()
    onLiveChanged: if (live) refresh()
    onAwakeChanged: if (awake) nowMs = Date.now()
    Component.onCompleted: refresh()

    function refresh() {
        var list = []
        for (var i = 0; i < alarms.rowCount(); i++) {
            var a = alarms.data(alarms.index(i, 0), 0x0100)
            if (a)
                list.push(a)
        }
        nowMs = Date.now()
        pick = Clock.pick(list, nowMs)
    }

    readonly property alias minuteTick: minuteTimer
    // one single shot for the next whole minute of the time to go
    Timer {
        id: minuteTimer
        repeat: false
        interval: Math.min(Clock.nextMinuteMs(tile.pick.at - tile.nowMs), 60001)
        running: tile.awake && tile.mode === "next"
        onTriggered: {
            tile.nowMs = Date.now()
            if (tile.awake && tile.mode === "next")
                minuteTimer.restart()
        }
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
                                                          qsTrId("id-tile-alarm-one-time"),
                                                          //% "Every day"
                                                          qsTrId("id-tile-alarm-every-day")))
          + localeManager.changesObserver
        : ""

    // the Next Alarm texts: the time to go ('22h 58m', a zero part left out) and the day it rings
    readonly property string untilText: {
        if (mode !== "next")
            return ""
        var p = Clock.untilParts(pick.at - nowMs)
        var s = p.d > 0 ? (p.h > 0
                           //% "%1d %2h"
                           ? qsTrId("id-tile-alarm-togo-dh").arg(p.d).arg(p.h)
                           //% "%1d"
                           : qsTrId("id-tile-alarm-togo-d").arg(p.d))
              : p.h > 0 ? (p.m > 0
                           //% "%1h %2m"
                           ? qsTrId("id-tile-alarm-togo-hm").arg(p.h).arg(p.m)
                           //% "%1h"
                           : qsTrId("id-tile-alarm-togo-h").arg(p.h))
              //% "%1m"
              : qsTrId("id-tile-alarm-togo-m").arg(p.m)
        return s + localeManager.changesObserver
    }
    readonly property string dayText: {
        if (mode !== "next")
            return ""
        var kind = Clock.dayKind(pick.at, nowMs)
        var s = kind === "today"
                //% "Today"
                ? qsTrId("id-tile-today")
                : kind === "tomorrow"
                  //% "Tomorrow"
                  ? qsTrId("id-tile-tomorrow")
                  // the language changed: the day names are read again (locale-formats-02)
                  : (localeManager.localeRevision, Qt.locale().dayName(new Date(pick.at).getDay(), Locale.LongFormat))
        return s + localeManager.changesObserver
    }

    // the snoozed card's side padding (hnv.java:178 14 dp)
    readonly property real cardPadH: Theme.dp(14)

    // ---- next alarm (S14-d) ------------------------------------------------
    // the time to go, its capitals from 72 px
    Label {
        id: untilLabel
        objectName: "alarmUntil"
        visible: tile.mode === "next"
        x: (tile.width - width) / 2 - tile.body.x
        y: Theme.dp(36) - (baselineOffset + untilCap.tightBoundingRect.y) - tile.body.y
        width: tile.width * 0.6
        horizontalAlignment: Text.AlignHCenter
        text: tile.untilText
        role: "labelSmall"
        color: "#FFFFFF"
        maximumLineCount: 1
    }
    TextMetrics { id: untilCap; font: untilLabel.font; text: "H" }

    // the stadium with the time, 268 x 100 px from 138 px
    TileCard {
        id: nextCard
        objectName: "alarmCard"
        visible: tile.mode === "next"
        width: Theme.dp(134)
        height: Theme.dp(50)
        x: (tile.width - width) / 2 - tile.body.x
        y: Theme.dp(69) - tile.body.y
        containerColor: tile.gradientFrom
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: tile.gradientFrom }
            GradientStop { position: 1; color: tile.gradientTo }
        }
        contentColor: tile.ink
        accessibleName: tile.repeat + ", " + tile.nextParts.time + " " + tile.nextParts.marker + ", " + tile.dayText
        onClicked: tile.openApp("")

        TileTime {
            id: timeRow
            objectName: "alarmTimeRow"
            anchors.centerIn: parent
            parts: tile.nextParts
            color: tile.ink
            timeRole: "displaySmall"
            markerRole: "labelSmall"
            markerGap: 0
        }
    }

    // the day it rings, its capitals from 290 px
    Label {
        id: dayLabel
        objectName: "alarmDay"
        visible: tile.mode === "next"
        x: (tile.width - width) / 2 - tile.body.x
        y: Theme.dp(145) - (baselineOffset + dayCap.tightBoundingRect.y) - tile.body.y
        width: tile.width * 0.6
        horizontalAlignment: Text.AlignHCenter
        text: tile.dayText
        role: "labelSmall"
        color: tile.dayYellow
        maximumLineCount: 1
    }
    TextMetrics { id: dayCap; font: dayLabel.font; text: "H" }

    // ---- no alarm on (S14) -------------------------------------------------
    // 'No alarms', its capitals from 79 px
    Label {
        id: noneLabel
        objectName: "alarmNone"
        visible: tile.mode === "none"
        x: (tile.width - width) / 2 - tile.body.x
        y: Theme.dp(39.5) - (baselineOffset + noneCap.tightBoundingRect.y) - tile.body.y
        width: tile.width * 0.7
        horizontalAlignment: Text.AlignHCenter
        //% "No alarms"
        text: qsTrId("id-tile-no-alarms") + localeManager.changesObserver
        role: "labelMedium"
        color: tile.grey
        maximumLineCount: 1
    }
    TextMetrics { id: noneCap; font: noneLabel.font; text: "H" }

    // the yellow stadium 268 x 120 px from 132 px
    TileCard {
        id: newCard
        objectName: "alarmNew"
        visible: tile.mode === "none"
        width: Theme.dp(134)
        height: Theme.dp(60)
        x: (tile.width - width) / 2 - tile.body.x
        y: Theme.dp(66) - tile.body.y
        containerColor: tile.yellow
        contentColor: tile.ink
        //% "Add alarm"
        accessibleName: qsTrId("id-tile-add-alarm") + localeManager.changesObserver
        onClicked: tile.openApp("new")

        Label {
            objectName: "alarmNewText"
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.dp(14)
            horizontalAlignment: Text.AlignHCenter
            //% "Set new"
            text: qsTrId("id-tile-set-new") + localeManager.changesObserver
            role: "labelMedium"
            color: tile.ink
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
        containerColor: tile.yellow
        contentColor: tile.ink
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
                color: tile.ink
                maximumLineCount: 1
            }
            TileTime {
                id: snoozeTime
                objectName: "snoozeTime"
                anchors.horizontalCenter: parent.horizontalCenter
                parts: tile.snoozeParts
                color: tile.ink
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
                color: tile.ink
                maximumLineCount: 1
            }
        }
    }
}
