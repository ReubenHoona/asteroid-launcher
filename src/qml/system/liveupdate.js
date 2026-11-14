/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The relative time of the live update full view (system-dialogs-misc-12): stock's
 * live_update_full_view_duration_hours "in %dh", _minutes "in %dm" and live_update_now "Now"
 * (LiveUpdateActivity). Pure functions: tests tst_liveupdate.qml. */

/* { kind: "h" | "m" | "now", n } for an entry that happens at whenMs (the epoch, ms). An hour or more
 * ahead is in whole hours (rounded down), a minute or more in whole minutes, less than a minute or past
 * is "now". */
function relative(whenMs, nowMs) {
    var left = whenMs - nowMs
    if (!(whenMs > 0))
        return { kind: "none", n: 0 }
    if (left >= 3600000)
        return { kind: "h", n: Math.floor(left / 3600000) }
    if (left >= 60000)
        return { kind: "m", n: Math.floor(left / 60000) }
    return { kind: "now", n: 0 }
}

/* Milliseconds until the text changes next (one single-shot timer, armed only while the full view is on
 * screen with the display on, never in the always-on screen), Infinity when it does not change. */
function nextChangeMs(whenMs, nowMs) {
    var left = whenMs - nowMs
    if (!(whenMs > 0) || left <= 0)
        return Infinity
    if (left >= 3600000)
        return left - Math.floor(left / 3600000) * 3600000 + 1
    if (left >= 60000)
        return left - Math.floor(left / 60000) * 60000 + 1
    // under a minute it says "Now" and stays so
    return Infinity
}

// the entry with this key in a list of entries, null when there is none
function find(entries, key) {
    for (var i = 0; entries && i < entries.length; i++)
        if (entries[i] && entries[i].key === key)
            return entries[i]
    return null
}
