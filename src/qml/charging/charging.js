/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The charging screen's rules and numbers (W2-launcher-charging), as pure
 * functions so that every number is a test assertion (tests tst_charging.qml).
 * Stock = Pixel Watch 2, CP3A SysUI ChargingComposeActivity (ini.java, ilj/ill/
 * ilo/ilm/iln, evf, hxe, msa, back_charging_intro_bolt.json). Units: dp on a
 * 192 dp screen (1 dp = 2 px on eos); times in ms.
 *
 * Nothing here runs by itself: no timer, no polling. The screen's animations
 * are driven by the display being on (ChargingScreen.qml). */

/* ---- the numbers of the layout (charging-battery-01) --------------------- */

var LAYOUT = {
    ringStrokeDp: 8,            // ini.java:2190-2272 (ring), full circle
    ringInsetDp: 2,
    ringGapDp: 8 / 3,           // stroke / 3 on each side of the indicator
    ringAlpha: 0.8,             // indicator primaryDim at 80 %
    percentTopDp: 14,           // '82%' top centre 14 dp from the top, arcSmall 14 sp
    boltDp: 24,                 // ic_power at 24 dp
    boltGapDp: 6,               // 6 dp above the clock (ini.java:2697)
    pillWidthSub: 0.1666,       // (192 - 192 * 0.1666 - 4) / 2 = 78 dp (ini.java:2257)
    pillHeightFraction: 0.3646, // of the screen height: 70 dp (ini.java:2257)
    pillGapDp: 4,
    hoursCornerDp: 40,          // wider than half of 70: a stadium
    minutesCornerDp: 18,
    chipPadXDp: 8,
    chipPadYDp: 6,
    chipIconDp: 16,
    chipIconGapDp: 8,
    chipGapDp: 6,               // pills to chip (inferred)
    unreadBottomDp: 12,         // the dot 12 dp above the bottom
    unreadDp: 8                 // (inferred)
}

// the width of one pill on a screen of this many dp (ini.java:2257)
function pillWidthDp(screenWidthDp) {
    return (screenWidthDp - screenWidthDp * LAYOUT.pillWidthSub - LAYOUT.pillGapDp) / 2
}
function pillHeightDp(screenHeightDp) {
    return screenHeightDp * LAYOUT.pillHeightFraction
}

/* ---- level, colours (charging-battery-08) -------------------------------- */

var LOW_LEVEL = 15

// the level the screen shows: whole, 0..100 (unknown shows 0)
function clampLevel(p) {
    var n = Math.round(Number(p))
    if (isNaN(n) || n < 0)
        return 0
    return n > 100 ? 100 : n
}

// <= 15 % turns the screen red (ini.java:676-698, 1755-1760)
function isLow(level) {
    return clampLevel(level) <= LOW_LEVEL
}

/* The colour roles of each element, by role name and alpha (Theme.color.<role>):
 * ring indicator, ring track, pill, digits, chip, chip text, percentage, bolt.
 * ini.java:1982-1990, 2190-2272, 2690-2700; grw.java:256-300. */
function roles(low) {
    if (low)
        return {
            ring: ["errorDim", 0.8], track: ["error", 0.48],
            pill: ["onError", 1], digit: ["errorDim", 1],
            chip: ["onError", 1], chipText: ["errorDim", 1],
            percent: ["onBackground", 0.8], bolt: ["onBackground", 0.8]
        }
    return {
        ring: ["primaryDim", 0.8], track: ["surfaceContainerLow", 1],
        pill: ["surfaceContainerLow", 1], digit: ["onSurfaceVariant", 1],
        chip: ["surfaceContainer", 1], chipText: ["primary", 1],
        percent: ["onBackground", 1], bolt: ["onBackground", 1]
    }
}
// the change between the two sets: 300 ms (the 'chargingLowBatteryTransition')
var COLOR_MS = 300
// the bolt of the intro: primaryDim at 80 % (error dim when low), then the bolt's own role
function introBoltRole(low) {
    return low ? ["errorDim", 0.8] : ["primaryDim", 0.8]
}

/* ---- the clock and the chip (charging-battery-01) ------------------------- */

function pad2(n) { return (n < 10 ? "0" : "") + n }

/* 'hh' (12 h, zero padded, no AM/PM) or 'HH', and 'mm' */
function clockParts(d, use12h) {
    var h = d.getHours()
    if (use12h)
        h = h % 12 === 0 ? 12 : h % 12
    return { hours: pad2(h), minutes: pad2(d.getMinutes()) }
}

// the next alarm shows in the chip when it rings within 24 h (and has not rung)
var ALARM_WINDOW_MS = 24 * 3600 * 1000
function alarmShown(nowMs, alarmMs) {
    return alarmMs > nowMs && alarmMs - nowMs <= ALARM_WINDOW_MS
}

/* The alarm's time as the 'hmm' / 'HHmm' skeletons give it in English: 'h:mm AM',
 * 'HH:mm'. am and pm: the locale's words. */
function alarmText(d, use12h, am, pm) {
    var h = d.getHours()
    if (!use12h)
        return pad2(h) + ":" + pad2(d.getMinutes())
    return (h % 12 === 0 ? 12 : h % 12) + ":" + pad2(d.getMinutes()) + " " + (h < 12 ? am : pm)
}
// the date 'EEE d': the short weekday (the locale's, index 0 = Sunday) and the day
function dateText(d, shortDays) {
    return shortDays[d.getDay()] + " " + d.getDate()
}
/* What the chip says: { kind: "alarm" | "date", text } */
function chip(now, alarmMs, use12h, am, pm, shortDays) {
    if (alarmShown(now.getTime(), alarmMs))
        return { kind: "alarm", text: alarmText(new Date(alarmMs), use12h, am, pm) }
    return { kind: "date", text: dateText(now, shortDays) }
}

/* ---- motion: curves and springs ------------------------------------------- */

/* cubic-bezier(x1, y1, x2, y2) evaluated at x (CSS timing function) */
function bezier(x1, y1, x2, y2, x) {
    if (x <= 0)
        return 0
    if (x >= 1)
        return 1
    function bx(t) { return 3 * x1 * t * (1 - t) * (1 - t) + 3 * x2 * t * t * (1 - t) + t * t * t }
    function by(t) { return 3 * y1 * t * (1 - t) * (1 - t) + 3 * y2 * t * t * (1 - t) + t * t * t }
    var lo = 0, hi = 1
    for (var i = 0; i < 40; i++) {
        var m = (lo + hi) / 2
        if (bx(m) < x) lo = m; else hi = m
    }
    return by((lo + hi) / 2)
}

/* A critically damped spring (damping ratio 1.0) of this stiffness from rest to
 * 1, t ms after it started: 1 - (1 + w t) e^(-w t), w = sqrt(k) (Motion.qml). */
function springAt(t, stiffness) {
    if (t <= 0)
        return 0
    var wt = Math.sqrt(stiffness) * t / 1000
    return 1 - (1 + wt) * Math.exp(-wt)
}
// how long it takes to come within `1 - fraction` of the end
function springSettle(stiffness, fraction) {
    var lo = 0, hi = 60
    for (var i = 0; i < 60; i++) {
        var m = (lo + hi) / 2
        if ((1 + m) * Math.exp(-m) > 1 - fraction) lo = m; else hi = m
    }
    return Math.ceil(1000 * lo / Math.sqrt(stiffness))
}

/* ---- the intro, on the plug-in only (charging-battery-06) ---------------- */

/* msa.java:33-37, back_charging_intro_bolt.json (60 fps, 60 frames, 204 px canvas), ilj/ill/ilo/ilm/iln,
 * ini.java:778-793, 871-874. Times are ms from the start of the intro. */
var INTRO = {
    // 1) the bolt (our own glyph, not the Lottie file)
    // the Lottie bolt is 64 px tall at the end (60 px art at 106 %); our glyph is 20/24 of its box,
    // so the box is 72 px at scale 1 (inferred from the art's size, not copied)
    boltBoxPx: 72,
    scaleFrom: 283.333 / 100, scaleTo: 106.25 / 100, scaleMs: 1000,
    scaleCurve: [0.094, 0.497, 0.342, 1],
    traceMs: 500, traceCurve: [0.001, 0.001, 0.18, 1],
    strokeFromPx: 2.5, strokeStart: 167, strokeEnd: 500, strokeCurve: [0.755, 0, 0.55, 1],
    fillStart: 167, fillEnd: 500, fillCurve: [0.309, 0, 0.2, 1],
    outlineFadeStart: 267, outlineFadeEnd: 583, outlineFadeCurve: [0.48, 0, 0, 1],
    // 2) the ring, the percentage; 3) the bolt moves into place; 4) clock and chip rise; 5) the dot
    ringAt: 1000,
    ringStiffness: 75, ringScaleStiffness: 1400,
    ringScaleFrom: 0.9, ringRotationFrom: -90,
    percentFadeStiffness: 260,
    boltMoveStiffness: 500,
    riseDp: 24, riseStiffness: 500, riseFadeStiffness: 260,
    clockDelay: 50, chipDelay: 100, dotDelay: 150
}
// the intro is over when its slowest spring is within 0.1 % of its end
var INTRO_END = INTRO.ringAt + Math.max(springSettle(INTRO.ringStiffness, 0.999),
                                        INTRO.chipDelay + springSettle(INTRO.riseFadeStiffness, 0.999),
                                        INTRO.dotDelay + springSettle(INTRO.riseFadeStiffness, 0.999))

function curve(c, x) { return bezier(c[0], c[1], c[2], c[3], x) }
function span(t, a, b) { return b > a ? Math.max(0, Math.min(1, (t - a) / (b - a))) : (t >= b ? 1 : 0) }

/* Everything the intro changes, at time t ms: pure, so a test reads any moment */
function introAt(t) {
    var I = INTRO
    var since = t - I.ringAt
    var ring = since > 0 ? springAt(since, I.ringStiffness) : 0
    return {
        // the bolt of the Lottie: how much of the outline is drawn (both halves), the outline's
        // stroke (px of the canvas), the fill and the outline's alpha, the scale of the whole
        trace: curve(I.traceCurve, span(t, 0, I.traceMs)),
        stroke: I.strokeFromPx * (1 - curve(I.strokeCurve, span(t, I.strokeStart, I.strokeEnd))),
        fill: curve(I.fillCurve, span(t, I.fillStart, I.fillEnd)),
        outline: 1 - curve(I.outlineFadeCurve, span(t, I.outlineFadeStart, I.outlineFadeEnd)),
        boltScale: I.scaleFrom + (I.scaleTo - I.scaleFrom) * curve(I.scaleCurve, span(t, 0, I.scaleMs)),
        // the ring: progress 0 -> level and rotation -90 -> 0 on the slow spring (1.0, 75), the
        // scale 0.9 -> 1 on 1.0 / 1400, the percentage fades in
        ring: ring,
        ringRotation: I.ringRotationFrom * (1 - ring),
        ringScale: I.ringScaleFrom + (1 - I.ringScaleFrom) * (since > 0 ? springAt(since, I.ringScaleStiffness) : 0),
        percent: since > 0 ? springAt(since, I.percentFadeStiffness) : 0,
        // the bolt moves to its place (the Lottie's centre -> 24 dp above the clock), scales to
        // 24 dp and recolours: one progress on the default spring
        boltMove: since > 0 ? springAt(since, I.boltMoveStiffness) : 0,
        // the clock, the chip: rise 24 dp (1.0 / 500) and fade (1.0 / 260), staggered
        clockRise: since - I.clockDelay > 0 ? springAt(since - I.clockDelay, I.riseStiffness) : 0,
        clockFade: since - I.clockDelay > 0 ? springAt(since - I.clockDelay, I.riseFadeStiffness) : 0,
        chipRise: since - I.chipDelay > 0 ? springAt(since - I.chipDelay, I.riseStiffness) : 0,
        chipFade: since - I.chipDelay > 0 ? springAt(since - I.chipDelay, I.riseFadeStiffness) : 0,
        dot: since - I.dotDelay > 0 ? springAt(since - I.dotDelay, I.riseFadeStiffness) : 0
    }
}

/* ---- the bolt pulse (charging-battery-07) -------------------------------- */

/* evf.java:199-210, hxe.java:61-69: alpha 1.0 at 0, 1.0 at 1000, 0.3 at 2000, 1.0 at 3000 ms,
 * each ramp on cubic-bezier(0.2, 0, 0, 1); loops while the level is below 100 %. */
var PULSE = { loopMs: 3000, holdMs: 1000, low: 0.3, curve: [0.2, 0, 0, 1] }

function pulseAlpha(t) {
    var p = PULSE
    var x = ((t % p.loopMs) + p.loopMs) % p.loopMs
    if (x <= p.holdMs)
        return 1
    if (x <= 2 * p.holdMs)
        return 1 - (1 - p.low) * bezier(p.curve[0], p.curve[1], p.curve[2], p.curve[3], (x - p.holdMs) / p.holdMs)
    return p.low + (1 - p.low) * bezier(p.curve[0], p.curve[1], p.curve[2], p.curve[3], (x - 2 * p.holdMs) / p.holdMs)
}
// the pulse runs after a plug-in launch while the level is below 100 %, drawn on the awake screen only
function pulseRuns(level, awake, shown) {
    return shown === true && awake === true && clampLevel(level) < 100
}

/* ---- plug, unplug, relaunch (charging-battery-02, -03) -------------------- */

/* PowerManagerService.java:5701-5704 (config_unplugTurnsOnScreen = true,
 * config_allowTheaterModeWakeFromUnplug = false), ikd.java, ikx.java:68-83. */
var UNPLUG_HOLD_MS = 1000       // ChargingComposeActivity: wait 1000 ms, then finish
var FADE_STIFFNESS = 260        // the slow effects spring of the fade away

/* The screen wakes on a plug or unplug, except in Theater (stock) and Bedtime
 * (the screen stays dark: inferred, as Theater). */
function wakesOnPlug(theater, bedtime) {
    return !(theater === true || bedtime === true)
}

/* What a change of the charger does. s: { plugged (now), was (before), theater, bedtime, dnd,
 * displayOff }. Answer: { show, wake, intro, linger, hide, feedback }
 *   plug-in:  the screen is up; wake the display (normal timers) unless Theater/Bedtime;
 *             the intro plays when the display is on (or comes on); the plug-in vibration (ngfd
 *             charging_started, which lipstick's 'Charging' banner used to carry) unless Do Not
 *             Disturb, Bedtime or Theater is on (gap charging-battery-11)
 *   unplug:   wake the same way; the screen stays UNPLUG_HOLD_MS, then fades away; with the
 *             display dark it goes at once
 *   no change: nothing */
function plugChange(s) {
    var r = { show: false, wake: false, intro: false, linger: false, hide: false, feedback: false }
    if (s.plugged === s.was)
        return r
    var wake = wakesOnPlug(s.theater, s.bedtime)
    if (s.plugged) {
        r.show = true
        r.wake = wake
        r.intro = wake || s.displayOff !== true
        r.feedback = wake && s.dnd !== true
        return r
    }
    r.wake = wake
    if (wake || s.displayOff !== true)
        r.linger = true
    else
        r.hide = true
    return r
}

/* Whether the screen is up. plugged, dismissed (the crown closed it until the next screen off),
 * lingering (the unplug's 1 s). */
function screenUp(plugged, dismissed, lingering) {
    return (plugged && !dismissed) || lingering
}

/* ---- the charging quality screen (app-inventory-03) ------------------------ */

/* ChargingQualityActivity, mtr/mts/mtt (texts and icons), mui.java:19-21 (65 s), mte.java:14 (30 s) */
var PROBLEM = {
    misalignedAfterMs: 30000,   // the stock constant next to the activity; inferred use
    moistureRecheckMs: 65000,
    iconDp: 24,
    texts: {
        misaligned: "Check if charger is aligned and has power",
        moisture: "Dry watch and charger, wait 1 min for charging to resume",
        unsupported: "Unsupported charger"
    },
    icons: { misaligned: "charger", moisture: "drop", unsupported: "warning" }
}
function problemText(kind) { return PROBLEM.texts[kind] || "" }

/* The misaligned rule: a charger is connected, the battery is not full, and
 * charging has not started. s: { plugged, charging, full }. Armed on the awake
 * screen only. */
function misaligned(s) {
    return s.plugged === true && s.charging === false && s.full !== true
}

/* ---- the bolt glyph (our own, in a 24 x 24 box, 20 tall as ic_power) ------ */

var BOLT = {
    box: 24,
    // top, left, left notch, bottom tip, right, right notch (clockwise from the top)
    points: [[13, 2], [6.5, 13], [11, 13], [10, 22], [17.5, 10], [13, 10]]
}
// the outline traced from the top to the bottom tip, both ways round
function boltHalves() {
    var p = BOLT.points
    return { a: [p[0], p[1], p[2], p[3]], b: [p[0], p[5], p[4], p[3]] }
}
function boltClosed() {
    var out = []
    for (var i = 0; i < BOLT.points.length; i++)
        out.push({ x: BOLT.points[i][0], y: BOLT.points[i][1] })
    out.push({ x: BOLT.points[0][0], y: BOLT.points[0][1] })
    return out
}
// the first `f` (0..1) of a polyline's length, as a list of {x, y}
function partial(pts, f) {
    var total = 0, i
    for (i = 1; i < pts.length; i++)
        total += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
    var want = total * Math.max(0, Math.min(1, f))
    var out = [{ x: pts[0][0], y: pts[0][1] }]
    var done = 0
    for (i = 1; i < pts.length && want > 0; i++) {
        var len = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
        if (done + len <= want + 1e-9) {
            out.push({ x: pts[i][0], y: pts[i][1] })
            done += len
        } else {
            var k = (want - done) / len
            out.push({ x: pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * k, y: pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * k })
            break
        }
    }
    return out
}
