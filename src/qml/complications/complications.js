/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The numbers and the pure rules of the watch face complications, kept out
 * of the QML so the tests can run them on a fixed clock: the bulb's
 * geometry (stock rwf fwq/fwp/fwi), the text of the stock providers (next
 * event, battery, weather, UV, rain, air quality, sun, moon, clock) and the
 * astronomy for the sun and the moon (no network, no timer).
 * Everything here is a function of its arguments.
 */

// ---- the round (bulb) slot, in px of an 86 px bulb (rwf fwq.java, fwp.java, fwi.java) ----
var BULB = 86
var RING_STROKE = 8          // borderWidth 4 units
var RING_ICON = 24           // centerIcon 12 units
var RING_ICON_Y = 74         // iconYPositionOffset 37 units: the icon's middle
var DOT = 18                 // scoreIndicatorSize 9 units
var DOT_STROKE = 4           // scoreIndicatorStrokeWidth 2 units
var DISC_ICON = 20           // iconWidthFillStyle 10 units
var DISC_ALPHA = 30 / 255    // brz.d(colour, 30)
var DATE_ICON = 20
var TITLE_SIZE = 24          // titleTextSize 12 units
var TEXT_WIDTH = 80          // textBoxWidth 40 units

// the gap at 6 o'clock when an icon is shown: T() = 2 * (90 - asin(40 / 21.5 - 1))
function gapAngle() {
    return 2 * (90 - Math.asin(40 / 21.5 - 1) * 180 / Math.PI)
}
// Qt's PathAngleArc: 0 = 3 o'clock, clockwise. Stock V() = T() / 2 + 90
function ringStart(withGap) { return withGap ? gapAngle() / 2 + 90 : 90 }
function ringSweep(withGap) { return withGap ? 360 - gapAngle() : 360 }
// where the progress ends, degrees (the end dot sits there)
function progressEnd(withGap, progress) {
    return ringStart(withGap) + ringSweep(withGap) * clamp01(progress)
}
// the value's text size in px of an 86 px bulb, by its length (fwq map y)
function valueSize(len) {
    if (len <= 3) return 28
    if (len === 4) return 22
    if (len === 5) return 18
    if (len === 6) return 16
    return 14
}
function clamp01(x) { return Math.max(0, Math.min(1, x)) }

// ---- the other shapes ----
var LINE = { width: 188, height: 28, fontRatio: 26 / 28, marginX: 48, marginY: 10 }
var LONG = { width: 280, height: 100, text: 26, line: 33.3, icon: 28, gap: 14 }
var ARC = { radius: 170, stroke: 12, icon: 24, text: 24, edge: 3, dotRadius: 6, dotRing: 10 }

// ---- text helpers ----
function pad2(n) { return (n < 10 ? "0" : "") + n }
function upper(s) { return String(s).toUpperCase() }

// "9:00 am" / "21:00" (stock: the clock's time, lower-case marker)
function fmtTime(d, use12h) {
    var h = d.getHours(), m = d.getMinutes()
    if (!use12h)
        return pad2(h) + ":" + pad2(m)
    return ((h % 12) || 12) + ":" + pad2(m) + " " + (h < 12 ? "am" : "pm")
}
// the time without its marker, and the marker, for a bulb ("7:25" over "pm")
function timeParts(d, use12h) {
    var h = d.getHours(), m = d.getMinutes()
    if (!use12h)
        return { time: pad2(h) + ":" + pad2(m), marker: "" }
    return { time: ((h % 12) || 12) + ":" + pad2(m), marker: h < 12 ? "am" : "pm" }
}
function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
function startOfDay(d, plusDays) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (plusDays || 0))
}
// "2h5m" / "45m" / "Now" (weather complication_solar_*)
function leftShort(ms) {
    var mins = Math.floor(ms / 60000)
    if (mins <= 0) return "Now"
    var h = Math.floor(mins / 60), m = mins % 60
    if (h === 0) return m + "m"
    if (m === 0) return h + "h"
    return h + "h" + m + "m"
}
// m:ss, or h:mm:ss from an hour
function clockText(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60
    return h > 0 ? h + ":" + pad2(m) + ":" + pad2(ss) : m + ":" + pad2(ss)
}

// ---- the next event (calendar NextEventComplicationService, 24 h look-ahead) ----
// ev: { start: Date, end: Date, title, allDay }, or null.
// Returns { kind: none | now | soon | later, short, long, title } where title is the first
// line of a long slot (the time range, or 'Now') and long its second (the event title).
// The caller passes the translated words in w: none, noEvents, now, today, tomorrow, inMinutes ("in %1 min")
function eventText(now, ev, use12h, w) {
    if (!ev)
        return { kind: "none", short: w.none, long: w.noEvents, title: w.noEvents }
    var start = ev.start, end = ev.end
    if (start <= now && now < end)
        return { kind: "now", short: w.now, long: ev.title, title: w.now }
    var mins = Math.ceil((start.getTime() - now.getTime()) / 60000)
    var range = ev.allDay ? (sameDay(start, now) ? w.today : w.tomorrow)
                          : fmtTime(start, use12h) + " - " + fmtTime(end, use12h)
    if (!ev.allDay && mins <= 60)
        return { kind: "soon", short: w.inMinutes.replace("%1", String(Math.max(1, mins))), long: ev.title, title: range }
    var shortLater = ev.allDay ? (sameDay(start, now) ? w.today : w.tomorrow) : fmtTime(start, use12h)
    return { kind: "later", short: shortLater, long: ev.title, title: range }
}
// the next event in a list of occurrences: the first that has not ended and starts within 24 h
function pickNext(now, list) {
    var best = null, limit = now.getTime() + 86400000
    for (var i = 0; i < list.length; i++) {
        var o = list[i]
        if (!o || !(o.end > now) || o.start.getTime() > limit)
            continue
        if (best === null || o.start < best.start)
            best = o
    }
    return best
}

// ---- battery (sysui muk.java) ----
// icon buckets <30 / <50 / <90 / full; the icon set has three battery glyphs (dead, full, charging), so the
// middle buckets share the full one until asteroid-icons-ion draws the steps
function batteryBucket(pc) {
    if (pc < 30) return 0
    if (pc < 50) return 1
    if (pc < 90) return 2
    return 3
}
var BATTERY_ICONS = ["ios-battery-dead", "ios-battery-full", "ios-battery-full", "ios-battery-full"]
function batteryIcon(pc, charging) {
    return charging ? "ios-battery-charging" : BATTERY_ICONS[batteryBucket(pc)]
}

// ---- weather ----
var RAMP = [[0xc4, 0xd3, 0xdb], [0x72, 0xe5, 0xba], [0x65, 0xc9, 0xff]]
// the colour ramp of the current temperature between today's low and high, interpolated
function ramp(t) {
    t = clamp01(t)
    var seg = t * (RAMP.length - 1)
    var i = Math.min(RAMP.length - 2, Math.floor(seg)), f = seg - i
    var a = RAMP[i], b = RAMP[i + 1]
    function c(k) { var v = Math.round(a[k] + (b[k] - a[k]) * f); return (v < 16 ? "0" : "") + v.toString(16) }
    return "#" + c(0) + c(1) + c(2)
}
function degrees(c, fahrenheit) {
    return (fahrenheit ? Math.round(c * 9 / 5 + 32) : Math.round(c)) + "°"
}
// OpenWeatherMap id -> a condition word key
function conditionKey(code) {
    code = Number(code)
    if (code >= 200 && code < 300) return "thunderstorm"
    if (code >= 300 && code < 400) return "drizzle"
    if (code >= 500 && code < 600) return "rain"
    if (code >= 600 && code < 700) return "snow"
    if (code >= 700 && code < 800) return "fog"
    if (code === 800) return "clear"
    if (code === 801 || code === 802) return "partlycloudy"
    if (code === 803 || code === 804) return "cloudy"
    return ""
}
function uvLabel(uv) {
    var i = Math.round(uv)
    return i <= 2 ? "low" : i <= 4 ? "moderate" : i <= 7 ? "high" : "extreme"
}
function precipLabel(pop) {
    if (pop <= 0) return "none"
    if (pop <= 29) return "slight"
    if (pop <= 59) return "chance"
    if (pop <= 79) return "likely"
    return "rain"
}
function aqiLabel(index) {
    return index < 51 ? "good" : index < 101 ? "moderate" : index < 201 ? "unhealthy" : index < 300 ? "veryunhealthy" : "hazardous"
}
// the extended forecast (dconf /org/asteroidos/weather/extended): the object, or null
function parseExtended(s) {
    if (!s)
        return null
    try {
        var o = JSON.parse(String(s))
        return o && o.v === 1 ? o : null
    } catch (e) {
        return null
    }
}
// the day of the forecast with the calendar date of `date`, else null
function dayOf(ext, date) {
    if (!ext || !ext.days)
        return null
    var ymd = date.getFullYear() * 10000 + (date.getMonth() + 1) * 100 + date.getDate()
    for (var i = 0; i < ext.days.length; i++)
        if (ext.days[i].d === ymd)
            return ext.days[i]
    return null
}

// ---- the sun and the moon ----
var J1970 = 2440587.5
function toJulian(ms) { return ms / 86400000 + J1970 }
function fromJulian(j) { return (j - J1970) * 86400000 }
var RAD = Math.PI / 180
// Sunrise and sunset of the calendar day of `date` at latitude lat and longitude lon (degrees,
// east positive), NOAA's sunrise equation. Returns { rise, set } in ms, or { polar: "day"|"night" }
function sunTimes(date, lat, lon) {
    var noon = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 12)
    var lw = -lon
    var n = Math.round(toJulian(noon) - 2451545 + 0.0008 - lw / 360)
    var jstar = n + lw / 360
    var M = (357.5291 + 0.98560028 * jstar) % 360
    var C = 1.9148 * Math.sin(M * RAD) + 0.02 * Math.sin(2 * M * RAD) + 0.0003 * Math.sin(3 * M * RAD)
    var lambda = (M + C + 180 + 102.9372) % 360
    var transit = 2451545 + jstar + 0.0053 * Math.sin(M * RAD) - 0.0069 * Math.sin(2 * lambda * RAD)
    var sinDec = Math.sin(lambda * RAD) * Math.sin(23.4397 * RAD)
    var cosDec = Math.cos(Math.asin(sinDec))
    var cosH = (Math.sin(-0.833 * RAD) - Math.sin(lat * RAD) * sinDec) / (Math.cos(lat * RAD) * cosDec)
    if (cosH > 1)
        return { polar: "night" }
    if (cosH < -1)
        return { polar: "day" }
    var h = Math.acos(cosH) / RAD
    return { rise: fromJulian(transit - h / 360), set: fromJulian(transit + h / 360) }
}
// The next sunrise or sunset after `now` (Date): { rise: bool, at: ms }, or null (polar day or night,
// no location). Uses the forecast's own times for today and tomorrow when it has them
// ({rise, set} in Unix seconds), else the formula at lat, lon (null when the phone's location is unknown).
function nextSun(now, lat, lon, today, tomorrow) {
    var cand = []
    function add(day, d) {
        var t = null
        if (day && day.rise && day.set)
            t = { rise: day.rise * 1000, set: day.set * 1000 }
        else if (lat !== null && lon !== null)
            t = sunTimes(d, lat, lon)
        if (t && t.rise !== undefined) {
            cand.push({ rise: true, at: t.rise })
            cand.push({ rise: false, at: t.set })
        }
    }
    add(today, now)
    add(tomorrow, startOfDay(now, 1))
    cand.sort(function (a, b) { return a.at - b.at })
    for (var i = 0; i < cand.length; i++)
        if (cand[i].at > now.getTime())
            return cand[i]
    return null
}
var SYNODIC = 29.530588853
// the moon's age in days from the new moon, its lit part and the phase 0..7 (new .. waning crescent)
function moonPhase(date) {
    var age = (toJulian(date.getTime()) - 2451550.1) % SYNODIC
    if (age < 0) age += SYNODIC
    var frac = age / SYNODIC
    return { age: age, illumination: (1 - Math.cos(2 * Math.PI * frac)) / 2, phase: Math.floor(frac * 8 + 0.5) % 8 }
}
var MOON_KEYS = ["new", "waxingcrescent", "firstquarter", "waxinggibbous", "full", "waninggibbous", "lastquarter", "waningcrescent"]

// ---- clock ----
// when an alarm (hour, minute, daysOfWeek "mtwTfsS" letters or "", triggerTime s) rings next (ms), 0 off
function nextRing(a, now) {
    if (!a.enabled)
        return 0
    if (a.triggerTime * 1000 > now.getTime())
        return a.triggerTime * 1000
    var codes = "mtwTfsS"
    for (var d = 0; d < 8; d++) {
        var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + d, a.hour, a.minute)
        if (t <= now)
            continue
        if (!a.daysOfWeek || a.daysOfWeek.indexOf(codes[(t.getDay() + 6) % 7]) >= 0)
            return t.getTime()
    }
    return 0
}
// the earliest enabled, non-countdown alarm: ms, 0 none
function nextAlarm(list, now) {
    var best = 0
    for (var i = 0; i < list.length; i++) {
        var a = list[i]
        if (!a || a.countdown)
            continue
        var t = nextRing(a, now)
        if (t && (best === 0 || t < best))
            best = t
    }
    return best
}
// whole days from the day of `now` to the date ymd ("YYYY-MM-DD"), negative past; null if invalid
function daysTo(now, ymd) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(ymd))
    if (!m)
        return null
    var a = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    var b = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate())
    return Math.round((a - b) / 86400000)
}
// a UTC offset ("+0530", "-0800", "0") -> minutes, null if invalid
function offsetMinutes(s) {
    var m = /^([+-]?)(\d{1,2})(\d{2})?$/.exec(String(s))
    if (!m)
        return null
    var v = Number(m[2]) * 60 + Number(m[3] || 0)
    return m[1] === "-" ? -v : v
}
// the wall clock of another zone, as a Date whose local fields show that time
function inOffset(now, minutes) {
    return new Date(now.getTime() + now.getTimezoneOffset() * 60000 + minutes * 60000)
}
// "kind:param" -> { kind, param }
function split(id) {
    var at = String(id).indexOf(":")
    return at < 0 ? { kind: String(id), param: "" } : { kind: String(id).slice(0, at), param: String(id).slice(at + 1) }
}
