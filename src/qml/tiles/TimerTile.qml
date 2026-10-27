/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import Nemo.Configuration
import org.asteroid.controls

// Start a timer in one tap, as Wear OS's timer tile: four presets, or the
// running timer with its time left; the next alarm under it. The timer is
// a countdown alarm, the same as asteroid-timer sets, so the alarm
// presenter rings it and the Timer app shows it.
TileBase {
    id: tile
    //% "Timer"
    title: qsTrId("id-tile-timer") + localeManager.changesObserver
    accent: "#c58af9"

    ConfigurationValue { id: lastDuration; key: "/org/asteroidos/timer/last-timer-duration"; defaultValue: 300 }
    ConfigurationValue { id: use12H; key: "/org/asteroidos/settings/use-12h-format"; defaultValue: false }

    readonly property var presets: [60, 180, 300, 600]

    // the running countdown, if any
    property QtObject countdown: null
    property int remaining: 0

    AlarmsModel {
        id: countdowns
        onlyCountdown: true
        onPopulatedChanged: tile.findCountdown()
        onRowsInserted: tile.findCountdown()
        onRowsRemoved: tile.findCountdown()
    }

    AlarmsModel {
        id: alarms
        onPopulatedChanged: if (tile.live) tile.nextAlarm = tile.findNextAlarm()
    }

    onLiveChanged: if (live) { findCountdown(); nextAlarm = findNextAlarm() }

    function findCountdown() {
        var found = null
        for (var i = 0; i < countdowns.rowCount(); i++) {
            var a = countdowns.data(countdowns.index(i, 0), 0x0100)
            if (a && a.enabled && a.triggerTime > Date.now() / 1000)
                found = a
        }
        countdown = found
        updateLeft()
    }

    function updateLeft() {
        remaining = countdown ? Math.max(0, Math.round(countdown.triggerTime - Date.now() / 1000)) : 0
        if (countdown && remaining === 0)
            countdown = null
    }

    function start(seconds) {
        var a = countdowns.createAlarm()
        a.countdown = true
        a.second = seconds - 1
        a.title = new Date(seconds * 1000).toISOString().slice(11, 19)
        a.enabled = true
        a.save()
        lastDuration.value = seconds
        countdown = a
        remaining = seconds
        Haptics.confirm()
    }

    function cancel() {
        if (countdown)
            countdown.deleteAlarm()
        countdown = null
        remaining = 0
        Haptics.click()
    }

    function format(s) {
        var m = Math.floor(s / 60)
        var sec = s % 60
        if (m >= 60)
            return Math.floor(m / 60) + ":" + ("0" + (m % 60)).slice(-2) + ":" + ("0" + sec).slice(-2)
        return m + ":" + ("0" + sec).slice(-2)
    }

    // the time left changes every second: only while it is on screen
    Timer {
        interval: 1000
        repeat: true
        running: tile.live && tile.countdown !== null
        onTriggered: tile.updateLeft()
    }

    property string nextAlarm: ""
    function findNextAlarm() {
        var now = new Date()
        var best = null
        for (var i = 0; i < alarms.rowCount(); i++) {
            var a = alarms.data(alarms.index(i, 0), 0x0100)
            if (!a || !a.enabled || a.countdown)
                continue
            var t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), a.hour, a.minute)
            if (t <= now)
                t.setDate(t.getDate() + 1)
            if (a.triggerTime > now / 1000)
                t = new Date(a.triggerTime * 1000)
            if (best === null || t < best)
                best = t
        }
        if (best === null)
            return ""
        return best.toLocaleString(Qt.locale(), (best.getDate() !== now.getDate() ? "ddd " : "")
                                                + (use12H.value ? "h:mm AP" : "HH:mm"))
    }

    // presets
    Grid {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Math.round(tile.height * 0.02)
        visible: tile.countdown === null
        columns: 2
        spacing: Math.round(tile.width * 0.03)
        Repeater {
            model: tile.presets
            delegate: MouseArea {
                width: Math.round(tile.width * 0.25)
                height: width
                onClicked: tile.start(modelData)
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#2d2d30"
                    border.color: modelData === lastDuration.value ? tile.accent : "transparent"
                    border.width: Math.max(2, Math.round(tile.width * 0.006))
                    opacity: parent.pressed ? 0.7 : 1
                }
                Column {
                    anchors.centerIn: parent
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData / 60
                        font.pixelSize: Math.round(tile.height * 0.08)
                        font.styleName: "SemiCondensed Medium"
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        //% "min"
                        text: qsTrId("id-tile-min") + localeManager.changesObserver
                        opacity: 0.7
                        font.pixelSize: Math.round(tile.height * 0.04)
                    }
                }
            }
        }
    }

    // running
    Column {
        anchors.centerIn: parent
        visible: tile.countdown !== null
        spacing: Math.round(tile.height * 0.03)
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.format(tile.remaining)
            font.pixelSize: Math.round(tile.height * 0.15)
            font.styleName: "SemiCondensed Medium"
        }
        MouseArea {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(tile.width * 0.36)
            height: Math.round(tile.height * 0.14)
            onClicked: tile.cancel()
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "#2d2d30"
                opacity: parent.pressed ? 0.7 : 1
            }
            Label {
                anchors.centerIn: parent
                //% "Cancel"
                text: qsTrId("id-tile-cancel") + localeManager.changesObserver
                font.pixelSize: Math.round(tile.height * 0.055)
            }
        }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        visible: tile.nextAlarm !== ""
        opacity: 0.7
        font.pixelSize: Math.round(tile.height * 0.045)
        //% "Alarm %1"
        text: qsTrId("id-tile-alarm-at").arg(tile.nextAlarm) + localeManager.changesObserver
    }
}
