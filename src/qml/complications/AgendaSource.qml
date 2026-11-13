/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.calendar

// The events of the next 24 hours of the calendar database (the phone's
// calendar arrives in it through asteroid-btsyncd, as asteroid-calendar
// and the agenda tile read it), for the next event complication: today
// and tomorrow whole, from which the complication takes the first that has
// not ended and starts within 24 h of now (complications.js pickNext). The
// window follows the face's clock (now) to the next day.
QtObject {
    id: source

    // the face's clock; the window is the day of it (moved only when the day changes)
    property date now: new Date()
    property date day: new Date()
    onNowChanged: {
        if (now.toDateString() !== day.toDateString())
            day = now
    }
    readonly property int count: model.count
    signal updated()

    function occurrence(i) {
        var o = model.get(i, AgendaModel.OccurrenceObjectRole)
        var e = model.get(i, AgendaModel.EventObjectRole)
        if (!o || !e)
            return null
        return { start: o.startTime, end: o.endTime, title: e.displayLabel, allDay: e.allDay }
    }

    property AgendaModel model: AgendaModel {
        startDate: new Date(source.day.getFullYear(), source.day.getMonth(), source.day.getDate())
        // 24 h from any time of the day reach into the next day
        endDate: new Date(source.day.getFullYear(), source.day.getMonth(), source.day.getDate() + 2)
        onUpdated: source.updated()
    }
}
