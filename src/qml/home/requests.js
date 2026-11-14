/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The requests other programs make of the launcher through dconf, as plain strings
 * "<route>@<ms>" (ms = Date.now() of the writer): /org/asteroidos/launcher/start-tutorial
 * ("tutorial@<ms>"), /org/asteroidos/launcher/open-face-picker ("picker@<ms>") and
 * /org/asteroidos/settings/ui/open ("<page>@<ms>"). A request acts only while it is younger
 * than 60 s, so one left in dconf from before a restart does nothing (CR-11, CR-12, CR-16).
 * Pure functions, unit tested (tst_fpl2.qml). */

var MAX_AGE_MS = 60000
// a writer's clock may be a moment ahead of ours
var SKEW_MS = 5000

// "tutorial@1700000000000" -> { route: "tutorial", ms: 1700000000000 }; null when it is no request
function parse(value) {
    var s = String(value === undefined || value === null ? "" : value)
    var at = s.lastIndexOf("@")
    if (at <= 0 || at === s.length - 1)
        return null
    var stamp = s.substring(at + 1)
    if (!/^[0-9]+$/.test(stamp))
        return null
    return { route: s.substring(0, at), ms: Number(stamp) }
}

// the request is of that route (empty route: any) and younger than 60 s at `now`
function fresh(value, route, now) {
    var p = parse(value)
    if (p === null)
        return false
    if (route !== "" && p.route !== route)
        return false
    var age = now - p.ms
    return age <= MAX_AGE_MS && age >= -SKEW_MS
}
