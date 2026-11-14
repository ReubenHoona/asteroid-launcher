/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* What counts as unread, and what marks it read (W2-launcher-status; audit
 * status-indicators-08, -05). Stock SysUI's UnreadItemsTracker (hkt.java):
 * every new item is unread; a newer revision of a read item is unread again
 * (hkt.java b()); opening the stream marks all read (jui.java:33-55); opening
 * one notification's full view from a heads-up or the glanceable view marks
 * only that one (enj.java:285-296, kne.java:51-60). Ours keeps both: the time
 * the stream was last looked at (seenUntil, over restarts) and the set of items
 * read one by one ({id: revision}, a revision is the item's timestamp in ms).
 *
 * A call has its own screen and an ongoing activity its own chip: neither is
 * an unread notification (status-indicators-11). */

function hint(n, key) {
    return n && n.hints ? n.hints[key] : undefined
}

// a call (answer, reject or end offered by the phone)
function isCall(n) {
    var a = hint(n, "x-asteroid-phone-actions")
    a = a ? String(a).split(",") : []
    return a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0 || a.indexOf("end") >= 0
}

// compositor/lifecycle.js ongoingKey / eosongoing.h isOngoing
function isOngoing(n) {
    var e = hint(n, "x-eos-ongoing"), m = hint(n, "x-nemo-ongoing")
    return e === true || e === "true" || e === "1" || m === true || m === "true" || m === "1"
           || (n && (n.category === "x-eos.ongoing" || n.category === "x-nemo.ongoing"))
           || hint(n, "x-asteroid-category") === "ongoing"
}

// the revision of a notification: its time in ms, NaN without one
function revision(n) {
    if (!n || !n.timestamp)
        return NaN
    var t = n.timestamp.getTime ? n.timestamp.getTime() : Number(n.timestamp)
    return t
}

function counts(n) {
    return n && !isCall(n) && !isOngoing(n) && !isNaN(revision(n))
}

/* Unread: counted, newer than the last look at the stream, and not read one by one at this
 * revision. read: {id: revision}. */
function isUnread(n, seenUntil, read) {
    if (!counts(n))
        return false
    var t = revision(n)
    if (t <= (Number(seenUntil) || 0))
        return false
    var r = read ? read[n.replacesId] : undefined
    return !(r !== undefined && r >= t)
}

/* items: the notifications in order. {count, newest}: newest is the newest time of any counted item
 * (what "seen until" takes at "mark all read"). */
function summarize(items, seenUntil, read) {
    var count = 0, newest = 0
    for (var i = 0; i < items.length; i++) {
        var n = items[i]
        if (!counts(n))
            continue
        newest = Math.max(newest, revision(n))
        if (isUnread(n, seenUntil, read))
            count++
    }
    return { count: count, newest: newest }
}

// the set after one item is opened: {id: revision}, a new object (a binding sees the change)
function markRead(read, n) {
    var out = {}
    for (var k in read)
        out[k] = read[k]
    if (counts(n))
        out[n.replacesId] = revision(n)
    return out
}

// the set without the items that are gone
function prune(read, items) {
    var present = {}
    for (var i = 0; i < items.length; i++)
        if (items[i])
            present[items[i].replacesId] = true
    var out = {}
    for (var k in read)
        if (present[k])
            out[k] = read[k]
    return out
}

// the bar's geometry (nai.java:33-58, overlay.css): a segment of the screen's edge circle at 6 o'clock
var BAR_STROKE_DP = 4      // arc-width 4dp, round caps
var BAR_LENGTH_DP = 16     // 16 dp end to end, caps included
var BAR_REST_DP = 2        // y = 100% - 2dp at rest
var BAR_SLIDE_DP = 5       // from 100% + 3dp: 5 dp up
var BAR_SLIDE_MS = 500     // cubic-bezier(0, 0, 0, 1)
var PILL_W_DP = 32, PILL_H_DP = 8, PILL_OPACITY = 0.8, PILL_BELOW_DP = 2

/* The sweep in degrees of a bar `lengthPx` long with `strokePx` caps on a circle `screenPx` across: the
 * chord between the cap centres, 2 * atan(((length - stroke) / 2) / radius) (nai.java:41-44; 7.2 degrees
 * on the 192 dp screen). */
function barSweepDeg(screenPx, lengthPx, strokePx) {
    var radius = screenPx / 2
    return 2 * Math.atan(((lengthPx - strokePx) / 2) / radius) * 180 / Math.PI
}
