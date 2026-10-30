/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.calendar

// Today's and tomorrow's events of the calendar database (the phone's
// calendar arrives in it through asteroid-btsyncd, as asteroid-calendar
// and the agenda tile read it), for the next event complication. The
// window follows the day when occurrence() is asked on another day.
QtObject {
    id: source

    property date day: new Date()
    readonly property int count: model.count
    signal updated()

    function occurrence(i) {
        var now = new Date()
        if (now.toDateString() !== day.toDateString())
            day = now
        var o = model.get(i, AgendaModel.OccurrenceObjectRole)
        var e = model.get(i, AgendaModel.EventObjectRole)
        if (!o || !e)
            return null
        return { start: o.startTime, end: o.endTime, title: e.displayLabel, allDay: e.allDay }
    }

    property AgendaModel model: AgendaModel {
        startDate: new Date(source.day.getFullYear(), source.day.getMonth(), source.day.getDate())
        endDate: new Date(source.day.getFullYear(), source.day.getMonth(), source.day.getDate() + 1)
        onUpdated: source.updated()
    }
}
