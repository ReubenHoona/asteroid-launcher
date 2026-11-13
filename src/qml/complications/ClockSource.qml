/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Alarms
import "complications.js" as C

// The next alarm and the running countdown of timed's alarms (as
// asteroid-alarmclock and asteroid-timer set them, and the alarm and timer
// tiles read them), for the Alarm and Timer complications. Loaded only
// while a slot shows one of them; read when it becomes active and when the
// alarms change; no timer (the time left is worked out from the face's
// clock).
QtObject {
    id: source

    property bool active: false
    // the face's clock (the sources' now)
    property date now: new Date()
    // when the next enabled alarm rings (ms, 0 none) and when the running countdown ends (ms, 0 none)
    property real nextAlarmMs: 0
    property real countdownEnd: 0
    onActiveChanged: if (active) refresh()

    function plain(model) {
        var list = []
        for (var i = 0; i < model.rowCount(); i++) {
            var a = model.data(model.index(i, 0), 0x0100)
            if (a)
                list.push({ enabled: a.enabled, hour: a.hour, minute: a.minute, daysOfWeek: a.daysOfWeek,
                            triggerTime: a.triggerTime, countdown: a.countdown })
        }
        return list
    }
    function refresh() {
        nextAlarmMs = C.nextAlarm(plain(alarms), source.now)
        var end = 0
        var l = plain(countdowns)
        for (var i = 0; i < l.length; i++)
            if (l[i].enabled && l[i].triggerTime * 1000 > source.now.getTime() && (end === 0 || l[i].triggerTime * 1000 < end))
                end = l[i].triggerTime * 1000
        countdownEnd = end
    }

    property AlarmsModel alarms: AlarmsModel {
        onPopulatedChanged: if (source.active) source.refresh()
        onRowsInserted: if (source.active) source.refresh()
        onRowsRemoved: if (source.active) source.refresh()
        onDataChanged: if (source.active) source.refresh()
    }
    property AlarmsModel countdowns: AlarmsModel {
        onlyCountdown: true
        onPopulatedChanged: if (source.active) source.refresh()
        onRowsInserted: if (source.active) source.refresh()
        onRowsRemoved: if (source.active) source.refresh()
        onDataChanged: if (source.active) source.refresh()
    }
}
