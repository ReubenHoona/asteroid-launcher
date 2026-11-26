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

/* Rows of three, read from the bottom up: CP3A reverses the list before it is
 * grouped (kxx.java:422 and :653, quicksettings_buttons .h(): Guava's
 * ImmutableList.reverse(), nkn.java), so the list's first tiles (Battery,
 * Settings, Sound) make the bottom row and the remainder row, count mod 3
 * tiles when that is not 0, is the top one (lah.java:33-41, :318-344). Each
 * row's tiles are reversed again before they are placed left to right
 * (lah.java:331, :342), so a row reads in the list's order. */
function rows(ids) {
    var rev = ids.slice().reverse()
    var n = rev.length
    var first = n % ROW_SIZE
    var out = []
    if (first > 0)
        out.push(rev.slice(0, first))
    for (var i = first; i < n; i += ROW_SIZE)
        out.push(rev.slice(i, i + ROW_SIZE))
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
 * (0, 0.3, 0.25, 0.5); scale (0.15 top, 0.5 bottom, zone 0..1); the button's
 * height, as a fraction of its width (buttonMorphHeight, las.java:17): 0.5 top,
 * 0.7 bottom, zone 0..1. The target (middle) value of each is 1: las.java passes
 * every spec through hdu.w / hdu.v (hdu.java:2263-2272, :2274-2316), which
 * rebuilds it with the defaulting constructor, mask 2 = target 1.0, so the
 * scale spec's own 0.7 (las.java:14) is not used; the values are hqf.java's
 * lerp(edge, target, easing(zone)). */
var MORPH_SCALE = { top: 0.15, bottom: 0.5, enter: 0, exit: 1 }
var MORPH_CONTAINER = { top: 0, bottom: 0.3, enter: 0.05, exit: 0.5 }
var MORPH_CONTENT = { top: 0, bottom: 0.3, enter: 0.25, exit: 0.5 }
var MORPH_HEIGHT = { top: 0.5, bottom: 0.7, enter: 0, exit: 1 }
/* the content is not drawn below this content alpha (lag.java:126) */
var MORPH_CONTENT_MIN = 0.05
/* TransformationSpec element height 0.2..0.6, transition area 0.5..0.5 of the
 * screen: the 192 dp spec of las.java:14 is hqd's defaulting constructor
 * (hqd.java:68-70: 0.2, 0.6, 0.5, 0.5), so the area is half the screen
 * whatever the element's height (hca.java:2621-2658) */
var MIN_ELEMENT = 0.2, MAX_ELEMENT = 0.6, MIN_AREA = 0.5, MAX_AREA = 0.5

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
 * px high and which is `h` px high (hca.java:2621-2658, as qml-asteroid's
 * EdgeEffect): scale, the alpha of the container and of the content, and the
 * height of the button as a fraction of its width (the stadium it is squeezed
 * into, kept on its inner edge: lag.java:80-125). 1, 1, 1, 1 in the middle.
 * The progress is taken from the element's inner edge (its bottom at the top
 * of the screen, its top at the bottom), which the squeeze keeps where it is. */
function morph(top, h, viewH) {
    var res = { scale: 1, container: 1, content: 1, height: 1, atTop: top + h / 2 < viewH / 2 }
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
    res.height = variable(MORPH_HEIGHT, topEdge, x)
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

function clamp01(v) { return Math.max(0, Math.min(1, v)) }

/* The status tray's transform: kxf.java case 16, the graphics layer of
 * lav.java:24-68 around the tray's box (kxr.java:2419-2470: statusBoxHeight
 * high, the pill at its bottom with statusBottomPadding under it). `top` and
 * `bottom` are the box's edges as fractions of the list's height (the item's
 * scroll progress), `h` its height in px. About the box's centre (byl.a):
 *  - scale 1, falling to 0.35 as its top goes from 0.8 to 1 of the screen
 *    (rising from 0.35 as its bottom comes from 0 to 0.2 at the top);
 *  - alpha 1, falling to 0.5 as its top goes from 0.6 to 1 (from 0.5 as its
 *    bottom comes from 0 to 0.4);
 *  - a shift towards the middle of h (1 - c) / 4, c = lav.c (lav.java:13-22):
 *    0.4 -> 1 as the bottom comes from 0 to 0.4, 1, then 1 -> 0.6 as the top
 *    goes from 0.6 to 1.
 * At rest (box top 300 / 384 = 0.781, bottom 1): scale 1, alpha 0.773,
 * shift -3.8 px; the pill (surfaceContainerLow #24262B) shows as #1C1D21. */
function statusTransform(top, bottom, h) {
    var scale = top > 0.8 ? 1 - 0.65 * clamp01((top - 0.8) / 0.2)
              : bottom < 0.2 ? 0.35 + 0.65 * clamp01(bottom / 0.2) : 1
    var alpha = bottom < 0.4 ? 0.5 + 0.5 * clamp01(bottom / 0.4)
              : top > 0.6 ? 1 - 0.5 * clamp01((top - 0.6) / 0.4) : 1
    var c = bottom < 0.4 ? 0.4 + 0.6 * clamp01(bottom / 0.4)
          : top <= 0.6 ? 1 : 1 - 0.4 * clamp01((top - 0.6) / 0.4)
    var dy = 1 - bottom > 0.6 ? h * (1 - c) / 4 : 1 - top < 0.4 ? -h * (1 - c) / 4 : 0
    return { scale: scale, alpha: alpha, dy: dy }
}

/* ---- the pull (lah.java) -------------------------------------------------- */

/* While quick settings is pulled in, CP3A's list moves in two parts, p being
 * how far out the tray is (laj.java:183-199 from ihr.java:79-92: the tray's
 * position over its size): the list is offset down by the screen height x
 * (1 - p) (lah.java:420-425 with afn.java case 14), which cancels the tray's
 * slide, and its last item, combined-bottom-spacer, is max(1 dp, 1.25 x the
 * screen height x (1 - p)) high (lah.java:547 with eqa.java case 3) while the
 * list is kept at its end on every change of p (lah.java:299-311). So on the
 * screen the content comes in 1.25 x the finger and arrives with the tray.
 * pullGrowth is how far the spacer has grown over its rest height: the content
 * is that much higher on the screen than at rest. */
var PULL_SPACER_FACTOR = 1.25
function pullGrowth(p, height, minimum) {
    return Math.max(minimum, PULL_SPACER_FACTOR * height * (1 - clamp01(p))) - minimum
}
function pullOffset(p, height) { return height * (1 - clamp01(p)) }

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

/* ---- the glyphs ---------------------------------------------------------- */

/* The Wear OS 6 emulator's quick settings (S11, S12) draws every button with a
 * Material Symbols Rounded FILLED glyph in onSurface: Bedtime a crescent moon
 * (bedtime), Do Not Disturb a disc with a bar (do_not_disturb_on), Theater a
 * clapperboard (movie), Settings a filled gear (settings), Notifications and
 * ring a bell, struck when muted (notifications, notifications_off), Airplane
 * an airplane (airplanemode_active), Flashlight a filled torch, struck while
 * it is off (flashlight_on, flashlight_off), Brightness a filled sun with 8
 * short rays (sunny), Find my phone a phone with waves (vibration). The icon
 * set has the moon, gear and sun as ms-bedtime-fill, ms-settings-fill and
 * ms-sunny-fill; the image's set has no clapperboard, torch or bell in FILL 1,
 * so these are path data here: Material Symbols Rounded glyphs (Google, Apache
 * License 2.0; google/material-design-icons 10ecc14, symbols/web/<name>/
 * materialsymbolsrounded/<name>_fill1_24px.svg), in their 960 box with y from
 * -960 to 0: movie, flashlight_on, flashlight_off, notifications,
 * notifications_off. The licence text is COPYING.Apache-2.0. */
var ICON_BEDTIME = "ms-bedtime-fill"
var ICON_SETTINGS = "ms-settings-fill"
var ICON_BRIGHTNESS = "ms-sunny-fill"
var GLYPH_CLAPPER = "m160-800 65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h80l65 130q7 14 20 22t28 8q30 0 46-25.5t2-52.5l-41-82h120q33 0 56.5 23.5T880-720v480q0 33-23.5 56.5T800-160H160q-33 0-56.5-23.5T80-240v-480q0-33 23.5-56.5T160-800Z"
var GLYPH_TORCH = "M240-760v-40q0-33 23.5-56.5T320-880h320q33 0 56.5 23.5T720-800v40H240Zm240 420q25 0 42.5-17.5T540-400q0-25-17.5-42.5T480-460q-25 0-42.5 17.5T420-400q0 25 17.5 42.5T480-340ZM320-160v-360l-67-100q-7-10-10-21t-3-23v-16h480v16q0 12-3 23t-10 21l-67 100v360q0 33-23.5 56.5T560-80H400q-33 0-56.5-23.5T320-160Z"
var GLYPH_TORCH_OFF = "M320-160v-368L84-764q-11-11-11-28t11-28q11-11 28-11t28 11l680 680q11 11 11 28t-11 28q-11 11-28 11t-28-11L640-208v48q0 33-23.5 56.5T560-80H400q-33 0-56.5-23.5T320-160Zm27-600q-16 0-30.5-6T291-783l-21-21q-20-20-4-48t54-28h320q33 0 56.5 23.5T720-800q0 17-11.5 28.5T680-760H347Zm224 257L445-629q-14-14-6.5-32.5T466-680h213q24 0 33 20t-5 40l-74 111q-11 16-29.5 18T571-503Z"
var GLYPH_BELL = "M200-200q-17 0-28.5-11.5T160-240q0-17 11.5-28.5T200-280h40v-280q0-83 50-147.5T420-792v-28q0-25 17.5-42.5T480-880q25 0 42.5 17.5T540-820v28q80 20 130 84.5T720-560v280h40q17 0 28.5 11.5T800-240q0 17-11.5 28.5T760-200H200ZM480-80q-33 0-56.5-23.5T400-160h160q0 33-23.5 56.5T480-80Z"
var GLYPH_BELL_OFF = "M646-200H200q-17 0-28.5-11.5T160-240q0-17 11.5-28.5T200-280h40v-280q0-33 8.5-65t25.5-61l126 126H288L84-764q-11-11-11-28t11-28q11-11 28-11t28 11l680 680q11 11 11.5 27.5T820-84q-11 11-28 11t-28-11L646-200Zm74-251q0 12-7 22t-18 15q-11 5-23 2.5T652-422L367-707q-7-7-10-15t-3-17q0-11 5.5-21.5T375-776q11-5 22-9t23-7v-28q0-25 17.5-42.5T480-880q25 0 42.5 17.5T540-820v28q80 20 130 85t50 147v109ZM480-80q-30 0-53.5-16.5T403-141q0-8 6.5-13.5T424-160h112q8 0 14.5 5.5T557-141q0 28-23.5 44.5T480-80Z"
/* the Flashlight button's glyph: the torch while the light is on, struck while it is off (S12) */
function torchGlyph(on) { return on ? GLYPH_TORCH : GLYPH_TORCH_OFF }
/* the Notifications and ring button's glyph: the bell, struck while muted (S11) */
function bellGlyph(muted) { return muted ? GLYPH_BELL_OFF : GLYPH_BELL }
/* Do Not Disturb (a disc with a bar) and Find my phone (a phone with waves on
 * both sides) are in the icon set: Material Symbols do_not_disturb_on (fill 1)
 * and vibration (CP3A compose_btn_dnd, kxx.java:276, and compose_btn_phone,
 * kxx.java:247, look the same) */
var ICON_DND = "ms-do_not_disturb_on-fill"
var ICON_FIND_PHONE = "ms-vibration"

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

/* The battery glyph, dp: CP3A's battery_status_0..9 (32 x 14 dp, drawn 1:1 in
 * the 32 dp icon, vertically centred: kze.java:15-35, kzc.c 32): a body
 * 22.154 x 12 at (4.269, 1) with 3.692 corners and a nub 1.385 x 5.539 at
 * (27.346, 4.23), both at 55 % of the content colour, and the level part of
 * the body solid from its left edge to levelRight[step index] (the body's own
 * shape cuts the last two); at 100 % body and nub are solid. */
var BATTERY_GLYPH = { width: 32, height: 14, top: 9,
                      bodyX: 4.269, bodyY: 1, bodyWidth: 22.154, bodyHeight: 12, bodyRadius: 3.692,
                      nubX: 27.346, nubY: 4.23, nubWidth: 1.385, nubHeight: 5.539, nubRadius: 1.077,
                      emptyAlpha: 0.55,
                      levelRight: [7.041, 8.885, 9.808, 12.555, 15.346, 18.124, 20.885, 22.731, 23.5, 26.423] }
/* the width of the solid part of the body, dp, for a percent */
function batteryLevelWidth(percent) {
    var i = BATTERY_STEPS.indexOf(batteryStep(percent))
    return BATTERY_GLYPH.levelRight[i] - BATTERY_GLYPH.bodyX
}

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

/* ---- the sample of a volume step (haptics-sounds-14, CR-56) ---- */

/* The ngfd event of a volume step: volume_step and volume_step_max for media (the main volume),
 * volume_step_<role> and volume_step_max_<role> for ring, notification, alarm and call: the names
 * Settings plays (asteroid-settings VolumeStepSound.qml). */
function volumeStepEvent(role, atMax) {
    return "volume_step" + (atMax ? "_max" : "") + (role === "media" ? "" : "_" + role)
}
