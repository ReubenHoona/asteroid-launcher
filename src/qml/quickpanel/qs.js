/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the quick settings panel (W2-launcher-quick-settings) as pure
 * functions, unit tested by tst_qspanel.qml. QuickPanel.qml owns the state;
 * this file decides. Numbers are stock CP3A's (SysUI lah.java, kxx.java,
 * kxr.java, kzd.java, las.java; VALUES.tsv compose_*), in px of the 384 px
 * screen (2 px per dp) unless a fraction is named.
 */

/* ---- the list of rows ---------------------------------------------------- */

var ROW_SIZE = 3

/* Rows of three; the top row holds (count mod 3) tiles when that is not 0
 * (lah.java:318-344). Each row's tiles are reversed before they are placed
 * left to right (lah.java:499-500, inferred by the audit). */
function rows(ids) {
    var n = ids.length
    var first = n % ROW_SIZE
    var out = []
    if (first > 0)
        out.push(ids.slice(0, first))
    for (var i = first; i < n; i += ROW_SIZE)
        out.push(ids.slice(i, i + ROW_SIZE))
    for (var r = 0; r < out.length; r++)
        out[r].reverse()
    return out
}

/* the top spacer above the first row, as a fraction of the screen height, for
 * a top row of 1, 2 or 3 tiles (VALUES.tsv compose_top_margin_percent_*: 4.7 %,
 * 7.8 %, 20.8 %) */
function topSpacerFraction(firstRowCount) {
    return firstRowCount <= 1 ? 0.047 : firstRowCount === 2 ? 0.078 : 0.208
}
function topSpacer(firstRowCount, height) {
    return Math.ceil(topSpacerFraction(firstRowCount) * height - 1e-9)
}

/* the side padding of a centred row of n tiles */
function sidePadding(n, width, size, gap) {
    return (width - n * size - Math.max(0, n - 1) * gap) / 2
}

/* the height of the box under the last row (compose_qss_statustray_display_height_percent
 * 21.8 %) and its bottom padding (5.2 %): the pill sits at the bottom of it */
var STATUS_BOX_FRACTION = 0.218
var STATUS_BOTTOM_FRACTION = 0.052
function statusBoxHeight(height) { return Math.ceil(STATUS_BOX_FRACTION * height - 1e-9) }
function statusBottomPadding(height) { return Math.ceil(STATUS_BOTTOM_FRACTION * height - 1e-9) }

/* ---- the edge morph (las.java, hqc.java: TransformVariableSpec) ----------- */

/* CubicBezier(0, 0, 0.6, 1) */
var MORPH_EASING = [0, 0, 0.6, 1]
/* TransformVariableSpec(topValue, bottomValue, zone enter, zone exit): the
 * value at the top / bottom screen edge, and where in the transition area the
 * value reaches 1 (the middle). Alpha: container (0, 0.3, 0.05, 0.5), content
 * (0, 0.3, 0.25, 0.5); scale (0.15 top, 0.5 bottom, zone 0..1). The jadx
 * decode of the defaulting constructor is partly inferred (audit 05). */
var MORPH_SCALE = { top: 0.15, bottom: 0.5, enter: 0, exit: 1 }
var MORPH_CONTAINER = { top: 0, bottom: 0.3, enter: 0.05, exit: 0.5 }
var MORPH_CONTENT = { top: 0, bottom: 0.3, enter: 0.25, exit: 0.5 }
/* ResponsiveTransformationSpec element height 0.2..0.6, transition area 0.35..0.55 */
var MIN_ELEMENT = 0.2, MAX_ELEMENT = 0.6, MIN_AREA = 0.35, MAX_AREA = 0.55

/* the cubic Bezier y at x (Newton / bisection on t) */
function bezier(p, x) {
    if (x <= 0) return 0
    if (x >= 1) return 1
    var lo = 0, hi = 1, t = x
    for (var i = 0; i < 40; i++) {
        t = (lo + hi) / 2
        var u = 1 - t
        var bx = 3 * u * u * t * p[0] + 3 * u * t * t * p[2] + t * t * t
        if (bx < x) lo = t; else hi = t
    }
    var v = 1 - t
    return 3 * v * v * t * p[1] + 3 * v * t * t * p[3] + t * t * t
}

/* One variable of the spec at progress x (0 at the screen edge, 1 at the
 * inner end of the area): lerp(edge, 1, easing(clamp((x - enter) / (exit - enter)))) */
function variable(spec, edgeIsTop, x) {
    var edge = edgeIsTop ? spec.top : spec.bottom
    var z = Math.max(0, Math.min(1, (x - spec.enter) / (spec.exit - spec.enter)))
    return edge + (1 - edge) * bezier(MORPH_EASING, z)
}

/* The transform of an element whose top is at `top` px of a viewport `viewH`
 * px high and which is `h` px high (ResponsiveTransformationSpecKt
 * TransitionAreaProgress, as qml-asteroid's EdgeEffect): scale, the alpha of
 * the container and of the content. 1, 1, 1 in the middle. */
function morph(top, h, viewH) {
    var res = { scale: 1, container: 1, content: 1, atTop: top + h / 2 < viewH / 2 }
    if (viewH <= 0 || h <= 0)
        return res
    var f = top / viewH
    var hf = h / viewH
    var bottom = f + hf
    var heightFraction = Math.max(0, Math.min(1, (hf - MIN_ELEMENT) / (MAX_ELEMENT - MIN_ELEMENT)))
    var area = MIN_AREA + (MAX_AREA - MIN_AREA) * heightFraction
    area = Math.min(area, (hf + 1) / 2)
    var x = bottom < 1 - f ? bottom / area : (1 - f) / area
    x = Math.max(0, x)
    if (x >= 1)
        return res
    var topEdge = bottom < 1 - f
    res.atTop = topEdge
    res.scale = variable(MORPH_SCALE, topEdge, x)
    res.container = variable(MORPH_CONTAINER, topEdge, x)
    res.content = variable(MORPH_CONTENT, topEdge, x)
    return res
}

/* The outer tiles of a row slide inward as the row shrinks: +-width (1 - scale)
 * in a row of three, half that in a row of two, none in a row of one
 * (kok.java:239-250). index 0 is the left one; the result is the x shift. */
function slide(index, count, size, scale) {
    if (count < 2)
        return 0
    var d = size * (1 - scale) * (count === 2 ? 0.5 : 1)
    if (index === 0)
        return d
    if (index === count - 1)
        return -d
    return 0
}

/* the status pill's own scale (kxr.java): 0.4 -> 1 over the top 40 % of the
 * screen, 1 in the middle, 1 -> 0.6 over the bottom 40 %; `centre` is the
 * pill's centre as a fraction of the screen height */
function pillScale(centre) {
    var c = Math.max(0, Math.min(1, centre))
    if (c < 0.4)
        return 0.4 + 0.6 * (c / 0.4)
    if (c > 0.6)
        return 1 - 0.4 * ((c - 0.6) / 0.4)
    return 1
}

/* ---- the tiles ------------------------------------------------------------ */

/* the stock default list (CP3A arrays.xml:68-85, gap quick-settings-09); a
 * tile is shown only where it is available */
var DEFAULT_TILES = ["battery", "settingsButton", "soundToggle", "bedtimeToggle", "dndToggle", "cinemaToggle",
                     "airplaneToggle", "flashlightButton", "brightnessButton", "touchLockToggle", "mobileToggle",
                     "findPhoneButton"]

/* The tiles a list names, in its order, that exist and are available
 * (`available` maps an id to true / false; an id that is not in it does not
 * exist). Duplicates are shown once. */
function visibleTiles(list, available) {
    var out = []
    for (var i = 0; i < list.length; i++) {
        var id = list[i]
        if (available[id] === true && out.indexOf(id) < 0)
            out.push(id)
    }
    return out
}

/* ---- the battery button (kxx.java:293-347, kxb.java) -------------------- */

var BATTERY_STEPS = [15, 20, 30, 40, 50, 60, 70, 90, 99, 100]
var LOW_BATTERY = 15
var SAVER_CONTAINER = "#FEE170"
var SAVER_CONTENT = "#3A3000"

/* the level the glyph shows: the first step at or above the percent */
function batteryStep(percent) {
    var p = Math.max(0, Math.min(100, percent))
    for (var i = 0; i < BATTERY_STEPS.length; i++)
        if (p <= BATTERY_STEPS[i])
            return BATTERY_STEPS[i]
    return 100
}
function batteryLow(percent) { return percent <= LOW_BATTERY }

function batteryDescription(percent, saverOn, charging, tr) {
    var s = tr.battery.replace("%1", Math.round(percent))
    return s + " " + (charging ? tr.charging : saverOn ? tr.saverOn : tr.saverOff)
}

/* ---- the status pill (kxr.java:2395-2560, kzd.java) --------------------- */

var PILL_HEIGHT_DP = 26, PILL_MIN_WIDTH_DP = 50, PILL_PAD_DP = 5, PILL_ICON_DP = 20, PILL_GAP_DP = 4, PILL_OVERFLOW_DP = 22
var PILL_MAX_ICONS = 4

/* the icons, in stock's order (phone, Bluetooth, Wi-Fi, alarm), from the
 * sources: `s` = { phoneKnown, phoneConnected, btPowered, wifiConnected, alarmMs } */
function statusIcons(s) {
    var out = []
    if (s.phoneKnown !== false)
        out.push(s.phoneConnected ? "phone" : "phoneOff")
    if (s.btPowered === false)
        out.push("btOff")
    if (s.wifiConnected)
        out.push("wifi")
    if (s.alarmMs > 0)
        out.push("alarm")
    return out
}

/* shown and hidden (the "+N" overflow circle) */
function pillSplit(icons) {
    if (icons.length <= PILL_MAX_ICONS)
        return { shown: icons.slice(), more: 0 }
    return { shown: icons.slice(0, PILL_MAX_ICONS - 1), more: icons.length - (PILL_MAX_ICONS - 1) }
}

/* the pill's width in dp: min 50, padding 5 each side, icons 20 apart 4 */
function pillWidthDp(shown, more) {
    var n = shown + (more > 0 ? 1 : 0)
    var inner = shown * PILL_ICON_DP + (more > 0 ? PILL_OVERFLOW_DP : 0) + Math.max(0, n - 1) * PILL_GAP_DP
    return Math.max(PILL_MIN_WIDTH_DP, inner + 2 * PILL_PAD_DP)
}

/* ---- the state caption (kzp.java, qss2_toggle_overlay.xml) --------------- */

var CAPTION = { fadeIn: 375, hold: 3000, fadeOut: 375, swapOut: 150, swapIn: 225, swapDelay: 150,
                easing: [0.4, 0, 1, 1], widthFrom: 0.24, widthTo: 0.76, bottomFraction: 0.06,
                gradientDp: 41, gradientLongDp: 65 }

/* ---- timing --------------------------------------------------------------- */

var TAP_DEBOUNCE_MS = 300     /* lah.java:22-31 */
var LONG_PRESS_MS = 400       /* Android's default long press */
var AUTO_CLOSE_MS = 700       /* kzc: Theater mode and Touch lock close the tray */

/* a second tap on the same tile within 300 ms of the last one taken is ignored */
function acceptTap(now, last, debounce) {
    return now - last >= debounce
}
