/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of Recents (W2-launcher-app-list, app-launcher-18/-19/-20) as
 * pure functions, unit tested (tests tst_applist.qml).
 *
 * Stock: the side button's Recents shows up to 8 apps, newest first, the one
 * in front first, no duplicates (SysUI iwm.java:181, 199-201, 398); an app
 * with an ongoing activity shows its status line (hca.java:238-271).
 *
 * The history is {d: the launcher entry's file name, t: the time of the
 * launch in ms}, newest first, kept in dconf and written when an app is
 * launched or cleared (never by a timer). */

var MAX_ENTRIES = 8

/* entries of the app launcher that are not apps with a window of their own:
 * they never go to Recents */
var NO_WINDOW = ["asteroid-assistant.desktop", "asteroid-find-my-phone.desktop"]

function desktopId(path) {
    var s = String(path || "")
    return s.substring(s.lastIndexOf("/") + 1)
}

function recordable(desktop) {
    return desktop !== "" && NO_WINDOW.indexOf(desktop) < 0
}

function valid(e) {
    return e && typeof e.d === "string" && e.d !== "" && typeof e.t === "number"
}

/* The stored text to a list; anything wrong is an empty history */
function parse(text) {
    try {
        var a = JSON.parse(text || "[]")
        if (!Array.isArray(a))
            return []
        var out = []
        for (var i = 0; i < a.length; i++)
            if (valid(a[i]) && out.length < MAX_ENTRIES && !has(out, a[i].d))
                out.push({ d: a[i].d, t: a[i].t })
        return out
    } catch (e) {
        return []
    }
}

function stringify(list) {
    return JSON.stringify(list)
}

function has(list, desktop) {
    for (var i = 0; i < list.length; i++)
        if (list[i].d === desktop)
            return true
    return false
}

/* An app was launched: it goes to the front of the list (once), at most 8 */
function record(list, desktop, now) {
    if (!recordable(desktop))
        return list
    var out = [{ d: desktop, t: now }]
    for (var i = 0; i < list.length && out.length < MAX_ENTRIES; i++)
        if (list[i].d !== desktop)
            out.push(list[i])
    return out
}

/* "Clear from Recents" */
function forget(list, desktop) {
    var out = []
    for (var i = 0; i < list.length; i++)
        if (list[i].d !== desktop)
            out.push(list[i])
    return out
}

/* What Recents shows.
 *   items     the launcher's apps: { filePath, exec, ... }
 *   keyOf     item -> the app key of the compositor's windows
 *   frontKey  the app in front when Recents opened, "" for none
 *   running   keys of the apps running in the background, most recent first
 *   ongoing   { key: true } of the apps with an ongoing activity
 *   history   parse()
 *   statuses  { key: text } of the ongoing activities (x-eos-ongoing-status)
 * Order: the front app, then apps with an ongoing activity, then the history
 * (newest first), then running apps the history does not know. No
 * duplicates, no app that is not installed any more, at most 8. */
function build(items, keyOf, frontKey, running, ongoing, history, statuses) {
    var byKey = {}, byDesktop = {}
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it || !it.filePath)
            continue
        var k = keyOf(it)
        if (k !== "" && !byKey[k])
            byKey[k] = it
        byDesktop[desktopId(it.filePath)] = it
    }
    var out = [], seen = {}
    function add(it, front) {
        if (!it || out.length >= MAX_ENTRIES)
            return
        var d = desktopId(it.filePath)
        if (seen[d] || !recordable(d))
            return
        seen[d] = true
        var key = keyOf(it)
        var st = lookup(statuses, key)
        out.push({ item: it, key: key, desktop: d, front: !!front, ongoing: lookup(ongoing, key) === true,
                   status: typeof st === "string" ? st : "" })
    }
    if (frontKey && byKey[frontKey])
        add(byKey[frontKey], true)
    // the apps with an ongoing activity, in the order of the history
    for (var h = 0; h < history.length; h++) {
        var hi = byDesktop[history[h].d]
        if (hi && lookup(ongoing, keyOf(hi)) === true)
            add(hi, false)
    }
    for (var h2 = 0; h2 < history.length; h2++)
        add(byDesktop[history[h2].d], false)
    for (var r = 0; r < (running || []).length; r++)
        add(byKey[running[r]], false)
    return out
}

/* An ongoing notification may name its app by the program without
 * 'asteroid-' (lifecycle.js windowOngoing does the same) */
function lookup(map, key) {
    if (!map || !key)
        return undefined
    if (map[key] !== undefined)
        return map[key]
    return map[key.indexOf("asteroid-") === 0 ? key.substring(9) : key]
}
