/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.nemomobile.calendar

// The next events of today and tomorrow (the phone's calendar arrives in
// the "Phone" notebook), as Wear OS's agenda tile
TileBase {
    id: tile
    //% "Agenda"
    title: qsTrId("id-tile-agenda") + localeManager.changesObserver
    accent: Theme.color.primary
    //% "Calendar"
    chipText: qsTrId("id-tile-calendar") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-calendar", null)
    onClicked: desktop.launchByName("asteroid-calendar", tile)

    ConfigurationValue { id: use12H; key: "/org/asteroidos/settings/use-12h-format"; defaultValue: false }

    // the day the window starts on; moved on when the tile shows on another day
    property date day: new Date()
    onLiveChanged: {
        if (!live)
            return
        var now = new Date()
        if (now.toDateString() !== day.toDateString())
            day = now
        upcoming = nextEvents()
    }

    AgendaModel {
        id: agenda
        startDate: new Date(tile.day.getFullYear(), tile.day.getMonth(), tile.day.getDate(), 0, 0, 0)
        endDate: new Date(tile.day.getFullYear(), tile.day.getMonth(), tile.day.getDate() + 1, 23, 59, 59)
        onUpdated: if (tile.live) tile.upcoming = tile.nextEvents()
    }

    // the first two events that have not ended yet; how many more there are
    // (stock's calendar tile: two at a time, then "More")
    property var upcoming: []
    property int more: 0
    function nextEvents() {
        var now = new Date()
        var list = []
        var rest = 0
        for (var i = 0; i < agenda.count; i++) {
            var o = agenda.get(i, AgendaModel.OccurrenceObjectRole)
            var e = agenda.get(i, AgendaModel.EventObjectRole)
            if (!o || !e || o.endTime < now)
                continue
            if (list.length < 2)
                list.push({ start: o.startTime, end: o.endTime, title: e.displayLabel, allDay: e.allDay })
            else
                rest++
        }
        more = rest
        return list
    }

    function when(ev) {
        var today = new Date()
        var tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)
        var s = ev.start
        //% "Tomorrow"
        var dayPart = s >= tomorrow ? qsTrId("id-tile-tomorrow") + " " : ""
        //% "All day"
        if (ev.allDay) return dayPart + qsTrId("id-tile-all-day")
        return dayPart + s.toLocaleString(Qt.locale(), use12H.value ? "h:mm AP" : "HH:mm")
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Math.round(tile.height * 0.025)
        visible: tile.upcoming.length > 0

        Repeater {
            model: tile.upcoming
            delegate: Column {
                width: parent.width
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.when(modelData) + localeManager.changesObserver
                    color: tile.accent
                    opacity: 0.9
                    font.pixelSize: Math.round(tile.height * 0.05)
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.title
                    elide: Text.ElideRight
                    maximumLineCount: index === 0 && tile.upcoming.length === 1 ? 2 : 1
                    wrapMode: Text.Wrap
                    font.pixelSize: Math.round(tile.height * 0.065)
                    font.styleName: "SemiCondensed Medium"
                }
            }
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tile.more > 0
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.045)
            //% "+%1 more"
            text: qsTrId("id-tile-more-events").arg(tile.more) + localeManager.changesObserver
        }
    }

    Column {
        anchors.centerIn: parent
        visible: tile.upcoming.length === 0
        spacing: Math.round(tile.height * 0.02)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "ios-calendar-outline"
            width: Math.round(tile.height * 0.12)
            height: width
            opacity: 0.7
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.055)
            //% "No more events"
            text: qsTrId("id-tile-no-events") + localeManager.changesObserver
        }
    }
}
