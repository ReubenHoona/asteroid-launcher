/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the screen lock (W3-launcher-a11y-security) as pure functions
 * and constants, so that every number of the audit is a test assertion
 * (tst_lock.qml). Stock CP3A SysUI keyguard (audit accessibility-lock-security):
 *   -03 PIN pad          PinPadController, PinPadEditView, NumPadKt,
 *                        VALUES.tsv systemui pin_pad_m3_*
 *   -04 look and motion  KeyguardViewController (handleInputOnRootView),
 *                        KeyguardInAndOutAnimationController,
 *                        config_keyguardHoldingDurationMs 1500
 *   -05 wrong PIN        PinEntryListener.onRejected, UnlockAttemptDialog
 *   -06 off wrist        KeyguardOffBodyLockState (UNLOCK_GRACE_PERIOD_MS 5000)
 *   -08 pattern          ChooseLockPattern, LockPatternListener
 *   -10 bootup lock      BootupLockscreenContainer, bootup_lock_screen_v2.xml
 *   -23 launch toast     KeyguardService.handleDismissKeyguard
 */

/* ---- when the bouncer shows (gap -04) ---------------------------------- */

// config_keyguardHoldingDurationMs: untouched, the bouncer comes 1500 ms after the wake
// (not while Touch lock is on)
var AUTO_BOUNCER_MS = 1500
// any tap, key or crown press shows it; a second request within 500 ms is ignored
var INPUT_DEBOUNCE_MS = 500
// the locked layer over the face fades in over 500 ms
var LAYER_FADE_MS = 500

// the "launch while locked" toast, 3000 ms (gap -23)
var LAUNCH_TOAST_MS = 3000

// Bouncer in: scale 1.25 -> 1.0 in 300 ms (fast out slow in), alpha 0.1 -> 1 in 225 ms after 75 ms,
// the black backdrop 0 -> 1 in 150 ms, the face zooms out 10 % in 300 ms (fast out extra slow in)
var IN = { scaleFrom: 1.25, scaleMs: 300, alphaFrom: 0.1, alphaMs: 225, alphaDelayMs: 75,
           backdropMs: 150, faceZoom: 0.9, faceMs: 300 }
// Bouncer out: scale 1.0 -> 1.25 in 225 ms, alpha 1 -> 0 in 150 ms, the backdrop and the face's
// zoom back over 450 ms after 150 ms
var OUT = { scaleTo: 1.25, scaleMs: 225, alphaMs: 150, backdropMs: 450, faceMs: 450, delayMs: 150 }

// FastOutSlowIn (0.4, 0, 0.2, 1) and AOSP's FastOutExtraSlowIn (the path
// M0,0 C0.05,0 0.133333,0.06 0.166666,0.4 C0.208333,0.82 0.25,1 1,1) as Easing.BezierSpline
var EASE_FAST_OUT_SLOW_IN = [0.4, 0, 0.2, 1, 1, 1]
var EASE_FAST_OUT_EXTRA_SLOW_IN = [0.05, 0, 0.133333, 0.06, 0.166666, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]

/* ---- the PIN pad (gap -03) ---------------------------------------------- */

// 4 pips of 18 dp, turned -15, -5, 5, 15 degrees, the outer two 3 dp lower; the row's top margin is
// 3.65 % of the height
var PIN_LENGTH = 4
var PIP_SIZE_DP = 18
var PIP_ROTATION = [-15, -5, 5, 15]
var PIP_DROP_DP = [3, 0, 0, 3]
var PIP_MARGIN_TOP = 0.0365
// each pip turns into one of six shapes, shuffled; 83 ms and 333 ms; the reset after a wrong PIN
// is staggered (4 - i) * 50 ms (PinPadEditView.mPinDelay)
var PIP_MORPH_FIRST_MS = 83
var PIP_MORPH_SECOND_MS = 333
function pipResetDelay(i) { return (PIN_LENGTH - i) * 50 }

// The six shapes (original drawings): width and height as a share of the pip, corner radius as a
// share of the shorter side, turn in degrees
var PIP_SHAPES = [
    { w: 1.0,  h: 1.0,  r: 0.5,  rot: 0 },    // circle
    { w: 0.9,  h: 0.9,  r: 0.28, rot: 0 },    // rounded square
    { w: 0.9,  h: 0.9,  r: 0.28, rot: 45 },   // diamond
    { w: 1.0,  h: 0.7,  r: 0.5,  rot: 0 },    // pill
    { w: 0.7,  h: 1.0,  r: 0.5,  rot: 0 },    // tall pill
    { w: 0.95, h: 0.95, r: 0.38, rot: 22 }    // turned squircle
]

/* A shuffle of 0..5 (Fisher-Yates); rnd() is Math.random in use, a fixed sequence in tests. */
function shapeOrder(rnd) {
    var a = []
    for (var i = 0; i < PIP_SHAPES.length; i++)
        a.push(i)
    for (var j = a.length - 1; j > 0; j--) {
        var k = Math.floor(rnd() * (j + 1))
        var t = a[j]; a[j] = a[k]; a[k] = t
    }
    return a
}

// the numpad: 4 x 3, "1 2 3 / 4 5 6 / 7 8 9 / backspace 0 enter"; the enter key is hidden (auto submit)
var KEYS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "back", "0", "enter"]
var SIDE_PADDING = 0.064      // pin_pad_m3_horizontal_padding_percent
var TOP_PADDING = 0.04        // pin_pad_m3_top_padding_percent
var BOTTOM_PADDING = 0.037    // pin_pad_m3_bottom_padding_percent
var GROUP_SPACING_DP = 10
var DIGIT_SP = 30
var DIGIT_LINE_SP = 34
var DIGIT_WEIGHT = 500
var DIGIT_WEIGHT_PRESSED = 700
var PRESSED_RADIUS_DP = 12
var ICON_PRESSED_SCALE = 1.16

/* The pad's geometry for a w x h box and `dp` pixels per dp: the pips' row, the buttons' size and
 * the position of each cell. Rows and columns are spaced by 10 dp; the buttons are circles as big
 * as the room allows. */
function padMetrics(w, h, dp) {
    var side = SIDE_PADDING * w
    var gap = GROUP_SPACING_DP * dp
    var pip = PIP_SIZE_DP * dp
    var pipY = PIP_MARGIN_TOP * h
    var gridTop = pipY + pip + 3 * dp + TOP_PADDING * h
    var gridBottom = h - BOTTOM_PADDING * h
    var cellW = (w - 2 * side - 2 * gap) / 3
    var cellH = (gridBottom - gridTop - 3 * gap) / 4
    var cell = Math.min(cellW, cellH)
    var totalW = 3 * cell + 2 * gap
    var left = (w - totalW) / 2
    var cells = []
    for (var i = 0; i < 12; i++) {
        var r = Math.floor(i / 3), c = i % 3
        cells.push({ key: KEYS[i], x: left + c * (cell + gap), y: gridTop + r * (cell + gap), size: cell })
    }
    return { side: side, gap: gap, pip: pip, pipY: pipY, gridTop: gridTop, gridBottom: gridBottom, cell: cell, cells: cells }
}

/* What a key does to the entry: returns { entry, submit }. Digits add up to 4 (a fifth is refused)
 * and the fourth submits; back removes one; enter submits a full entry (it is hidden). */
function pressKey(entry, key) {
    if (key === "back")
        return { entry: entry.slice(0, -1), submit: false }
    if (key === "enter")
        return { entry: entry, submit: entry.length === PIN_LENGTH }
    if (key.length === 1 && key >= "0" && key <= "9" && entry.length < PIN_LENGTH) {
        var e = entry + key
        return { entry: e, submit: e.length === PIN_LENGTH }
    }
    return { entry: entry, submit: false }
}

/* ---- the pattern (gap -08) ----------------------------------------------- */

var PATTERN_MIN_DOTS = 4
// the pattern's padding is 19 % of the width; a wrong pattern shows red for 2000 ms; the padlock's top margin is 5 dp
var PATTERN_PADDING = 0.19
var PATTERN_ERROR_MS = 2000
var PATTERN_LOCK_TOP_DP = 5

/* The dots a straight line from dot a to dot b crosses (3 x 3, numbered 0..8 row by row): the one
 * between is part of the pattern as on Android (0 to 2 takes 1 as well). */
function between(a, b) {
    var ar = Math.floor(a / 3), ac = a % 3, br = Math.floor(b / 3), bc = b % 3
    var dr = Math.abs(ar - br), dc = Math.abs(ac - bc)
    // only a step of two in a row or column (or both) has a dot in the middle
    if (dr % 2 === 0 && dc % 2 === 0 && (dr === 2 || dc === 2))
        return ((ar + br) / 2) * 3 + (ac + bc) / 2
    return -1
}

/* Add dot d to a pattern ([dot numbers]); returns the new pattern, with a skipped dot in between. */
function addDot(pattern, d) {
    if (pattern.indexOf(d) >= 0)
        return pattern
    var p = pattern.slice()
    if (p.length > 0) {
        var m = between(p[p.length - 1], d)
        if (m >= 0 && p.indexOf(m) < 0)
            p.push(m)
    }
    p.push(d)
    return p
}

function patternString(pattern) { return pattern.join("") }

/* ---- wrong tries and the wait (gap -05) ---------------------------------- */

/* The wait's words for `ms` left, rounded up to whole seconds: stock screen_lock_try_again_*.
 * kind: "seconds" (Try again in %1 sec), "minutes" (%1 min %2 sec), "hours" (%1 hr %2 min), "day"
 * (Try again in 24 hr). a, b the numbers. */
function waitParts(ms) {
    var s = Math.max(0, Math.ceil(ms / 1000))
    if (s >= 24 * 3600)
        return { kind: "day", a: 24, b: 0 }
    if (s >= 3600) {
        var h = Math.floor(s / 3600)
        var m = Math.ceil((s % 3600) / 60)
        if (m === 60) { h++; m = 0 }
        return { kind: "hours", a: h, b: m }
    }
    if (s >= 60)
        return { kind: "minutes", a: Math.floor(s / 60), b: s % 60 }
    return { kind: "seconds", a: s, b: 0 }
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

/* The English text of waitParts (the QML takes the words from the catalogue and the numbers from here). */
function waitText(ms) {
    var p = waitParts(ms)
    switch (p.kind) {
    case "day": return "Try again in 24 hr"
    case "hours": return "Try again in " + p.a + " hr " + pad2(p.b) + " min"
    case "minutes": return "Try again in " + p.a + " min " + pad2(p.b) + " sec"
    default: return "Try again in " + p.a + " sec"
    }
}

/* ---- off the wrist (gap -06) --------------------------------------------- */

// more than 5 s after the last unlock the screen goes off at once as well (UNLOCK_GRACE_PERIOD_MS)
var UNLOCK_GRACE_MS = 5000

/* What the off-body sensor's change does. state: 0 on the wrist, 1 off the wrist, -1 unknown; the
 * watch must be unlocked with a credential set. unlockedAt: when it was last unlocked (ms); now.
 * Answers none, lock, lockAndOff. */
function offBodyAction(state, secured, locked, unlockedAt, now) {
    if (state !== 1 || !secured || locked)
        return "none"
    return now - unlockedAt > UNLOCK_GRACE_MS ? "lockAndOff" : "lock"
}

/* ---- the boot lock screen (gap -10) -------------------------------------- */

// a filled 80 dp badge with a 2 px outline, a 36 dp lock icon, "Unlock" below it (146 dp wide,
// 4 dp gap), it fades out in 300 ms
var BOOT = { badgeDp: 80, outlinePx: 2, iconDp: 36, titleWidthDp: 146, gapDp: 4, fadeMs: 300 }
