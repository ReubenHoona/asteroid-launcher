/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The face chip of the ongoing activities (W2-launcher-status; audit
 * status-indicators-12, -13, alarms-timers-stopwatch-32, media-controls-17):
 * its text, its timer parts, its icon and its size. The registry (C++,
 * src/ongoingregistry.h) orders the entries; this is what the chip shows of
 * the first. Stock: the Live Space of SysUI (mzr.java:226-262, mzw.java
 * StatusTransformer, dji.java:308-327, myx.java:22-38). */

// $ST VALUES.tsv sysui live_space_height 32dp, live_space_bottom_padding 8dp; the icon 18 dp
// (overlay_icon_size); the tap target at least 60 dp tall (overlay_icon_min_tap_target_height)
var HEIGHT_DP = 32
var BOTTOM_DP = 8
var ICON_DP = 18
var TAP_MIN_DP = 60
// the expanded chip is at most this share of the screen's chord at its middle (our design)
var MAX_CHORD = 0.7
// the transitions of the chip: 250 ms (the Live Space code holds a 250 ms duration, mzg.java:33)
var TRANSITION_MS = 250
// our own look: black at 70 % behind the icon
var BACKDROP_OPACITY = 0.7

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

// expanded when the entry has something to say (dji.java:308-327)
function expanded(e, nowMs) {
    return text(e, nowMs) !== ""
}

/* Milliseconds until the text changes next, Infinity when it does not (a paused timer, "Now", no time):
 * the chip arms one single-shot timer for that, never polls. */
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

// the always-on layout key of the chip: the entry and its icon, never the text (the hub draws icon only)
function chipKey(e) {
    return e && e.key ? e.key + "|" + staticIcon(e) : ""
}

/* The most the expanded chip may be wide: MAX_CHORD of the screen's chord at the chip's middle height.
 * screenPx the screen's width, middleFromBottomPx the chip's middle above the screen's bottom. */
function maxWidth(screenPx, middleFromBottomPx) {
    var r = screenPx / 2
    var dy = r - middleFromBottomPx
    var chord = 2 * Math.sqrt(Math.max(0, r * r - dy * dy))
    return MAX_CHORD * chord
}
