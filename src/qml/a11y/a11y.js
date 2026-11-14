/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The accessibility features of the launcher (W3-launcher-a11y-security) as
 * pure functions and constants, so that every number of the audit is a test
 * assertion (tst_a11y.qml). Stock CP3A:
 *   -15 magnification     Settings prefs_magnification.xml,
 *                         MagnificationSettingsFragment, VALUES.tsv android
 *                         config_screen_magnification_multi_tap_adjustment 25,
 *                         accessibility_magnification_indicator_width 4dp
 *   -16 colour correction prefs_color_correction.xml, ColorCorrectionFragment;
 *                         the daltonizer's matrices are android's own
 *                         (SurfaceFlinger Daltonizer; Fidaner et al.'s LMS
 *                         simulation and error shift), not in the decompile
 *   -21 vibration watch   VibrationWatchUtils (decompiled), prefs_accessibility_vibration_watch.xml
 *   -18 screen reader     TalkbackFragment, TalkBack values-watch/strings.xml,
 *                         VALUES.tsv accessibility_focus_highlight_color
 *   -22 power button      AccessibilityFragment (incall_power_button_behavior)
 */

/* ---- dconf keys (the Settings pages of W3-settings write them) ----------- */

var KEY_MAGNIFICATION = "/org/asteroidos/a11y/magnification"
var KEY_MAGNIFICATION_SCALE = "/org/asteroidos/a11y/magnification-scale"
var KEY_MAGNIFICATION_EDGE = "/org/asteroidos/a11y/magnification-edge-haptic"
var KEY_COLOR_CORRECTION = "/org/asteroidos/a11y/color-correction"
var KEY_COLOR_CORRECTION_MODE = "/org/asteroidos/a11y/color-correction-mode"
var KEY_VIBRATION_WATCH = "/org/asteroidos/a11y/vibration-watch"
var KEY_VIBRATION_WATCH_TYPE = "/org/asteroidos/a11y/vibration-watch-type"
var KEY_VIBRATION_WATCH_SPEED = "/org/asteroidos/a11y/vibration-watch-speed"
var KEY_POWER_ENDS_CALL = "/org/asteroidos/a11y/power-button-ends-call"

/* ---- magnification (gap -15) ---------------------------------------------- */

// 'Magnification size' slider: 1.5, 1.7, 2.0, 2.2, 2.5, 2.7, 3.0 x, default 2.0 x (200 %)
var SCALES = [1.5, 1.7, 2.0, 2.2, 2.5, 2.7, 3.0]
var DEFAULT_SCALE = 2.0
// the border while magnified: accessibility_magnification_indicator_width 4 dp
var BORDER_DP = 4

/* The nearest step of the slider to a stored value. */
function validScale(v) {
    var n = Number(v)
    if (!(n > 0))
        return DEFAULT_SCALE
    var best = SCALES[0]
    for (var i = 1; i < SCALES.length; i++)
        if (Math.abs(SCALES[i] - n) < Math.abs(best - n))
            best = SCALES[i]
    return best
}

/* The view of a magnified screen: a point p of the scene shows at p * s + t (per axis). Zooming in
 * at the point f (where the third tap landed) keeps f where it is: t = f * (1 - s). The screen is
 * always covered: t stays in [size * (1 - s), 0]. */
function zoomAt(f, s, size) {
    return clampPan(f * (1 - s), s, size)
}

function clampPan(t, s, size) {
    return Math.max(size * (1 - s), Math.min(0, t))
}

/* A finger drag of d px moves the content with it: the new offset and whether it ran into an edge
 * (the 'Vibrate on edge' haptic comes when it reaches one, not while it stays there). */
function pan(t, d, s, size) {
    var n = clampPan(t + d, s, size)
    var lo = size * (1 - s)
    var atBound = n >= 0 || n <= lo
    var wasBound = t >= 0 || t <= lo
    return { t: n, hit: atBound && !wasBound }
}

/* ---- colour correction (gap -16) ------------------------------------------- */

var MODES = ["deuteranomaly", "protanomaly", "tritanomaly", "grayscale"]
var DEFAULT_MODE = "deuteranomaly"

function validMode(m) { return MODES.indexOf(m) >= 0 ? m : DEFAULT_MODE }

// Rec. 709 luma in every row, as Android's grayscale matrix and Bedtime's (modescore.cpp filterMatrix)
var GRAYSCALE = [0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722, 0.2126, 0.7152, 0.0722]
var IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]

// RGB to LMS (Hunt-Pointer-Estevez as the Vischeck simulation uses it), row-major
var RGB2LMS = [17.8824, 43.5161, 4.11935, 3.45565, 27.1554, 3.86714, 0.0299566, 0.184309, 1.46709]
// the simulation of each dichromacy in LMS space
var SIM = {
    protanomaly:   [0, 2.02344, -2.52581, 0, 1, 0, 0, 0, 1],
    deuteranomaly: [1, 0, 0, 0.494207, 0, 1.24827, 0, 0, 1],
    tritanomaly:   [1, 0, 0, 0, 1, 0, -0.395913, 0.801109, 0]
}
// the error shifted into the channels that can be seen
var ERR2MOD = {
    protanomaly:   [0, 0, 0, 0.7, 1, 0, 0.7, 0, 1],
    deuteranomaly: [0, 0, 0, 0.7, 1, 0, 0.7, 0, 1],
    tritanomaly:   [1, 0.7, 0, 0, 1, 0, 0, 0.7, 1]
}

function mul(a, b) {
    var r = []
    for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++)
            r.push(a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j])
    return r
}

function inv(m) {
    var a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
    var A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
    var det = a * A + b * B + c * C
    return [A / det, -(b * i - c * h) / det, (b * f - c * e) / det,
            B / det, (a * i - c * g) / det, -(a * f - c * d) / det,
            C / det, -(a * h - b * g) / det, (a * e - b * d) / det]
}

function add(a, b) {
    var r = []
    for (var i = 0; i < 9; i++)
        r.push(a[i] + b[i])
    return r
}

function sub(a, b) {
    var r = []
    for (var i = 0; i < 9; i++)
        r.push(a[i] - b[i])
    return r
}

/* The 3 x 3 colour matrix (row-major, applied to the colour) of a mode. The daltonizer is the
 * correction of Fidaner et al.: S = LMS2RGB * SIM * RGB2LMS is what the dichromat sees, and the
 * correction is I + ERR2MOD * (I - S): the part of the colour that is lost goes to channels
 * that are not. Grayscale is the luma matrix. */
function correctionMatrix(mode) {
    var m = validMode(mode)
    if (m === "grayscale")
        return GRAYSCALE.slice()
    var s = mul(inv(RGB2LMS), mul(SIM[m], RGB2LMS))
    return add(IDENTITY, mul(ERR2MOD[m], sub(IDENTITY, s)))
}

/* One colour matrix after another: first `a` (Bedtime's filter), then `b` (the correction). */
function chain(a, b) { return mul(b, a) }

/* ---- vibration watch (gap -21) ----------------------------------------------- */

// Speed 0 to 4, default 2 (VibrationWatchUtils)
var VW_GAP_MS = [800, 650, 500, 350, 200]
var VW_LONG_MS = [700, 450, 300, 225, 175]
var VW_SHORT_MS = [225, 150, 100, 75, 50]
var VW_DEFAULT_SPEED = 2
// 'Digits' (long = 10, short = 1) and 'Terse' (one short per quarter-hour)
var VW_DIGITS = "digits"
var VW_TERSE = "terse"

function validSpeed(v) {
    var n = Math.round(Number(v))
    return n >= 0 && n <= 4 ? n : VW_DEFAULT_SPEED
}

/* The vibration of a number 0..99 as the list of its pulses: [{ ms, afterMs }] (the vibration, and the
 * pause that follows it; as VibrationWatchUtils.buildConstantAmplitudeEffect: tens as long ones,
 * then ones as short ones, each followed by the gap). */
function pulses(value, speed) {
    var sp = validSpeed(speed)
    var tens = Math.floor(value / 10), ones = value % 10
    var out = []
    for (var i = 0; i < tens; i++)
        out.push({ ms: VW_LONG_MS[sp], afterMs: VW_GAP_MS[sp] })
    for (var j = 0; j < ones; j++)
        out.push({ ms: VW_SHORT_MS[sp], afterMs: VW_GAP_MS[sp] })
    return out
}

/* The same as stock's waveform array: [off, on, off, on, ...] in ms. The first off is 1 ms, the
 * tens and the ones are separated by a 0 ms vibration and another 1 ms off. */
function waveform(value, speed) {
    var sp = validSpeed(speed)
    var tens = Math.floor(value / 10), ones = value % 10
    var w = [1]
    for (var i = 0; i < tens; i++) { w.push(VW_LONG_MS[sp]); w.push(VW_GAP_MS[sp]) }
    w.push(0)
    w.push(1)
    for (var j = 0; j < ones; j++) { w.push(VW_SHORT_MS[sp]); w.push(VW_GAP_MS[sp]) }
    return w
}

/* The hour to tell: 12 hour clock unless the watch shows 24 hours. */
function hourValue(hours, use24h) {
    if (use24h)
        return hours
    var h = hours % 12
    return h === 0 ? 12 : h
}

/* What a two finger tap says. fingersTaps: 1 = the hour, 2 = the minute. type: 'digits' or 'terse'.
 * Returns the pulses. Terse: minutes as one short pulse per quarter-hour (0 to 3). */
function timePulses(taps, hours, minutes, use24h, type, speed) {
    if (taps === 1)
        return pulses(hourValue(hours, use24h), speed)
    if (type === VW_TERSE) {
        var sp = validSpeed(speed)
        var out = []
        for (var q = 0; q < Math.floor(minutes / 15); q++)
            out.push({ ms: VW_SHORT_MS[sp], afterMs: VW_GAP_MS[sp] })
        return out
    }
    return pulses(minutes, speed)
}

/* The ngfd event of a pulse: eos_vw_long_<speed> or eos_vw_short_<speed> (drafts/eos-a11y-events.ini). */
function pulseEvent(ms, speed) {
    var sp = validSpeed(speed)
    return (ms === VW_LONG_MS[sp] ? "eos_vw_long_" : "eos_vw_short_") + sp
}

/* ---- screen reader (gap -18) --------------------------------------------------- */

// the focus ring: #bf39b500 (alpha, red, green, blue as android prints it), 4 dp, thick 6 dp
var FOCUS_COLOR = "#bf39b500"
var FOCUS_WIDTH_DP = 4
var FOCUS_THICK_DP = 6
// speech rates 60 to 400 %, Normal 100
var SPEECH_RATE_MIN = 60
var SPEECH_RATE_MAX = 400
var SPEECH_RATE_NORMAL = 100

/* TalkBack's Wear gestures: a swipe of one finger right or left is next and previous, down and up
 * are the granularity (not built: it needs the text of the focused node); two fingers swiping scroll;
 * a swipe right then up or down is volume up and down. dir: "right", "left", "up", "down";
 * fingers 1 or 2; second: the direction of the second leg or "". Answers: next, previous,
 * scrollUp, scrollDown, scrollLeft, scrollRight, volumeUp, volumeDown, none. */
function swipeAction(fingers, dir, second) {
    if (fingers === 1) {
        if (second === "up" && dir === "right")
            return "volumeUp"
        if (second === "down" && dir === "right")
            return "volumeDown"
        if (second !== "" && second !== undefined)
            return "none"
        return dir === "right" ? "next" : dir === "left" ? "previous" : "none"
    }
    if (fingers === 2) {
        // the content moves with the fingers: swiping up scrolls down the list
        switch (dir) {
        case "up": return "scrollDown"
        case "down": return "scrollUp"
        case "left": return "scrollRight"
        case "right": return "scrollLeft"
        }
    }
    return "none"
}

/* One finger: double tap activates, double tap and hold is a long press; two fingers double tap
 * and hold is the media control. */
function tapAction(fingers, taps, held) {
    if (fingers === 1 && taps === 2)
        return held ? "longPress" : "activate"
    if (fingers === 2 && taps === 2 && held)
        return "media"
    return "none"
}
