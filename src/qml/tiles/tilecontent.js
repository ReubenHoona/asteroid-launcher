/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The rules of the content tiles of W3-launcher-tiles-content-b as pure functions, tested in
 * tst_tiles_b.qml: Forecast, Solar, UV Index, Next event, Main goal, Daily heart rate, Sleep, Exercise quick
 * start. The tiles own the state and the drawing; this file decides. Stock numbers carry their source.
 * Sizes are px on the 384 px Pixel Watch 2 screen (2 px per dp).
 */

/* ---- colours (stock; a tile's own colours, not roles of the colour theme) ---- */

// the graphic data card of the Fitbit tiles (tile_*_preview.xml, tiles-individual-19, -20)
var CARD = "#29303D"
var GREEN = "#6DD58C"                 // goal met, Daily goal value (tiles-individual-19)
var GOAL_RING = "#A8C7FA"             // the ring, and its second lap
var PILL = "#3E4756"                  // the neutral pill under the count (inferred: not in the sources)
var HR_LINE = "#94D6FF"               // flex_lite_tile_heartrate_preview.xml
var HR_HIGH = "#E46962"               // highest bpm label and dot (tiles-individual-20)
var HR_LOW = "#2BC7F7"                // lowest
var HR_ICON = "#FFBA2B"               // heart icon of 'Current bpm'
var SLEEP_RING = "#E5C7FF"            // flex_lite_tile_sleep_preview.xml (health-fitness-32)
// the Health category colour of steps (health-fitness-20: the Health app's activity palette;
// flex_lite_tile_primarygoal_preview.xml, its ring and count). The Main goal data card keeps the
// colours tile_primarygoal_preview.xml gives it (CARD, GREEN, GOAL_RING)
var STEPS = "#80F7DD"
var SLEEP_TRACK = "#2D3130"
var EXERCISE_FIRST = "#6DD58C"        // tile_quickstart_preview.xml: the first button green, the rest blue
var EXERCISE_OTHER = "#A8C7FA"
var PRECIP_BG = "#A1C9FF"             // forecast_tile_precipitation_background_color
var PRECIP_FG = "#00315E"             // inferred: dark on the light blue
var QUICKADD = "#1A438F"              // add_tile.png (tiles-individual-29)

/* UV bands: forecast_tile_uv_pill_*, uv_tile_ring_color_*, uv_tile_label_color_* (VALUES.tsv, weather) */
var UV_BANDS = [
    { max: 2,  bg: "#BEEFBB", fg: "#00381F", ring: "#80DA88", label: "#72E5BA" },
    { max: 5,  bg: "#FFE07C", fg: "#4D2600", ring: "#FCBD00", label: "#FFF965" },
    { max: 7,  bg: "#FFB683", fg: "#522302", ring: "#FF8D41", label: "#FFA082" },
    { max: 10, bg: "#FF8983", fg: "#3A0907", ring: "#F55E57", label: "#FF746E" },
    { max: 1000, bg: "#C597FF", fg: "#280255", ring: "#AD72FF", label: "#A388FA" }
]

/* the band of a UV index (0-2, 3-5, 6-7, 8-10, 11+); the index rounds as the app rounds */
function uvBandIndex(uv) {
    var v = Math.round(Number(uv))
    for (var i = 0; i < UV_BANDS.length; i++)
        if (v <= UV_BANDS[i].max)
            return i
    return UV_BANDS.length - 1
}

function uvBand(uv) {
    return UV_BANDS[uvBandIndex(uv)]
}

/* The word of the band (uv_tile_uv_*_string) */
function uvWord(uv) {
    switch (uvBandIndex(uv)) {
    case 0:
        //% "Low"
        return qsTrId("id-tile-uv-low")
    case 1:
        //% "Moderate"
        return qsTrId("id-tile-uv-moderate")
    case 2:
        //% "High"
        return qsTrId("id-tile-uv-high")
    case 3:
        //% "Very High"
        return qsTrId("id-tile-uv-very-high")
    }
    //% "Extreme"
    return qsTrId("id-tile-uv-extreme")
}

/* The protection note of the UV tile (uv_tile_*_needed_string); the cut-offs 3 and 8 are the app's (weatherdata.js) */
function uvNote(uv) {
    var v = Math.round(Number(uv))
    if (v < 3)
        //% "No protection needed"
        return qsTrId("id-tile-uv-no-protection")
    if (v < 8)
        //% "Protection needed"
        return qsTrId("id-tile-uv-protection")
    //% "Extra protection needed"
    return qsTrId("id-tile-uv-extra-protection")
}

/* ---- Forecast ---- */

/* What the lower right pill of the Forecast tile shows: the chance of rain when it is above 5 %, else the UV
 * index (hlh.java:60-170): { kind: "rain", pop } or { kind: "uv", uv } (uv null: unknown, shown "--") */
function forecastPill(pop, uv) {
    var p = Number(pop)
    if (isFinite(p) && pop !== null && p > 5)
        return { kind: "rain", pop: Math.round(p) }
    var u = (uv === null || uv === undefined || uv === "") ? NaN : Number(uv)
    return { kind: "uv", uv: isFinite(u) ? Math.round(u) : null }
}

/* The text of a temperature for the card: "13°", "--" when unknown (the unit comes from the setting) */
function degrees(c, fahrenheit) {
    if (c === null || c === undefined || c === "" || !isFinite(Number(c)))
        return "--"
    var v = fahrenheit ? Number(c) * 9 / 5 + 32 : Number(c)
    return (Math.round(v) + 0) + "°"
}

/* Which of the tile's states to show: "ok", "loading", "noconnection", "nolocation" or "downloadfailed" (the same
 * rules as the app's weatherdata.js screenState; ctx: hasData, refreshing, timedOut, phoneConnected, wifiConnected,
 * placeKnown) */
function weatherState(ctx) {
    if (ctx.hasData)
        return "ok"
    if (ctx.refreshing && !ctx.timedOut)
        return "loading"
    if (!ctx.phoneConnected && !ctx.wifiConnected)
        return "noconnection"
    if (!ctx.placeKnown)
        return "nolocation"
    return ctx.timedOut ? "downloadfailed" : "loading"
}

function weatherStateText(state) {
    switch (state) {
    case "noconnection":
        //% "Couldn’t connect to internet. Please check network connectivity."
        return qsTrId("id-tile-wx-no-internet")
    case "nolocation":
        //% "Couldn’t retrieve your location"
        return qsTrId("id-tile-wx-no-location")
    case "downloadfailed":
        //% "Can’t download weather data"
        return qsTrId("id-tile-wx-download-failed")
    }
    //% "Loading Weather…"
    return qsTrId("id-tile-wx-loading")
}

/* the button under the text: Settings for no connection, Retry for the others that can be retried, none while loading */
function weatherStateButton(state) {
    if (state === "noconnection")
        //% "Settings"
        return qsTrId("id-tile-wx-settings")
    if (state === "nolocation" || state === "downloadfailed")
        //% "Retry"
        return qsTrId("id-tile-wx-retry")
    return ""
}

/* ---- Solar ---- */

/* '6h 11m', '3h', '25m' (solar_tile_*_left_short); under a minute: 'Now' */
function solarDuration(sec) {
    var total = Math.floor(sec / 60)
    if (total < 1)
        //% "Now"
        return qsTrId("id-tile-solar-now")
    var h = Math.floor(total / 60), m = total % 60
    if (h > 0 && m > 0)
        //% "%1h %2m"
        return qsTrId("id-tile-solar-hm").replace("%1", h).replace("%2", m)
    if (h > 0)
        //% "%1h"
        return qsTrId("id-tile-solar-h").replace("%1", h)
    //% "%1m"
    return qsTrId("id-tile-solar-m").replace("%1", m)
}

/* The sun event after the next one (the line under the Solar card: 'Sunset' and its time after a sunrise, the
 * next day's 'Sunrise' after a sunset). days: [{ rise, set }] in seconds, today first; next: solarInfo(). */
function otherSun(days, next) {
    var i
    if (next.kind === "sunrise") {
        for (i = 0; i < days.length; i++)
            if (days[i].set > next.at)
                return { kind: "sunset", at: days[i].set }
    } else if (next.kind === "sunset") {
        for (i = 0; i < days.length; i++)
            if (days[i].rise > next.at)
                return { kind: "sunrise", at: days[i].rise }
    }
    return { kind: "none", at: 0 }
}

/* The sun's way through the half ring: 0 at the left end (sunrise), 1 at the right (sunset); night: the ring
 * is empty. Given the sun times of today. */
function sunProgress(rise, set, nowSec) {
    if (!(rise > 0) || !(set > rise))
        return 0
    if (nowSec <= rise)
        return 0
    if (nowSec >= set)
        return 1
    return (nowSec - rise) / (set - rise)
}

/* ---- Next event ---- */

/* The event the tile shows: the first one that has not ended; one running timed event before the rest, then by
 * start, an all-day event before a timed one that starts at the same time. list: [{ start, end, title, allDay }]
 * in ms; null when there is none. */
function pickEvent(list, nowMs) {
    var best = null
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!(e.end > nowMs) && !(e.end === e.start && e.start >= nowMs))
            continue
        if (best === null || _eventBefore(e, best, nowMs))
            best = e
    }
    return best
}

function _eventBefore(a, b, nowMs) {
    var ra = (!a.allDay && a.start <= nowMs) ? 0 : 1
    var rb = (!b.allDay && b.start <= nowMs) ? 0 : 1
    if (ra !== rb)
        return ra < rb
    if (a.start !== b.start)
        return a.start < b.start
    return a.allDay && !b.allDay
}

/* What the title of the tile says about the event: "now" (a timed event in progress), "today", "tomorrow" or
 * "date" (an all-day event that began earlier counts as today) */
function eventWhen(ev, nowMs) {
    if (!ev.allDay && ev.start <= nowMs && ev.end > nowMs)
        return "now"
    var now = new Date(nowMs)
    var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    var startOfTomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime()
    var startOfAfter = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2).getTime()
    if (ev.start < startOfTomorrow)
        return "today"
    if (ev.start < startOfAfter)
        return "tomorrow"
    return "date"
}

/* When to look again: the moment the shown event starts (its title says Now) or ends, whichever comes first
 * and is still ahead; -1 when there is none (an all-day event counts from its start only) */
function nextChangeMs(ev, nowMs) {
    if (!ev)
        return -1
    if (ev.start > nowMs)
        return ev.start
    if (ev.end > nowMs)
        return ev.end
    return -1
}

/* ---- Main goal ---- */

/* How the day's count stands against the goal (aflu.java:D): "left" (n steps to go), "met" (equal), "over" (n above);
 * ratio for the ring, 0 to 2 (the second lap is the overflow) */
function goalState(steps, goal) {
    steps = Math.max(0, Math.round(Number(steps) || 0))
    goal = Math.round(Number(goal) || 0)
    if (!(goal > 0))
        return { kind: "none", n: 0, met: false, ratio: 0 }
    var d = goal - steps
    return { kind: d > 0 ? "left" : d === 0 ? "met" : "over", n: Math.abs(d), met: steps >= goal, ratio: Math.min(2, steps / goal) }
}

/* ---- Daily heart rate ---- */

var HR_WINDOW_MINUTES = 120           // aapt.java:27-32
var HR_BUCKET_MINUTES = 3
var HR_BUCKETS = HR_WINDOW_MINUTES / HR_BUCKET_MINUTES

/* The line of the chart: the buckets that have a mean (> 0) as points in a w x h box, the lowest mean at the bottom;
 * all means equal: the middle. Also the index of the highest and the lowest (the first one of equals). */
function chartPoints(values, w, h) {
    var n = values.length
    var pts = []
    var lo = 0, hi = 0, first = true
    var i
    for (i = 0; i < n; i++) {
        var v = Number(values[i])
        if (!(v > 0))
            continue
        if (first) { lo = hi = v; first = false } else { lo = Math.min(lo, v); hi = Math.max(hi, v) }
    }
    var maxAt = -1, minAt = -1
    for (i = 0; i < n; i++) {
        var u = Number(values[i])
        if (!(u > 0))
            continue
        var p = { index: i, value: u, x: n > 1 ? w * i / (n - 1) : w / 2, y: hi > lo ? h * (1 - (u - lo) / (hi - lo)) : h / 2 }
        pts.push(p)
        if (maxAt < 0 && u === hi)
            maxAt = pts.length - 1
        if (minAt < 0 && u === lo)
            minAt = pts.length - 1
    }
    return { points: pts, maxAt: maxAt, minAt: minAt, min: lo, max: hi }
}

/* a live reading counts when it is a pulse (0 is no contact) */
function liveBpm(bpm) {
    var v = Math.round(Number(bpm))
    return v >= 25 && v <= 250 ? v : 0
}

/* ---- Sleep ---- */

/* '7h 31m', '8h', '45m' */
function durationText(min) {
    min = Math.max(0, Math.round(min))
    var h = Math.floor(min / 60), m = min % 60
    if (h > 0 && m > 0)
        //% "%1h %2m"
        return qsTrId("id-tile-solar-hm").replace("%1", h).replace("%2", m)
    if (h > 0)
        //% "%1h"
        return qsTrId("id-tile-solar-h").replace("%1", h)
    //% "%1m"
    return qsTrId("id-tile-solar-m").replace("%1", m)
}

/* What the Sleep tile shows of the last night (SleepDataLoader.lastNight()): the time asleep, bedtime and wake
 * time, the ring towards the sleep goal (0 to 1), "Nx" when the goal is at least doubled (aarf.java:h), the score
 * (-1: none). */
function sleepSummary(night) {
    if (!night || night.valid !== true || !night.main)
        return { valid: false }
    var m = night.main
    var asleep = Number(m.asleepMin) || 0
    var goal = Number(night.goalMin) > 0 ? Number(night.goalMin) : 480
    var ratio = asleep / goal
    var score = Number(night.score)
    return {
        valid: true,
        asleepMin: asleep,
        bed: new Date(Number(m.startMs)),
        wake: new Date(Number(m.endMs)),
        goalMin: goal,
        ring: Math.max(0, Math.min(1, ratio)),
        times: ratio >= 2 ? Math.floor(ratio) : 0,
        score: isFinite(score) && score > 0 ? Math.round(score) : -1
    }
}

/* ---- Exercise quick start ---- */

var EXERCISE_SHOWN = 3                // PW2 (192 dp): 3 buttons; a 225 dp screen or taller shows 6 (aapr.java)
var EXERCISE_DEFAULT = ["Run", "Hike", "Bike", "Walk", "Weights", "Canoeing"]

/* the keys of the buttons: the app's recent list (dconf /org/asteroidos/exercise/recent, newest first, comma
 * separated), unknown keys and repeats dropped, the app's default six when there is no history; `known` tells
 * whether a key is an exercise type; n = how many buttons the screen has */
function exerciseKeys(recent, known, n) {
    var out = []
    var parts = String(recent || "").split(",")
    for (var i = 0; i < parts.length && out.length < n; i++) {
        var k = parts[i].trim()
        if (k !== "" && known(k) && out.indexOf(k) < 0)
            out.push(k)
    }
    if (out.length === 0) {
        for (var j = 0; j < EXERCISE_DEFAULT.length && out.length < n; j++)
            if (known(EXERCISE_DEFAULT[j]))
                out.push(EXERCISE_DEFAULT[j])
    }
    return out
}

/* the request the Exercise app reads ('<type>@<ms>'): the tile's tap starts that type */
function exerciseRequest(key, nowMs) {
    return key + "@" + nowMs
}

/* ---- Maps ---- */

/* The saved place with the name Home or Work (asteroid-map's /map/waypointList: [icon, [lat, lon], colour, name,
 * date] each); null when there is none. The name is compared without case and spaces at the ends. */
function savedPlace(listJson, name) {
    var list
    try { list = JSON.parse(listJson) } catch (e) { return null }
    if (!Array.isArray(list))
        return null
    var want = String(name).trim().toLowerCase()
    for (var i = 0; i < list.length; i++) {
        var w = list[i]
        if (w && w[1] && String(w[3]).trim().toLowerCase() === want && isFinite(Number(w[1][0])) && isFinite(Number(w[1][1])))
            return { lat: Number(w[1][0]), lon: Number(w[1][1]), name: String(w[3]) }
    }
    return null
}

/* ---- Favorites and Contact ---- */

/* the starred contacts, in the list's order, at most n (ContactsLink.contacts: { key, name, starred, photo }) */
function favorites(contacts, n) {
    var out = []
    for (var i = 0; i < contacts.length && out.length < n; i++)
        if (contacts[i].starred)
            out.push(contacts[i])
    return out
}

/* the chosen contact of the Contact tile (dconf /org/asteroidos/launcher/tile-contact, JSON { k, n, p }); null when
 * none is chosen */
function chosenContact(json) {
    var o
    try { o = JSON.parse(json) } catch (e) { return null }
    if (!o || typeof o.k !== "string" || o.k === "" || typeof o.n !== "string")
        return null
    return { key: o.k, name: o.n, photo: o.p === 1 || o.p === true }
}

/* the polygon of the Quick Add tile's shape: a circle of radius r whose edge swells in `lobes` rounded lobes by
 * `depth` (the 12 lobed scallop of add_tile.png); a flat list of x, y pairs around (cx, cy) */
function scallop(cx, cy, r, lobes, depth, steps) {
    var out = []
    for (var i = 0; i < steps; i++) {
        var a = 2 * Math.PI * i / steps
        var rr = r - depth + depth * (0.5 + 0.5 * Math.cos(lobes * a))
        out.push(cx + rr * Math.cos(a), cy + rr * Math.sin(a))
    }
    return out
}
