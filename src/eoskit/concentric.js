/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The numbers of the Concentric face (watchfaces/027-concentric.qml): stock Wear OS's default
 * face, rwf "orbita" (OrbitaWatchFaceService, NumberWheel, gnu/gnp/gnq/gnr of
 * com.google.android.wearable.watchface.rwf; its design space is 192 units, x 2 here) and the
 * Wear OS 6 emulator's look (S01, S01-b awake, S02, S02-b always-on, S15 picker, M13 motion).
 * Plain functions: the face only places what these return, the tests run them without a screen,
 * and the face hands the sensor hub its dial through them (eosHubSlotOrigin, eosHubTick).
 *
 * Angles: a dial numeral of value v (00, 05 ... 55) sits at (v - t) * 6 degrees counter-clockwise
 * from 3 o'clock (NumberWheel.e: d2 = (15 - i) * 2 pi / 12 + offset, the offset the hand's angle),
 * t the seconds (outer dial) or the minutes (inner dial) shown. So the value now is in the pill
 * at 3 o'clock and the dial turns clockwise. Awake both dials sweep (M13: the outer dial moves
 * 6 degrees a second at every frame, the inner one 0.1 degree a second); always-on the inner dial
 * stands at the whole minute (S02: "40" at 35.7 degrees at 06:34) and the outer numerals are gone.
 * A slot j (0..59) is the place at j * 6 degrees: at the whole minute m it shows value (m + j) % 60
 * when that is a multiple of 5 (the hub's glyph expressions in huboffload.cpp use the same rule).
 */

var BASE = 384
var CX = 192
var CY = 192

// ---- the dials (NumberWheel radii gnu.c = 96 - 16 and gnu.b = 96 - 43 units; S01: 160.0 and 106.1 px)
var SECONDS_RADIUS = 160
var MINUTES_RADIUS = 106
// the numerals: 20 px cells of concentric_numbers.png (o(): 10 units); S01 digits 17 px tall:
// Roboto 23 px (digit 0.73 em = 16.8 px), Regular (the stock bitmap's stroke, 2 px)
var NUMERAL_PX = 23
// the inner dial's colour (gnu.h, NumberWheel colour filter SRC_IN); the outer dial and the pill
// take the colour option's text colour (colorway "c": white for Cloud, S01 255,255,255)
var MINUTES_COLOR = "#767a80"

// ---- the tick rings (orbita_indice_secs.png and orbita_indice_mins.png, measured: 60 ticks,
// 2 px wide, #5f6368; a long one at every numeral). Radii from the centre, in px.
var TICK_COLOR = "#5f6368"
var TICK_WIDTH = 2
var SECONDS_TICKS = { minor: [182, 189], major: [176, 190] }
var MINUTES_TICKS = { minor: [130.5, 137.5], major: [124, 138] }

// ---- the time (S01, S01-b: "06" ink 144..239 x 161..226; "33" ink 267..306 x 179..207)
// Hour: stock 44 units (88 px) Google Sans Clock wght 440, always-on wght 300 (gni 3, 4).
// Roboto 90 px has the same 66 px digits; Medium has the measured 10 px stroke (S01), Light the
// always-on 6 px one (S02). Minute: 19 units (38 px): Roboto 40 px (29 px digits), Regular has the
// measured 4 px stroke, Light the always-on 3 px one. Both left aligned in stock's boxes
// (gnu.i, gnu.j, Paint.Align.LEFT): the first digit's ink starts at these x.
var HOUR = { px: 90, inkLeft: 144, centerY: 193.5 }
var MINUTE = { px: 40, inkLeft: 266.5, centerY: 193 }

// ---- the pill (fio.D: a stadium of radius 17 units around (143, 96) units, running to the right
// off the screen; always-on it is a circle: the half-dial animator ends at length 0). The path
// is stroked 2 px (S01: 157..158 and 225..226 at x 300, 251..252 at y 192). As a Rectangle with
// its border inside: outer radius 35.
var PILL = { cx: 286, cy: 192, r: 34, stroke: 2, reach: 100 }
// the black under the pill (NumberWheel scrim): awake a rectangle over the inner numerals in the
// pill (0.68198..0.8102 x 0.4128..0.5872 of the screen), always-on a disk of 34 px at
// (0.75, 0.5) of the screen under the circle (the outer numerals stay visible in the pill: the
// seconds dial is drawn after this scrim)
var SCRIM_RECT = { x: 261.88, y: 158.52, w: 49.24, h: 66.96 }
var SCRIM_DISK = { cx: 288, cy: 192, r: 34 }

// ---- the options (watch_face_orbita.xml): Color (four_colorway, default index 1 = Cloud) and Layout
// (COMPLICATIONS_LAYOUT_STYLES, "Layout"): Dial I (default: tick rings on), Dial II (no tick rings:
// gnr 12 disables both index layers) and Half Dial (A-06, D60-48 residue; gnp 10 -> gnq case 8):
//  - the face's bounds become (-71, 0, 121, 192) units: everything of the dial 142 px to the left (the
//    dials' centre at x 50 px; NumberWheel and the scrims follow the parent bounds), both index rings on;
//  - the hour 40 units instead of 44 (gnu.b(40)): Roboto 90 * 40 / 44 = 82 px; its box (gnu.i, left
//    aligned) moves with the dial, so the first digit's ink starts where Dial I's would at that size:
//    box left 130 px + 14 px * 40 / 44 of side bearing, less 142 (0.7 px: at the bezel, as stock);
//  - the pill is "half-dial-inset" (gnp 12; gnr 7: InsetPathDrawable at (176, 79) units, length 33):
//    the stadium's circle centres 143 and 176 units, radius 17 (110..244 px after the shift);
//    always-on the circle (gnp 18/19: the length 33 -> 0); "full-dial-inset" is off;
//  - the seconds NumberWheel draws its vignette (setIncludeVignette; screen percentage 0.75): a
//    RadialGradient centred on the wheel's own bounds, which do not move (NumberWheel's q and s are set
//    from them at its making; the numerals follow the parent bounds), so on the screen's middle, radius
//    1.05 x 96 units (201.6 px), transparent out to 0.75 of it (151.2 px), then to black; PorterDuff DARKEN
//    (black with that alpha over what is under it); the left half only (drawArc 90, 180); always-on too
//    (the numbers' opacity is 0, the vignette is drawn regardless); drawn by the seconds wheel, so over
//    both dials and under the pill and the time;
//  - three bulbs (orbita_bulb_complication_*, 192-unit space, not moved): top 111.2..154.2 x 19..62
//    (Weather, fallback Sunrise and sunset), centre 137.2..180.2 x 75..118 (DATA_SOURCE_DATE: Date and
//    month), bottom 111.2..154.2 x 131..174 (Heart rate, fallback Notifications); off in Dial I and II.
// The sensor hub keeps drawing the dial always-on: the numerals the vignette darkens get cells of their
// own cut by it (huboffload.cpp buildDial: eosHubShade), the ones off the panel none.
var LAYOUTS = ["dial1", "dial2", "half"]
var LAYOUT_NAMES = ["Dial I", "Dial II", "Half Dial"]
var HALF = {
    shift: -142,
    hourPx: 82,
    hourInkLeft: 130 + 14 * 40 / 44,
    pillReach: 66,
    vignette: { cx: 192, cy: 192, r: 201.6, from: 0.75 },
    bulbs: {
        top: { x: 222.4, y: 38, w: 86, h: 86 },
        center: { x: 274.4, y: 150, w: 86, h: 86 },
        bottom: { x: 222.4, y: 262, w: 86, h: 86 }
    },
    defaults: { top: "weather", center: "datemonth", bottom: "heartrate" }
}
// the dial's shift (design px) and the pill's reach for a layout
function shiftOf(layout) { return layout === "half" ? HALF.shift : 0 }
function pillReach(layout) { return layout === "half" ? HALF.pillReach : PILL.reach }
// the vignette's darkening (0..1) at a design point: the left half of the screen, from 0.75 of its radius
function vignetteAt(x, y) {
    var v = HALF.vignette
    if (x > v.cx)
        return 0
    var d = Math.sqrt((x - v.cx) * (x - v.cx) + (y - v.cy) * (y - v.cy)) / v.r
    return Math.max(0, Math.min(1, (d - v.from) / (1 - v.from)))
}

// the colorways' text colour ("c" of stock-colorways.tsv, the A rows that four_colorway.xml lists: Jade is
// A13, Lemongrass A37, not the C05/C06 rows of the same names), what NumberWheel and the pill take; the
// same as facekit.js colorRole(id, "c")
var TEXT_COLORS = {
    "graphite": "#9b9b9b", "cloud": "#ffffff", "almond": "#fff6e2", "watermelon": "#ff7572",
    "coral": "#f99181", "pomelo": "#f8908b", "guava": "#ffb2ad", "peach": "#ffb891",
    "champagne": "#ffc79f", "chai": "#d8a161", "sand": "#cbbb75", "honey": "#fac16e",
    "melon": "#ffd786", "wheat": "#ffe9b9", "dandelion": "#fffa7a", "limoncello": "#fcffb6",
    "lemongrass": "#e8febb", "lime": "#e6ff7b", "pear": "#c7ff81", "spearmint": "#9df8ab",
    "fern": "#73e1a5", "forest": "#6a9685", "mint": "#80fdd5", "jade": "#b0f1d9",
    "sage": "#b2dcd3", "stream": "#9fe2ec", "aqua": "#99f3ff", "sky": "#aedfff",
    "ocean": "#94bafa", "sapphire": "#75a5f4", "amethyst": "#a0a7ff", "lilac": "#d0baff",
    "lavender": "#d593fe", "flamingo": "#f9b0ff", "bubble-gum": "#ffbae8"
}
function textColor(id) {
    return TEXT_COLORS.hasOwnProperty(id) ? TEXT_COLORS[id] : TEXT_COLORS["cloud"]
}

// ---- the time texts: two digits in 12 h too (S01 "06" at 6:33 pm, S15 "10")
function pad2(n) { return (n < 10 ? "0" : "") + n }
function hourText(h24, use12) { return pad2(use12 ? (h24 + 11) % 12 + 1 : h24) }

// ---- the sweep: seconds of the day of a date, with its milliseconds
function secondsOfDay(d) {
    return d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + d.getMilliseconds() / 1000
}
// the dials' t from the sweep: seconds 0..60, minutes 0..60 (with the seconds)
function secondsT(sweep) { return ((sweep % 60) + 60) % 60 }
function minutesT(sweep) { return ((sweep / 60) % 60 + 60) % 60 }

// ---- angles and places
// degrees counter-clockwise from 3 o'clock, in (-180, 180]
function norm(a) {
    var r = ((a % 360) + 360) % 360
    return r > 180 ? r - 360 : r
}
function numeralAngle(v, t) { return norm((v - t) * 6) }
// the dial's turn for its tick ring, degrees clockwise (QML rotation): 0 at t = 0
function ringTurn(t) { return t * 6 }
// the point at `radius` and angle `deg` (counter-clockwise from 3 o'clock), design px
function pointAt(radius, deg) {
    var a = deg * Math.PI / 180
    return { x: CX + radius * Math.cos(a), y: CY - radius * Math.sin(a) }
}
// the top-left of a numeral Text (w x h px on this screen, k px per design px) whose digits'
// middle is at the dial point: the box centred across, the digits' middle (digitCenter em of
// the font size) on the point. snap: whole pixels (the always-on face: the hub's cells land
// exactly where the AP drew them)
function numeralTopLeft(radius, deg, w, k, px, digitCenter, snap) {
    var p = pointAt(radius, deg)
    var x = p.x * k - w / 2
    var y = p.y * k - digitCenter * px
    return snap ? { x: Math.round(x), y: Math.round(y) } : { x: x, y: y }
}
// slot j (0..59) at the whole minute m: the value it shows, or -1 (no numeral there)
function slotValue(j, m) {
    var v = (m + j) % 60
    return v % 5 === 0 ? v : -1
}
// the slot of value v at the whole minute m
function slotOf(v, m) { return ((v - m) % 60 + 60) % 60 }
// a tick of a ring at angle deg (counter-clockwise from 3 o'clock) from radius r0 to r1:
// its centre line in design px
function tickLine(deg, r0, r1) {
    var a = pointAt(r0, deg), b = pointAt(r1, deg)
    return { x1: a.x, y1: a.y, x2: b.x, y2: b.y }
}

// ---- the pill window: what of a dial is in the pill (the value shown now) ----
// whether a design point is inside the pill's stroke outline (awake: the stadium to the right edge)
function inPill(x, y) {
    if (Math.abs(y - PILL.cy) > PILL.r)
        return false
    if (x >= PILL.cx)
        return true
    var dx = x - PILL.cx, dy = y - PILL.cy
    return dx * dx + dy * dy <= PILL.r * PILL.r
}
// the value of a dial whose numeral is nearest 3 o'clock at time t (the one in the window)
function windowValue(t) {
    return (Math.round(t / 5) * 5) % 60
}
// the pill's outer width (design px) at an always-on blend 0..1: the stadium's right end moves
// left until it is the circle (stock: AccelerateDecelerateInterpolator, gnu.d); reach: Half Dial's is shorter
function pillWidth(blend, reach) {
    var b = Math.max(0, Math.min(1, blend))
    var e = 0.5 - 0.5 * Math.cos(Math.PI * b)
    return 2 * (PILL.r + PILL.stroke / 2) + (reach === undefined ? PILL.reach : reach) * (1 - e)
}
