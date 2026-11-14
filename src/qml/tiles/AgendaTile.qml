/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.nemomobile.calendar
import "tilecontent.js" as TC

/*
 * Next event, as the Google Calendar tile (tiles-individual-18, weather-calendar-36; CalendarTileService.java
 * :112, :437-468, :753-790, :1810-1906; mkp.java:720-746): one event at a time, the first that has not ended (the
 * phone's calendar arrives in the "Phone" notebook; a week ahead is looked at). The title says "Now" for a timed
 * event in progress, else "Today", "Tomorrow" or the date; the main slot is one card (surfaceContainer, corner 52 px,
 * 24 px above and below the text and 28 px at the sides, the width of the slot) with the title in two lines at most
 * and under it the time range ("8:30 - 9:30 AM", the 12 or 24 hour format of Settings) or "All day"; a tap on the card
 * opens the Calendar app on that event. The edge button "Calendar" opens the app. Without an event: the title is
 * "Today • Tue 10", a small picture and "Your day is clear".
 *
 * Battery: the tile looks again when it comes on screen, when the calendar changes while it shows, and at the one moment
 * the shown event starts or ends: a single-shot timer, only while the tile is on screen with the display on.
 */
TileBase {
    id: tile
    title: tile.titleText + localeManager.changesObserver
    backgroundTap: false
    accent: Theme.color.primary
    //% "Calendar"
    chipText: qsTrId("id-tile-calendar") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-calendar", null)

    ConfigurationValue { id: calendarRequest; key: "/org/asteroidos/calendar/ui/open"; defaultValue: "" }

    // the window of the model: from the start of today a week ahead; moved on when the tile shows on another day
    property date windowDay: new Date()
    property var shown: null
    // the time the shown event was chosen for (the title and the timer follow it)
    property real stamp: Date.now()

    AgendaModel {
        id: agenda
        objectName: "agenda"
        startDate: new Date(tile.windowDay.getFullYear(), tile.windowDay.getMonth(), tile.windowDay.getDate(), 0, 0, 0)
        endDate: new Date(tile.windowDay.getFullYear(), tile.windowDay.getMonth(), tile.windowDay.getDate() + 7, 23, 59, 59)
        onUpdated: if (tile.live) tile.refresh()
    }

    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()

    function refresh() {
        var now = new Date()
        if (now.toDateString() !== windowDay.toDateString())
            windowDay = now
        stamp = now.getTime()
        var list = []
        for (var i = 0; i < agenda.count; i++) {
            var o = agenda.get(i, AgendaModel.OccurrenceObjectRole)
            var e = agenda.get(i, AgendaModel.EventObjectRole)
            if (o && e)
                list.push({ start: o.startTime.getTime(), end: o.endTime.getTime(), title: e.displayLabel, allDay: e.allDay })
        }
        shown = TC.pickEvent(list, stamp)
    }

    readonly property string when: shown ? TC.eventWhen(shown, stamp) : "none"
    readonly property string titleText: {
        var d = new Date(stamp)
        switch (when) {
        case "now":
            //% "Now"
            return qsTrId("id-tile-now")
        case "today":
            //% "Today"
            return qsTrId("id-tile-today")
        case "tomorrow":
            //% "Tomorrow"
            return qsTrId("id-tile-tomorrow")
        case "date":
            return TimeFormat.date(new Date(shown.start), "EEEMMMd")
        }
        // nothing to show: 'Today • Tue 10'
        //% "Today • %1 %2"
        return qsTrId("id-tile-today-date").replace("%1", Qt.locale().toString(d, "ddd")).replace("%2", d.getDate())
    }
    readonly property string rangeText: !shown ? ""
        //% "All day"
        : shown.allDay ? qsTrId("id-tile-all-day")
                       : TimeFormat.range(new Date(shown.start), new Date(shown.end))

    // the moment to look again (the event starts, or ends), a single shot while on screen with the display on
    Timer {
        id: changeTimer
        objectName: "agendaChange"
        readonly property real at: TC.nextChangeMs(tile.shown, tile.stamp)
        interval: Math.max(1000, Math.min(2147483000, at - Date.now() + 500))
        repeat: false
        running: tile.awake && !tile.preview && at > 0
        onTriggered: tile.refresh()
    }

    TileCard {
        id: card
        objectName: "agendaCard"
        visible: tile.shown !== null
        width: tile.body.width
        height: Math.min(tile.body.height, column.implicitHeight + 2 * Theme.dp(12))
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.dp(26)
        containerColor: Theme.color.surfaceContainer
        contentColor: Theme.color.onSurface
        preview: tile.preview
        accessibleName: (tile.shown ? tile.shown.title : "") + ", " + tile.rangeText
        onClicked: {
            // the Calendar app on that event (the same request the next event complication writes)
            if (tile.shown)
                calendarRequest.value = "event:" + tile.shown.start + "@" + Date.now()
            desktop.launchByName("asteroid-calendar", card)
        }

        Column {
            id: column
            x: Theme.dp(14)
            y: Theme.dp(12)
            width: parent.width - 2 * Theme.dp(14)
            Label {
                id: eventTitle
                objectName: "agendaEvent"
                width: parent.width
                text: tile.shown ? tile.shown.title : ""
                role: "labelMedium"
                font.weight: Font.Medium
                color: Theme.color.onSurface
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                id: eventRange
                objectName: "agendaRange"
                width: parent.width
                text: tile.rangeText
                role: "bodyMedium"
                color: Theme.color.onSurfaceVariant
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }

    // a day with nothing left: a small picture, "Your day is clear"
    Column {
        id: clear
        objectName: "agendaClear"
        visible: tile.shown === null
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.dp(4)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "ms-calendar_month"
            color: Theme.color.onSurfaceVariant
            width: Theme.dp(28)
            height: width
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            //% "Your day is clear"
            text: qsTrId("id-tile-day-clear") + localeManager.changesObserver
            role: "titleSmall"
            color: Theme.color.onSurface
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
    }
}
