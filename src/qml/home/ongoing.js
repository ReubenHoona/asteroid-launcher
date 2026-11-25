/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The ongoing activities (W2-launcher-status; audit status-indicators-12, -13,
 * alarms-timers-stopwatch-32, media-controls-17): their text, their timer parts
 * and their icon. The registry (C++, src/ongoingregistry.h) orders the entries;
 * the face's bottom row shows the first one's icon (LiveSpace, N61-17: icon
 * only, as the Wear OS 6 emulator), the stream's live chips (LiveChips) the
 * text. Stock: the Live Space of SysUI (mzr.java:226-262, mzw.java
 * StatusTransformer, dji.java:308-327, myx.java:22-38). */

// the icon 18 dp (overlay_icon_size)
var ICON_DP = 18

var DEFAULT_ICON = {
    call: "ms-call",
    transport: "ms-music_note",
    alarm: "ms-alarm",
    stopwatch: "ms-timer",
    workout: "ms-directions_walk",
    navigation: "ms-navigation",
    location_sharing: "ms-location_on",
    other: "ms-schedule"
}

// the static icon of an entry: the one it gave, else the one of its category
function staticIcon(e) {
    if (e && e.staticIcon)
        return e.staticIcon
    return e && DEFAULT_ICON[e.category] ? DEFAULT_ICON[e.category] : DEFAULT_ICON.other
}

// an icon given as a file (an image, maybe animated) rather than an icon name
function isFile(name) {
    return name !== undefined && name !== "" && (name.indexOf("/") >= 0 || name.indexOf(".") > 0)
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

/* DateUtils.formatElapsedTime as the call screen has it: "00:42", "1:02:03" */
function formatElapsed(totalSeconds) {
    var s = Math.max(0, Math.floor(totalSeconds))
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60
    s = s % 60
    return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : pad2(m) + ":" + pad2(s)
}

/* A Live Update's time as stock shows it (mzr.java:226-262: live_update_duration_hours "%d hr",
 * live_update_duration_minutes "%d min", live_update_now "Now"). */
function durationText(whenMs, nowMs) {
    var left = whenMs - nowMs
    if (left >= 3600000)
        return Math.floor(left / 3600000) + " hr"
    if (left >= 60000)
        return Math.floor(left / 60000) + " min"
    return "Now"
}

// a timer part: a count-up from `when`, a countdown to it, a paused one standing still
function timerText(e, nowMs) {
    if (!e || !(e.when > 0))
        return ""
    if (e.duration)
        return durationText(e.when, nowMs)
    if (e.paused && e.frozen >= 0)
        return formatElapsed(e.frozen / 1000)
    if (e.countdown)
        return formatElapsed(Math.ceil((e.when - nowMs) / 1000))
    return formatElapsed((nowMs - e.when) / 1000)
}

/* The chip's text: the status with "%t" replaced by the timer part; a status without "%t" as it is;
 * no status but a time: the timer part alone ("--" when it has nothing: mzw.java). */
function text(e, nowMs) {
    if (!e)
        return ""
    var st = e.status || ""
    if (st.indexOf("%t") >= 0)
        return st.replace("%t", timerText(e, nowMs))
    if (st !== "")
        return st
    return e.when > 0 ? timerText(e, nowMs) : ""
}

/* Milliseconds until the text changes next, Infinity when it does not (a paused timer, "Now", no time):
 * a live chip arms one single-shot timer for that, never polls. */
function nextChangeMs(e, nowMs) {
    if (!e || !(e.when > 0))
        return Infinity
    var st = e.status || ""
    if (st !== "" && st.indexOf("%t") < 0)
        return Infinity
    if (e.duration) {
        var left = e.when - nowMs
        if (left >= 3600000)
            return left - Math.floor(left / 3600000) * 3600000 + 1
        if (left >= 60000)
            return left - Math.floor(left / 60000) * 60000 + 1
        return left > 0 ? left + 1 : Infinity
    }
    if (e.paused && e.frozen >= 0)
        return Infinity
    if (e.countdown) {
        // the text shows the seconds left rounded up: it changes when a whole second is crossed
        var r = e.when - nowMs
        if (r <= 0)
            return Infinity
        var rem = r % 1000
        return (rem === 0 ? 1000 : rem) + 1
    }
    var up = nowMs - e.when
    return 1000 - (((up % 1000) + 1000) % 1000) + 1
}

// the content description (w2_ongoing_activity)
function description(e) {
    return "Ongoing " + (e && e.title ? e.title : "") + " running in the background"
}

// the always-on layout key of the face's icon: the entry and its icon, never the text
function chipKey(e) {
    return e && e.key ? e.key + "|" + staticIcon(e) : ""
}
