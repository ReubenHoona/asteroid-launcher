/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.calendar

/*
 * The calendar's events of one window for the assistant's calendar answers (AssistantActions calendarQuery): the
 * watch's calendar database, where the phone's calendar arrives through asteroid-btsyncd, as the agenda tile and
 * the next event complication read it. Made for one question and dropped after it: nothing is read or watched
 * otherwise. list(): [{ start, end (ms), title, allDay }] in the model's order; updated: the window was read.
 */
QtObject {
    id: reader

    property date startDate
    property date endDate
    signal updated()

    function list() {
        var out = []
        for (var i = 0; i < model.count; i++) {
            var o = model.get(i, AgendaModel.OccurrenceObjectRole)
            var e = model.get(i, AgendaModel.EventObjectRole)
            if (o && e)
                out.push({ start: o.startTime.getTime(), end: o.endTime.getTime(), title: e.displayLabel, allDay: e.allDay })
        }
        return out
    }

    property AgendaModel model: AgendaModel {
        startDate: reader.startDate
        endDate: reader.endDate
        onUpdated: reader.updated()
    }
}
