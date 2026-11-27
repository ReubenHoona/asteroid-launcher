/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.sensorlogd
import "complications.js" as C

/*
 * The Health numbers of the complications Calories, Floors, Active Zone Minutes and Exercise days (M4 WO-10), as the
 * Health app has them: today's energy burned, floors and Active Zone Minutes of asteroid-sensorlogd's day summary
 * (HealthMetricsLoader.summary: the day files and heartrate.db) and the days of this week with a workout
 * (WorkoutLoader.workouts: health.db). Made by ComplicationSources only while a slot shows one of them.
 *
 * Power, as the other sources: read while `active` (the face on the awake screen) and only what a slot shows
 * (wantsDay: the three of the day summary; wantsWeek: Exercise days): when a slot comes to show it, then only when
 * the data changed (the steps log was written, which comes with the sensor hub's batch or with the live count while
 * the screen is on; health.db was written) or the day did, at most once a minute: a change waits for the face's
 * minute (tick()), a screen on reads only what changed while it was off. No timer of its own; while inactive the
 * numbers stay as they were.
 */
Item {
    id: src
    visible: false

    property bool active: false
    // the face's clock: which day and week
    property date now: new Date()
    property bool wantsDay: false
    property bool wantsWeek: false
    // R5 E-09: today's cardio load and its target (HealthMetricsLoader.cardioLoad)
    property bool wantsCardio: false

    // the numbers (-1: not read yet)
    property int kcal: -1
    property int floors: -1
    property int azm: -1
    property int exerciseDays: -1
    property int cardio: -1
    property int cardioHigh: -1  // the top of the target; -1: none yet
    readonly property int reads: _reads

    property int _reads: 0
    property real _readAt: -1
    property string _readDay: ""
    property bool _dirty: false

    function valueOf(kind) {
        return kind === "calories" ? kcal : kind === "floors" ? floors : kind === "azm" ? azm : kind === "exercisedays" ? exerciseDays
             : kind === "cardioload" ? cardio : -1
    }

    function refresh() {
        _dirty = false
        _readAt = now.getTime()
        _readDay = C.dayKey(now)
        _reads++
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        if (wantsDay) {
            var s = metrics.summary(today)
            kcal = Math.max(0, Math.round(Number(s.energyKcal) || 0))
            floors = Math.max(0, Math.round(Number(s.floors) || 0))
            azm = Math.max(0, Math.round(Number(s.azm) || 0))
        }
        if (wantsWeek)
            exerciseDays = C.exerciseDays(workouts.workouts(new Date(C.weekStartMs(now.getTime())), today))
        if (wantsCardio) {
            var c = metrics.cardioLoad(today)
            cardio = Math.max(0, Math.round(Number(c.load) || 0))
            cardioHigh = c.hasTarget === true ? Number(c.high) : -1
        }
    }
    // something to read: never read, a new day, or the data changed and the last read is a minute old
    function due() {
        if (_readAt < 0 || C.dayKey(now) !== _readDay)
            return true
        var age = now.getTime() - _readAt
        return _dirty && (age >= 60000 || age < 0)
    }
    // the data changed: read again now if the last read is a minute old, else when the face's clock is
    function changed() {
        _dirty = true
        tick()
    }
    // a change, the face's clock (a new minute, a new day): looked at once the bindings of the moment have settled
    // (the slot's clock, wants and active come one by one)
    function tick() {
        Qt.callLater(src.check)
    }
    function check() {
        if (active && due())
            refresh()
    }
    onNowChanged: tick()
    onActiveChanged: tick()
    onWantsDayChanged: if (wantsDay) { _readAt = -1; tick() }
    onWantsWeekChanged: if (wantsWeek) { _readAt = -1; tick() }
    onWantsCardioChanged: if (wantsCardio) { _readAt = -1; tick() }
    Component.onCompleted: tick()

    HealthMetricsLoader {
        id: metrics
        onDataChanged: if (src.wantsDay || src.wantsCardio) src.changed()
    }
    WorkoutLoader {
        id: workouts
        onDataChanged: if (src.wantsWeek) src.changed()
    }
}
