/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/*
 * The rules of the Alarm and Timer tiles (W3-launcher-tiles-content-a), as
 * stock CP3A's Clock tiles (com.google.android.deskclock, decompiled): which
 * alarm the tile shows and in which state (hnv.java:44, 63-104, 124-150),
 * the repeat text (goh.java:1620-1655), the saved timers and how they are
 * laid out (ibk.java, ezv.java:96-115) and the label of a timer button
 * (ibr.java:67-73). Pure functions: no timers, no D-Bus, no clock of their
 * own (the caller says what time it is).
 */

// timed's day letters, Monday first (the order the alarm clock stores them in)
var DAY_CODES = "mtwTfsS"

/* ---- alarms ---------------------------------------------------------- */

// the day flags of a daysOfWeek string, Monday first
function dayFlags(days) {
    var out = []
    var s = days || ""
    for (var i = 0; i < 7; i++)
        out.push(s.indexOf(DAY_CODES[i]) >= 0)
    return out
}

// the day indexes (0 = Monday) in the order a week starts in the locale
// (firstDay as Qt.locale().firstDayOfWeek: 0 Sunday, 1 Monday ... 6 Saturday)
function weekOrder(firstDay) {
    var start = (Number(firstDay) + 6) % 7
    var out = []
    for (var i = 0; i < 7; i++)
        out.push((start + i) % 7)
    return out
}

/* The first line of the card (hhz.java:90-103 e(), goh.java y()): 'One time',
 * 'Every day', one day by its full name, several by their short names joined
 * with ', ' from the locale's first day. Same text as the alarm clock's list.
 * locale: a QML locale (dayName, firstDayOfWeek). */
function repeatText(days, locale, oneTimeText, everyDayText) {
    var flags = dayFlags(days)
    var set = 0
    for (var i = 0; i < 7; i++)
        if (flags[i])
            set++
    if (set === 0)
        return oneTimeText
    if (set === 7)
        return everyDayText
    var order = weekOrder(locale.firstDayOfWeek)
    var names = []
    for (var k = 0; k < order.length; k++) {
        var d = order[k]
        // Qt.locale().dayName: 1 Monday ... 7 Sunday; Locale.LongFormat 0, ShortFormat 1
        if (flags[d])
            names.push(locale.dayName(d + 1, set === 1 ? 0 : 1))
    }
    return names.join(", ")
}

/* When an alarm next rings (ms since the epoch), 0 when it is off. timed's
 * trigger time wins when it is still ahead (it also holds a snooze). */
function nextRing(a, nowMs) {
    if (!a.enabled)
        return 0
    if (a.triggerTime * 1000 > nowMs)
        return a.triggerTime * 1000
    var now = new Date(nowMs)
    for (var d = 0; d < 8; d++) {
        var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, a.hour, a.minute)
        if (t.getTime() <= nowMs)
            continue
        if ((a.daysOfWeek || "") === "" || a.daysOfWeek.indexOf(DAY_CODES[(t.getDay() + 6) % 7]) >= 0)
            return t.getTime()
    }
    return 0
}

/* A snoozed alarm (hnv.java:76-104): it is on, timed holds a trigger time
 * ahead (the alarm presenter re-armed it with the snooze trigger) and that
 * time is not the alarm's own hour:minute. Returns the time it rings again
 * (ms), or 0. */
function snoozedUntil(a, nowMs) {
    if (!a.enabled || !(a.triggerTime > 0))
        return 0
    var at = a.triggerTime * 1000
    if (at <= nowMs)
        return 0
    var t = new Date(at)
    if (t.getHours() === a.hour && t.getMinutes() === a.minute)
        return 0
    return at
}

/* What the tile shows (hnv.java:44-71): the alarm that rings next of those
 * that are on, never a countdown. alarms: nemo alarm objects (enabled, hour,
 * minute, daysOfWeek, triggerTime, countdown). Returns
 *   { state: "none" }   no alarm is on (the 'Set new alarm' button)
 *   { state: "next", alarm, at }
 *   { state: "snoozed", alarm, at, until }   (the alarm is snoozed and rings first) */
function pick(alarms, nowMs) {
    var best = null
    for (var i = 0; i < alarms.length; i++) {
        var a = alarms[i]
        if (!a || a.countdown || !a.enabled)
            continue
        var until = snoozedUntil(a, nowMs)
        var at = until > 0 ? until : nextRing(a, nowMs)
        if (!at)
            continue
        if (best === null || at < best.at)
            best = { alarm: a, at: at, until: until }
    }
    if (best === null)
        return { state: "none" }
    return { state: best.until > 0 ? "snoozed" : "next", alarm: best.alarm, at: best.at, until: best.until }
}

// a Date for an alarm's own hour:minute (the date is only a carrier)
function clockDate(hour, minute) {
    return new Date(2000, 0, 1, hour, minute)
}

/* ---- timers ---------------------------------------------------------- */

// ibk.java:67 with ibj.java:24: the saved timers a screen under 225 dp starts
// with when the user has none: 5, 10, 15, 30 min (the recents of the Timer
// app, which also has 1 min, once the app has written its list)
var DEFAULT_RECENTS = [300, 600, 900, 1800]
// ezv.java:96-115 lays out at most five buttons
var MAX_BUTTONS = 5
// the Timer app's picker has hours 0-23 (asteroid-timer TimerLogic.js)
var MAX_SECONDS = 23 * 3600 + 59 * 60 + 59

/* The saved timers as the dconf value gives them (a string list; numbers and
 * a "60,300" string are taken too): whole seconds above 0, each once,
 * shortest first (ibk.java:41-68 keeps a TreeSet of durations). Same rules as
 * the Timer app's parseRecents, so both read one list. */
function parseRecents(value) {
    var src = []
    if (typeof value === "string") {
        src = value === "" ? [] : value.split(",")
    } else if (value && typeof value.length === "number") {
        for (var i = 0; i < value.length; i++)
            src.push(value[i])
    }
    var seen = {}
    var out = []
    for (var j = 0; j < src.length; j++) {
        var n = Math.round(Number(src[j]))
        if (isFinite(n) && n > 0 && n <= MAX_SECONDS && !seen[n]) {
            seen[n] = true
            out.push(n)
        }
    }
    out.sort(function (a, b) { return a - b })
    return out
}

function addRecent(list, seconds) {
    return parseRecents(list.concat([seconds]))
}

// what goes into dconf: a string list (a plain int list is not safe in every dconf binding)
function recentsToStore(list) {
    return list.map(function (s) { return String(s) })
}

/* The durations the idle tile offers: the saved list, else the defaults; at
 * most five (the store is a set, so a longer list keeps the shortest five). */
function buttons(saved) {
    var list = parseRecents(saved)
    if (list.length === 0)
        list = DEFAULT_RECENTS.slice()
    return list.slice(0, MAX_BUTTONS)
}

/* The label of a timer button (ibr.java:67-73, duration_separator ':'): the
 * number over the unit. Whole hours 'Hr', whole minutes 'Min', seconds
 * 'Sec'; a mixed duration writes the parts with ':' and joins the units the
 * same way. units: { hour: "Hr", minute: "Min", second: "Sec", sep: ":" }
 * Returns { number, unit, wide } (wide: the number is longer than 3
 * characters, which the layout counts). */
function label(seconds, units) {
    var h = Math.floor(seconds / 3600)
    var m = Math.floor(seconds / 60) % 60
    var s = seconds % 60
    var sep = units.sep
    var p2 = function (n) { return (n < 10 ? "0" : "") + n }
    var number, unit
    if (h > 0) {
        if (m === 0 && s === 0) {
            number = String(h)
            unit = units.hour
        } else if (s === 0) {
            number = h + sep + p2(m)
            unit = units.hour + sep + units.minute
        } else {
            number = h + sep + p2(m) + sep + p2(s)
            unit = units.hour + sep + units.minute + sep + units.second
        }
    } else if (m > 0) {
        if (s === 0) {
            number = String(m)
            unit = units.minute
        } else {
            number = m + sep + p2(s)
            unit = units.minute + sep + units.second
        }
    } else {
        number = String(s)
        unit = units.second
    }
    return { number: number, unit: unit, wide: number.length > 3 }
}

/* How many buttons go in each row (ezv.java:96-115, ibr.e): fewer than four
 * in one row, four as 2 x 2, five as 3 + 2 (2 + 3 when one of the first
 * three has a wide label). durations: the buttons' seconds (<= 5);
 * units as for label(). */
function rows(durations, units) {
    var n = durations.length
    if (n === 0)
        return []
    if (n < 4)
        return [n]
    if (n === 4)
        return [2, 2]
    for (var i = 0; i < 3; i++)
        if (label(durations[i], units).wide)
            return [2, 3]
    return [3, 2]
}

/* ---- the running timer (what a Nemo countdown alarm is) ---------------- */

/* The state of a countdown alarm (asteroid-timer TimerLogic.classify, from
 * nemo-qml-plugin-alarms alarmobject.cpp save()): running: enabled with the
 * trigger time ahead; paused: not enabled, trigger time 0, the duration less
 * `elapsed` seconds left; expired: anything else. */
function classify(a, nowMs) {
    var dur = a.hour * 3600 + a.minute * 60 + a.second
    var r = { state: "expired", durationSec: dur, endMs: 0, frozenMs: 0 }
    if (!(dur > 0))
        return r
    if (a.enabled) {
        var end = a.triggerTime * 1000
        if (end > nowMs) {
            r.state = "running"
            r.endMs = end
        }
    } else if (!(a.triggerTime > 0)) {
        var left = dur - (a.elapsed > 0 ? a.elapsed : 0)
        if (left > 0) {
            r.state = "paused"
            r.frozenMs = left * 1000
        }
    }
    return r
}

/* The countdown's text (dwf.java:109-258, the Timer app's countdownText):
 * 'H:MM:SS', 'M:SS' or 'S', whole seconds rounded up. */
function countdownText(ms) {
    var s = Math.ceil(Math.max(0, ms) / 1000)
    var h = Math.floor(s / 3600)
    var m = Math.floor(s / 60) % 60
    var sec = s % 60
    var p2 = function (n) { return (n < 10 ? "0" : "") + n }
    if (h > 0)
        return h + ":" + p2(m) + ":" + p2(sec)
    if (m > 0)
        return m + ":" + p2(sec)
    return String(sec)
}

/* The total of the timer as the card's second line ('5:00', dwf.java content):
 * 'H:MM:SS' or 'M:SS' of the whole duration. */
function totalText(durationSec) {
    var h = Math.floor(durationSec / 3600)
    var m = Math.floor(durationSec / 60) % 60
    var s = durationSec % 60
    var p2 = function (n) { return (n < 10 ? "0" : "") + n }
    return h > 0 ? h + ":" + p2(m) + ":" + p2(s) : m + ":" + p2(s)
}

// the share of the timer that is left, 0..1 (the ring)
function ringProgress(remainingMs, durationSec) {
    if (!(durationSec > 0))
        return 0
    return Math.max(0, Math.min(1, remainingMs / (durationSec * 1000)))
}

/* Milliseconds until countdownText changes (the next whole second of the
 * time left); Infinity when it does not (paused, over). One single shot per
 * second while the tile shows, none otherwise. */
function nextTickMs(remainingMs) {
    if (!(remainingMs > 0))
        return Infinity
    var rem = remainingMs % 1000
    return (rem === 0 ? 1000 : rem) + 1
}
