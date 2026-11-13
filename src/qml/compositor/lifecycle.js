/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The application lifecycle rules (W2-launcher-keys-lifecycle) as pure
 * functions, so the state machine is unit tested (tst_lifecycle.qml).
 * AppLifecycle.qml owns the state and the one timer; this file decides.
 *
 * Stock (CP3A):
 *  - Home and Back move an app to the background, nothing is destroyed;
 *    cached apps are frozen 5 s after they leave the screen
 *    (config_defaultFreezerDebounceTimeout 5000, FrameworksOverlayClockwork:
 *    OVERLAYS.md; audit buttons-navigation-04);
 *  - after the display went off, the top task goes to the back (the face
 *    shows) once wear_activity_auto_resume_timeout_ms (default 60000)
 *    passed; a wake shorter than that restarts the count, at most 2 times
 *    (ambient_auto_resume_timeout_max_reset_count 2), then the first start
 *    is kept; tasks with an ongoing activity never expire, and the count
 *    restarts 500 ms after the ongoing activity ended
 *    (TaskTimeoutController.java:164-166,208, HeadlessTaskManagementSession
 *    .java:229-251,327-445; audit interruptions-01, ambient-aod-03). The
 *    stock timer is a non-wakeup ELAPSED_REALTIME alarm: it fires when the
 *    device is awake again. Here no timer runs while the display is off at
 *    all: the check is made at the wake, against the boot-time clock.
 */

var FREEZE_DELAY_MS = 5000         // config_defaultFreezerDebounceTimeout
var MAX_RESETS = 2                 // ambient_auto_resume_timeout_max_reset_count
var ONGOING_GRACE_MS = 500         // HeadlessTaskManagementSession postDelayed(.., 500)
var NEVER_MS = 86400000            // 'Never' in Settings > Display > Go to watch face
var DEFAULT_TIMEOUT_MS = 60000     // wear_activity_auto_resume_timeout_ms
var MAX_HIDDEN = 4                 // hidden apps kept (audit buttons-navigation-04)

// The seven stock options (VALUES.tsv activity_auto_resume_timeout_values_ms)
var TIMEOUT_OPTIONS_MS = [0, 15000, 30000, 60000, 120000, 300000, 86400000]

function timeoutValue(v) {
    var n = Number(v)
    return (isNaN(n) || n < 0) ? DEFAULT_TIMEOUT_MS : n
}

function isNever(ms) { return ms >= NEVER_MS }

/* ---- the go-to-watch-face episode ----------------------------------- */

function newEpisode() { return { active: false, start: 0, resets: 0, wakeAt: -1 } }

/* The display went off (blank or always-on). A wake shorter than the
 * timeout restarts the count (start = now), at most MAX_RESETS times;
 * after that the first start is kept. A wake as long as the timeout or
 * longer was real use: a new count. */
function displayOff(ep, now, timeoutMs) {
    var shortWake = ep.active && ep.wakeAt >= 0 && (now - ep.wakeAt) < timeoutMs
    if (shortWake) {
        if (ep.resets < MAX_RESETS) {
            ep.start = now
            ep.resets++
        }
    } else {
        ep.active = true
        ep.start = now
        ep.resets = 0
    }
    ep.wakeAt = -1
}

/* The count has run out at `now` (the display wakes, or it went off with
 * 'Immediately'). */
function expired(ep, now, timeoutMs) {
    if (!ep.active || isNever(timeoutMs))
        return false
    return now - ep.start >= timeoutMs
}

/* The display is on again. True when the app in front goes to the back
 * and the face shows; the episode is over then. A wake that does not
 * expire it stays a candidate "short wake" for the next display off. */
function displayOn(ep, now, timeoutMs) {
    if (expired(ep, now, timeoutMs)) {
        ep.active = false
        ep.wakeAt = -1
        return true
    }
    if (ep.active && ep.wakeAt < 0)
        ep.wakeAt = now
    return false
}

/* An ongoing activity ended while the display was off: the count starts
 * again, 500 ms later. */
function ongoingEnded(ep, now) {
    ep.active = true
    ep.start = now + ONGOING_GRACE_MS
    ep.resets = 0
    ep.wakeAt = -1
}

/* The episode ends for good (the user left the app, the face shows). */
function episodeEnd(ep) {
    ep.active = false
    ep.wakeAt = -1
    ep.resets = 0
}

/* ---- freezing hidden apps ------------------------------------------- */

/* hidden: [{id, hiddenAt, frozen, ongoing, lastUsed}] -> ids to freeze at
 * `now`: left the screen FREEZE_DELAY_MS ago, not frozen, not ongoing. */
function dueToFreeze(hidden, now) {
    var r = []
    for (var i = 0; i < hidden.length; i++) {
        var h = hidden[i]
        if (!h.frozen && !h.ongoing && now - h.hiddenAt >= FREEZE_DELAY_MS)
            r.push(h.id)
    }
    return r
}

/* ms until the next freeze is due, or -1 when nothing waits (the timer
 * then does not run at all) */
function nextFreezeIn(hidden, now) {
    var best = -1
    for (var i = 0; i < hidden.length; i++) {
        var h = hidden[i]
        if (h.frozen || h.ongoing)
            continue
        var d = Math.max(0, FREEZE_DELAY_MS - (now - h.hiddenAt))
        if (best < 0 || d < best)
            best = d
    }
    return best
}

/* The hidden apps to close so that at most MAX_HIDDEN stay: the least
 * recently used first. Ongoing apps are the last to go. */
function evictions(hidden, max) {
    var limit = max === undefined ? MAX_HIDDEN : max
    if (hidden.length <= limit)
        return []
    var order = hidden.slice().sort(function (a, b) {
        if (a.ongoing !== b.ongoing)
            return a.ongoing ? 1 : -1
        return a.lastUsed - b.lastUsed
    })
    var r = []
    for (var i = 0; i < hidden.length - limit; i++)
        r.push(order[i].id)
    return r
}

/* Applications that hold a sensor or the position while they are open
 * and do not stop it when they leave the screen (they get no pause signal
 * yet): a frozen process keeps its sensorfw or GPS session running, so
 * they are closed 5 s after they left the screen, as before this change
 * (audit buttons-navigation-04: "until they do, keep an allow-list or
 * still close sensor-holding apps"). An app with an ongoing activity is
 * never closed or frozen. Remove a name when the app stops its sensors on
 * hide. */
var CLOSE_WHEN_HIDDEN = ["asteroid-hrm", "asteroid-compass", "asteroid-map"]

function closesWhenHidden(key) {
    return CLOSE_WHEN_HIDDEN.indexOf(appKey(key)) >= 0
}

/* ---- naming apps ------------------------------------------------------ */

/* "/usr/bin/asteroid-settings --x", "asteroid-settings.desktop",
 * "Asteroid-Settings" -> "asteroid-settings" */
function appKey(s) {
    var t = String(s || "").trim()
    if (t === "")
        return ""
    // an Exec line: its program, not its arguments
    var sp = t.search(/\s/)
    if (sp > 0)
        t = t.substring(0, sp)
    t = t.substring(t.lastIndexOf("/") + 1)
    if (t.length > 8 && t.substring(t.length - 8) === ".desktop")
        t = t.substring(0, t.length - 8)
    return t.toLowerCase()
}

/* Whether a notification says an app has an ongoing activity: the hint
 * x-eos-ongoing (or x-nemo-ongoing) true, or the category
 * x-eos.ongoing / x-nemo.ongoing. The app is named by x-eos-app (a
 * desktop id or program) or else by the notification's appName. */
function ongoingKey(hints, category, appName) {
    var h = hints || {}
    var on = h["x-eos-ongoing"] === true || h["x-nemo-ongoing"] === true
             || h["x-eos-ongoing"] === "true" || h["x-nemo-ongoing"] === "true"
             || category === "x-eos.ongoing" || category === "x-nemo.ongoing"
             || h["x-asteroid-category"] === "ongoing"
    if (!on)
        return ""
    return appKey(h["x-eos-app"] || appName)
}

/* Does a window belong to the ongoing app `key`? A window's key is its
 * appKey (the process name, lipstick) or, failing that, its title. A
 * notification's appName may carry the program name without 'asteroid-'. */
function windowOngoing(winKey, winTitle, keys) {
    var k = appKey(winKey) || appKey(winTitle)
    if (k === "")
        return false
    if (keys[k])
        return true
    var short = k.indexOf("asteroid-") === 0 ? k.substring(9) : k
    return !!keys[short]
}
