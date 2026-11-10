/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import org.asteroid.controls

/*
 * The watch's alarms (timed's, as asteroid-alarmclock sets them and the
 * alarm presenter rings them), as the stock Clock tile: the next alarm to
 * ring and the one after it, each with its days and a switch that turns it
 * on or off where it is; the time to the next ring. A tap or the chip opens
 * the alarm clock. Read when the tile shows and when the alarms change
 * (no timer: the time left is worked out when the tile comes on screen).
 */
TileBase {
    id: tile
    //% "Alarm"
    title: qsTrId("id-tile-alarm") + localeManager.changesObserver
    accent: "#fcad70"
    //% "Alarms"
    chipText: qsTrId("id-tile-alarms") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-alarmclock", null)
    onClicked: desktop.launchByName("asteroid-alarmclock", tile)

    ConfigurationValue { id: use12H; key: "/org/asteroidos/settings/use-12h-format"; defaultValue: false }

    AlarmsModel {
        id: alarms
        onPopulatedChanged: if (tile.live) tile.refresh()
        onRowsInserted: if (tile.live) tile.refresh()
        onRowsRemoved: if (tile.live) tile.refresh()
    }

    // the alarms shown, in the order they ring (kept while the tile shows,
    // so a row does not move under the finger that switched it)
    property var rows: []
    property string untilNext: ""
    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()

    // when an alarm rings next (ms), 0 when it is off
    function nextRing(a, now) {
        if (!a.enabled)
            return 0
        if (a.triggerTime * 1000 > now.getTime())
            return a.triggerTime * 1000
        var codes = "mtwTfsS"
        for (var d = 0; d < 8; d++) {
            var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, a.hour, a.minute)
            if (t <= now)
                continue
            if (a.daysOfWeek === "" || a.daysOfWeek.indexOf(codes[(t.getDay() + 6) % 7]) >= 0)
                return t.getTime()
        }
        return 0
    }

    function refresh() {
        var now = new Date()
        var list = []
        for (var i = 0; i < alarms.rowCount(); i++) {
            var a = alarms.data(alarms.index(i, 0), 0x0100)
            if (a && !a.countdown)
                list.push({ alarm: a, at: nextRing(a, now) })
        }
        // the ones on by their next ring, then the ones off by time of day
        list.sort(function (x, y) {
            if (x.at && y.at)
                return x.at - y.at
            if (x.at || y.at)
                return x.at ? -1 : 1
            return (x.alarm.hour * 60 + x.alarm.minute) - (y.alarm.hour * 60 + y.alarm.minute)
        })
        rows = list.slice(0, 2)
        untilNext = list.length > 0 && list[0].at ? inTime(list[0].at - now.getTime()) : ""
    }

    function inTime(ms) {
        var mins = Math.max(1, Math.round(ms / 60000))
        var h = Math.floor(mins / 60), m = mins % 60
        //% "In %1 d %2 h"
        if (h >= 24) return qsTrId("id-tile-alarm-in-dh").arg(Math.floor(h / 24)).arg(h % 24)
        //% "In %1 h %2 min"
        if (h > 0 && m > 0) return qsTrId("id-tile-alarm-in-hm").arg(h).arg(m)
        //% "In %1 h"
        if (h > 0) return qsTrId("id-tile-alarm-in-h").arg(h)
        //% "In %1 min"
        return qsTrId("id-tile-alarm-in-m").arg(m)
    }

    function timeText(a) {
        if (!use12H.value)
            return ("0" + a.hour).slice(-2) + ":" + ("0" + a.minute).slice(-2)
        var h = a.hour % 12
        return (h === 0 ? 12 : h) + ":" + ("0" + a.minute).slice(-2)
    }
    function amPm(a) {
        return use12H.value ? (a.hour < 12 ? "AM" : "PM") : ""
    }

    function daysText(a, at) {
        var d = a.daysOfWeek
        if (d === "") {
            if (!at)
                //% "Once"
                return qsTrId("id-tile-alarm-once")
            var now = new Date()
            var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
            //% "Today"
            return at < tomorrow.getTime() ? qsTrId("id-tile-today") : qsTrId("id-tile-tomorrow")
        }
        //% "Weekdays"
        if (d === "mtwTf") return qsTrId("id-tile-alarm-weekdays")
        //% "Weekends"
        if (d === "sS") return qsTrId("id-tile-alarm-weekends")
        //% "Every day"
        if (d === "mtwTfsS") return qsTrId("id-tile-alarm-every-day")
        var codes = "mtwTfsS"
        var names = []
        for (var i = 0; i < 7; i++)
            if (d.indexOf(codes[i]) >= 0)
                names.push(Qt.locale().dayName((i + 1) % 7, Locale.ShortFormat))
        return names.join(" ")
    }

    function toggle(a) {
        a.enabled = !a.enabled
        a.save()
        Haptics.click()
        // the time to the next ring changes; the rows stay where they are
        var now = new Date()
        var next = 0
        for (var i = 0; i < alarms.rowCount(); i++) {
            var b = alarms.data(alarms.index(i, 0), 0x0100)
            var t = b && !b.countdown ? nextRing(b, now) : 0
            if (t && (!next || t < next))
                next = t
        }
        untilNext = next ? inTime(next - now.getTime()) : ""
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Math.round(tile.height * 0.01)
        visible: tile.rows.length > 0
        spacing: Math.round(tile.height * 0.012)

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: tile.untilNext !== ""
            text: tile.untilNext + localeManager.changesObserver
            color: tile.accent
            font.pixelSize: Math.round(tile.height * 0.045)
        }

        Repeater {
            model: tile.rows
            delegate: Item {
                id: row
                readonly property QtObject alarm: modelData.alarm
                readonly property bool first: index === 0
                width: Math.round(tile.width * 0.66)
                height: Math.round(tile.height * (first ? 0.2 : 0.15))

                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Row {
                        spacing: Math.round(tile.width * 0.01)
                        Label {
                            id: timeLabel
                            text: tile.timeText(row.alarm)
                            opacity: row.alarm.enabled ? 1 : 0.55
                            font.pixelSize: Math.round(tile.height * (row.first ? 0.115 : 0.08))
                            font.styleName: "SemiCondensed Medium"
                        }
                        Label {
                            anchors.baseline: timeLabel.baseline
                            visible: text !== ""
                            text: tile.amPm(row.alarm)
                            opacity: row.alarm.enabled ? 0.8 : 0.45
                            font.pixelSize: Math.round(tile.height * 0.045)
                        }
                    }
                    Label {
                        width: row.width - toggleSwitch.width - Math.round(tile.width * 0.03)
                        elide: Text.ElideRight
                        text: tile.daysText(row.alarm, modelData.at) + localeManager.changesObserver
                        opacity: row.alarm.enabled ? 0.75 : 0.45
                        font.pixelSize: Math.round(tile.height * 0.042)
                    }
                }

                // the switch, as Wear OS's: a pill with its thumb
                MouseArea {
                    id: toggleSwitch
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(tile.width * 0.15)
                    height: Math.round(tile.height * 0.12)
                    onClicked: tile.toggle(row.alarm)
                    Rectangle {
                        id: track
                        anchors.centerIn: parent
                        width: parent.width
                        height: Math.round(tile.height * 0.075)
                        radius: height / 2
                        color: row.alarm.enabled ? tile.accent : Theme.color.surfaceContainerHigh
                        opacity: toggleSwitch.pressed ? 0.75 : 1
                        Rectangle {
                            width: parent.height * 0.75
                            height: width
                            radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: row.alarm.enabled ? parent.width - width - parent.height * 0.125 : parent.height * 0.125
                            color: row.alarm.enabled ? "#000000" : "#9aa0a6"
                        }
                    }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        visible: tile.rows.length === 0
        spacing: Math.round(tile.height * 0.02)
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "ios-alarm-outline"
            width: Math.round(tile.height * 0.12)
            height: width
            opacity: 0.7
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: 0.7
            font.pixelSize: Math.round(tile.height * 0.055)
            //% "No alarms"
            text: qsTrId("id-tile-no-alarms") + localeManager.changesObserver
        }
    }
}
