/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The numbers and the rules of the eos watch faces (W3-launcher-faces), as plain
 * functions: the stock slot boxes of the faces that follow Wear OS's Utility, Index,
 * Everyday, Classic, Large Scale, Analog Bold, Track and Prime, the option schema
 * every face declares, the accent colours, the time text rules and the ambient look.
 * The QML faces only place what these functions return; the tests run them without a
 * screen. All boxes are in px of the 384 px screen (stock's 192 unit space x 2); a face
 * scales them with width / 384. Evidence for every number: stock-faces-extract.md of the
 * wear UI audit (res/xml/watch_face_<name>.xml of com.google.android.wearable.watchface.rwf),
 * AUDIT.md section 2.3 to 2.5 and 5.3; "inferred" marks what the previews gave.
 */

var BASE = 384

// ---- the font ------------------------------------------------------------------------
// Roboto: tabular digits (every digit one advance wide), which the sensor hub's glyph
// sprites need (huboffload.h); Outfit's digits are proportional. Stock's Google Sans Clock
// is Google's and is not shipped.
var FONT = "Roboto"
// Roboto of the image (the 2018 files: ascent 1.0478 em, descent 0.271 em): the digits' middle
// sits 0.688 em below the top of the line, and a digit is 0.73 em tall (measured with
// FontMetrics.tightBoundingRect; the same files are on the watch). digitTop() puts the
// digits' middle at a given y.
var DIGIT_CENTER = 0.688
var DIGIT_HEIGHT = 0.73
var DIGIT_ADVANCE = 0.5615      // em, every digit of Roboto, in every weight (FontMetrics.advanceWidth)
function digitTop(cy, size) { return cy - DIGIT_CENTER * size }

// stock weights 350 / 475 (interactive, Bold Time) and 200 / 350 (ambient) on the Roboto
// weights the image has (Thin 100, Light 300, Regular 400, Medium 500)
var WEIGHT = { normal: 300, bold: 500, ambientNormal: 100, ambientBold: 300 }
function weight(bold, ambient) {
    return ambient ? (bold ? WEIGHT.ambientBold : WEIGHT.ambientNormal) : (bold ? WEIGHT.bold : WEIGHT.normal)
}
// interactive to ambient: 300 ms (fuv.java:84-95, TRANSITION_TO_AMBIENT); the other way is at once
var AMBIENT_MS = 300
// the always-on colours are the interactive ones at this brightness (fewer lit pixels)
var AMBIENT_DIM = 0.7
// complications and other furniture in the always-on screen
var AMBIENT_SLOT_ALPHA = 0.6

function hex2(v) {
    var s = Math.max(0, Math.min(255, Math.round(v))).toString(16)
    return s.length < 2 ? "0" + s : s
}
// "#rrggbb" scaled towards black
function dim(color, f) {
    var m = /^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/.exec(String(color))
    if (!m)
        return String(color)
    return "#" + hex2(parseInt(m[1], 16) * f) + hex2(parseInt(m[2], 16) * f) + hex2(parseInt(m[3], 16) * f)
}
function ambientColor(color) { return dim(color, AMBIENT_DIM) }

// ---- the accents ("Color": four_colorway, 35 accents; the numbers are stock-colorways.tsv) ----
var ACCENTS = [
    ["graphite", "Graphite", "#949494"],
    ["cloud", "Cloud", "#e4e4e4"],
    ["almond", "Almond", "#fcf7eb"],
    ["watermelon", "Watermelon", "#ff7b78"],
    ["coral", "Coral", "#f99586"],
    ["pomelo", "Pomelo", "#ffa49f"],
    ["guava", "Guava", "#ffc1bd"],
    ["peach", "Peach", "#fdb78f"],
    ["champagne", "Champagne", "#ffd4b6"],
    ["chai", "Chai", "#d8ab77"],
    ["sand", "Sand", "#c4b575"],
    ["honey", "Honey", "#f8c67c"],
    ["melon", "Melon", "#ffd88a"],
    ["wheat", "Wheat", "#ffe9b9"],
    ["dandelion", "Dandelion", "#fffa86"],
    ["limoncello", "Limoncello", "#fcffb6"],
    ["lemongrass", "Lemongrass", "#ebffc3"],
    ["lime", "Lime", "#e6ff7b"],
    ["pear", "Pear", "#c7ff81"],
    ["spearmint", "Spearmint", "#adf7b9"],
    ["fern", "Fern", "#77d9a4"],
    ["forest", "Forest", "#67887b"],
    ["mint", "Mint", "#abffdf"],
    ["jade", "Jade", "#beecdb"],
    ["sage", "Sage", "#cce4df"],
    ["stream", "Stream", "#b0e4ec"],
    ["aqua", "Aqua", "#99f3ff"],
    ["sky", "Sky", "#b6daf1"],
    ["ocean", "Ocean", "#a2c2f7"],
    ["sapphire", "Sapphire", "#81acf4"],
    ["amethyst", "Amethyst", "#aeb4ff"],
    ["lilac", "Lilac", "#d6c3ff"],
    ["lavender", "Lavender", "#e4b0fd"],
    ["flamingo", "Flamingo", "#fabbff"],
    ["bubble-gum", "Bubble Gum", "#ffcaed"]
]
function accentIds() { return ACCENTS.map(function (a) { return a[0] }) }
function accentNames() { return ACCENTS.map(function (a) { return a[1] }) }
function accentColor(id, fallbackId) {
    for (var i = 0; i < ACCENTS.length; i++)
        if (ACCENTS[i][0] === id)
            return ACCENTS[i][2]
    return fallbackId !== undefined && fallbackId !== id ? accentColor(fallbackId) : "#ffffff"
}

// ---- the option schema (watchface-catalogue-10) -----------------------------------------
// A face declares `eosOptions`, a list of these; the editor shows a page per entry with
// the stock names ("Color", "Layout", "Styles", "Fonts", "Bold Time", "Seconds") and the
// launcher hands the favourite's values back to the face as `eosStyle` ({id: value}).
function listOption(id, values, labels, def) {
    return { id: id, kind: "list", values: values, labels: labels, def: def }
}
function boolOption(id, def) { return { id: id, kind: "bool", def: def } }
function colorOption(def) { return listOption("color", accentIds(), accentNames(), def) }
function findOption(schema, id) {
    var s = schema || []
    for (var i = 0; i < s.length; i++)
        if (s[i].id === id)
            return s[i]
    return null
}
// the value of an option for a style ({id: value}): the stored one when it is valid, else the default
function optionValue(schema, style, id) {
    var o = findOption(schema, id)
    if (!o)
        return undefined
    var v = style ? style[id] : undefined
    if (o.kind === "bool")
        return typeof v === "boolean" ? v : o.def
    return o.values.indexOf(v) >= 0 ? v : o.def
}
// every option of a schema with its value
function resolved(schema, style) {
    var out = {}
    var s = schema || []
    for (var i = 0; i < s.length; i++)
        out[s[i].id] = optionValue(s, style, s[i].id)
    return out
}
// whether the schema has a "seconds" option, and its default (false when it has none)
function secondsDefault(schema) {
    var o = findOption(schema, "seconds")
    return o ? o.def === true : undefined
}

// ---- time text: Pixel digital faces ("h:mm" in 12 h, "HH:mm" in 24 h; no AM/PM, no leading zero in 12 h)
function pad2(n) { return (n < 10 ? "0" : "") + n }
function hourText(h24, use12) {
    if (use12)
        return String(h24 % 12 === 0 ? 12 : h24 % 12)
    return pad2(h24)
}
function minuteText(m) { return pad2(m) }
function timeString(h24, m, use12) { return hourText(h24, use12) + ":" + minuteText(m) }
// the digits the layout has room for: "10:08" is the widest, in em
function timeWidthEm(use12, h24) {
    return (hourText(h24, use12).length + 2) * DIGIT_ADVANCE + 0.25    // colon about 0.25 em
}

// ---- boxes ---------------------------------------------------------------------------
function box(x, y, w, h) { return { x: x, y: y, w: w, h: h } }
function bulbAt(x, y, d) { return { x: x, y: y, w: d || 86, h: d || 86 } }
function lineAt(x, y) { return { x: x, y: y, w: 188, h: 28 } }
function centreOf(b) { return { x: b.x + b.w / 2, y: b.y + b.h / 2 } }

// F1 Modular (Utility, watch_face_numerique.xml; boxes gnk.java:12-16, gmo.java:46-82)
var MODULAR_LAYOUTS = ["modular1", "modular2", "modular3", "minimal"]
var MODULAR_NAMES = ["Modular I", "Modular II", "Modular III", "Minimal"]
function modular(layout) {
    switch (layout) {
    case "modular2":
        return { top: null, long: box(52, 228, 280, 100), time: box(76, 34, 228, 62), size: 72,
                 bulbs: { left: bulbAt(37, 124), center: bulbAt(149, 124), right: bulbAt(261, 124) } }
    case "modular3":
        return { top: lineAt(98, 38), long: box(52, 222, 280, 100), time: box(24, 92, 336, 106.7), size: 112, bulbs: null }
    case "minimal":
        return { top: null, long: null, time: box(0, 120, 384, 118.7), size: 128, bulbs: null }
    }
    return { top: lineAt(98, 38), long: null, time: box(18, 84, 348, 106), size: 112,
             bulbs: { left: bulbAt(36, 216.7), center: bulbAt(149, 216.7), right: bulbAt(262, 216.7) } }
}

// F2 List (Index, watch_face_utilita.xml): hours over minutes at the left, four lines at the right
var LIST_LINES = [100, 152, 204, 256]
function list() {
    var lines = []
    for (var i = 0; i < LIST_LINES.length; i++)
        lines.push({ x: 186.4, y: LIST_LINES[i], w: 188, h: 28 })
    // the digits' boxes are the measured ones (preview_utilita.png); 120 px = their height / cap height
    return { top: lineAt(98, 38), lines: lines, hour: box(44, 101, 155, 85), minute: box(40, 201, 159, 84), size: 120 }
}

// F3 Stacked (Everyday, watch_face_athletica.xml)
var STACKED_LAYOUTS = ["info", "big"]
function stacked(layout) {
    if (layout === "big")
        return { top: null, left: null, right: null, hour: box(46, 54, 292, 140), minute: box(46, 198, 292, 140), size: 172 }
    return { top: lineAt(98, 38), left: bulbAt(18, 150), right: bulbAt(280, 150),
             hour: box(100, 94, 183, 95), minute: box(100, 195, 183, 98), size: 132 }
}

// F4 Classic (watch_face_classica.xml): four bulbs
var CLASSIC_STYLES = ["none", "arabic1", "arabic2", "roman1", "roman2", "dashes", "dots"]
var CLASSIC_STYLE_NAMES = ["None", "Arabic I", "Arabic II", "Roman I", "Roman II", "Dashes", "Dots"]
function classic() {
    return { left: bulbAt(59, 150), top: bulbAt(150, 59), right: bulbAt(241, 150), bottom: bulbAt(150, 241) }
}
var ROMAN = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
// the numerals of a style: [{text, angle}] with angle in degrees from 12 o'clock, clockwise
function numerals(style) {
    var out = []
    var i
    if (style === "arabic1" || style === "roman1") {
        for (i = 0; i < 12; i++)
            out.push({ text: style === "arabic1" ? String(i === 0 ? 12 : i) : ROMAN[i], angle: i * 30 })
    } else if (style === "arabic2" || style === "roman2") {
        var four = style === "arabic2" ? ["12", "3", "6", "9"] : ["XII", "III", "VI", "IX"]
        for (i = 0; i < 4; i++)
            out.push({ text: four[i], angle: i * 90 })
    }
    return out
}
// the ticks of a style: [{angle, length, width, round}]
function ticks(style) {
    var out = []
    var i
    if (style === "dashes") {
        for (i = 0; i < 60; i++)
            out.push({ angle: i * 6, length: i % 5 === 0 ? 18 : 9, width: i % 5 === 0 ? 4 : 2, round: false })
    } else if (style === "dots") {
        for (i = 0; i < 12; i++)
            out.push({ angle: i * 30, length: 12, width: 12, round: true })
    }
    return out
}
// the numerals ring: the 12 spans y 10 to 37 in the preview, so its middle is 23.5 px from the rim
var NUMERAL_SIZE = 38              // px; cap height 27
var NUMERAL_RADIUS = 168.5

// hands: angles in degrees from 12 o'clock, clockwise
function hourAngle(h24, m) { return (h24 % 12) * 30 + m * 0.5 }
function minuteAngle(m, s) { return m * 6 + (s || 0) * 0.1 }
function secondAngle(s, ms) { return s * 6 + (ms || 0) * 0.006 }
// hand shapes in px: length from the pivot, width, tail behind it
var HANDS = {
    hour: { length: 100, width: 10, tail: 14 },
    minute: { length: 152, width: 8, tail: 14 },
    second: { length: 168, width: 3, tail: 30 }
}
// in the always-on screen the hands are drawn with this fraction of their width
var HAND_AMBIENT_WIDTH = 0.6

// F5 Large Scale (Accessible, watch_face_accessible.xml): glyphs about 31-352 x 84-180 (preview)
var LARGE_LAYOUTS = ["circular", "linear", "stacked", "justtime"]
var LARGE_NAMES = ["Circular", "Linear", "Stacked Time", "Just Time"]
function large(layout) {
    switch (layout) {
    case "linear":
        return { bulb: null, top: box(69.5, 58, 246.5, 44), stacked: false, size: 132, hour: box(0, 138, 384, 96), minute: null }
    case "stacked":
        return { bulb: bulbAt(206.1, 108, 148), top: null, stacked: true, size: 132, hour: box(36, 78, 148, 94), minute: box(36, 206, 148, 94) }
    case "justtime":
        return { bulb: null, top: null, stacked: false, size: 140, hour: box(0, 144, 384, 96), minute: null }
    }
    return { bulb: bulbAt(118.1, 198, 148), top: null, stacked: false, size: 132, hour: box(0, 84, 384, 96), minute: null }
}

// F6 Bold numerals (Analog Bold, watch_face_analogbold.xml)
var BOLD_LAYOUTS = ["numerals", "date", "info1", "info2", "info4"]
var BOLD_LAYOUT_NAMES = ["Numerals", "Date", "Info I", "Info II", "Info IV"]
var BOLD_STYLES = ["nodashes", "dashesdots", "dashes"]
var BOLD_STYLE_NAMES = ["No Dashes", "Dashes & Dots", "Dashes"]
var BOLD_FONTS = ["standard", "rounded"]
var BOLD_FONT_NAMES = ["Standard", "Rounded"]
var BOLD_NUMERAL_SIZE = 150
// the three numerals' centres
var BOLD_NUMERALS = [{ text: "12", cx: 192, cy: 100 }, { text: "9", cx: 62, cy: 192 }, { text: "6", cx: 192, cy: 284 }]
// the date window at 3 o'clock (the preview: about 258-346 x 170-214)
var DATE_WINDOW = box(258, 170, 88, 44)
function bold(layout) {
    switch (layout) {
    case "info1":
        return { window: null, bulbs: [{ id: "bottom", x: 142, y: 241, w: 100, h: 100 }], arcs: [] }
    case "info2":
        return { window: null, bulbs: [{ id: "left", x: 32, y: 142, w: 100, h: 100 }, { id: "right", x: 252, y: 142, w: 100, h: 100 }], arcs: [] }
    case "info4":
        return { window: null, bulbs: [],
                 arcs: [{ id: "topright", start: -90, sweep: 90 }, { id: "bottomright", start: 0, sweep: 90 },
                        { id: "bottomleft", start: 90, sweep: 90 }, { id: "topleft", start: 180, sweep: 90 }] }
    case "numerals":
        return { window: null, bulbs: [], arcs: [] }
    }
    return { window: DATE_WINDOW, bulbs: [], arcs: [] }
}
// the ticks of the Analog Bold styles: dashes every 5 minutes (and dots between) or every minute
function boldTicks(style) {
    var out = []
    var i
    if (style === "dashes") {
        for (i = 0; i < 60; i++)
            out.push({ angle: i * 6, length: i % 5 === 0 ? 16 : 8, width: i % 5 === 0 ? 4 : 2, round: false })
    } else if (style === "dashesdots") {
        for (i = 0; i < 60; i++)
            out.push({ angle: i * 6, length: i % 5 === 0 ? 16 : 4, width: i % 5 === 0 ? 4 : 4, round: i % 5 !== 0 })
    }
    return out
}

// F7 Step ring (Track, watch_face_soloring.xml): a ring round the rim, stacked time inside
var RING = { radius: 172, stroke: 32, start: -90, sweep: 360 }
var RING_LAYOUTS = ["stacked", "linear"]
function ring(layout) {
    if (layout === "linear")
        return { slot: box(98, 96, 188, 28), stacked: false, size: 112, hour: box(0, 146, 384, 106), minute: null }
    return { slot: box(98, 70.4, 188, 28), stacked: true, size: 112,
             hour: box(96, 100, 192, 82), minute: box(96, 190, 192, 82) }
}

// F8 Words (Prime, watch_face_wordclock.xml): three lines of 64 px words, a top line slot
var WORDS = { size: 64, top: box(100, 32, 188, 28), lines: [box(0, 100, 384, 46), box(0, 171, 384, 47), box(0, 242, 384, 48)],
              left: 48, right: 48 }
var ONES = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve",
            "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
var TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty"]
function numberWord(n) {
    if (n < 20)
        return ONES[n]
    return TENS[Math.floor(n / 10)] + (n % 10 ? "-" + ONES[n % 10].toLowerCase() : "")
}
/* The time as three lines: the hour, then the minutes' tens (or "Oh" under ten, the whole
 * number from ten to nineteen), then the minutes' units: 10:09 is Ten / Oh / Nine. On the
 * hour the second line says "O'clock". */
function words(h24, m, use12) {
    var h = use12 ? (h24 % 12 === 0 ? 12 : h24 % 12) : h24
    var l1 = numberWord(h)
    var l2, l3
    if (m === 0) {
        l2 = "O'clock"; l3 = ""
    } else if (m < 10) {
        l2 = "Oh"; l3 = ONES[m]
    } else if (m < 20) {
        l2 = ONES[m]; l3 = ""
    } else {
        l2 = TENS[Math.floor(m / 10)]; l3 = m % 10 ? ONES[m % 10] : ""
    }
    return [l1, l2, l3]
}

// F9 Photo (the Photos face): a picture behind the time, one line slot
var PHOTO_LAYOUTS = ["stacked", "linear"]
function photo(layout) {
    if (layout === "linear")
        return { slot: box(98, 240, 188, 24), stacked: false, size: 120, hour: box(0, 100, 384, 106), minute: null }
    return { slot: box(98, 306, 188, 36), stacked: true, size: 112, hour: box(96, 44, 192, 82), minute: box(96, 134, 192, 82) }
}
// the shade over the picture so the time stays readable, and its alpha in the always-on screen (the time alone)
var PHOTO_SHADE = 0.35

// the face a Loader fails on (watchface-catalogue-27, SysUI Simple: iqp.java:75-97,131-155)
var SIMPLE = { size: 100, digitOffset: 13.1, colonDot: 4, colonOffset: 16.7, ambientText: "#808080" }

// ---- slots: the launcher's ComplicationView shapes ------------------------------------
// the sources the faces default to: Day and date is "date", Next event is "nextevent", ...
var SLOT_DEFAULTS = {
    modular: { top: "date", left: "steps", center: "health", right: "heartrate", bottom: "nextevent" },
    list: { top: "date", one: "nextevent", two: "steps", three: "weather", four: "heartrate" },
    stacked: { top: "date", left: "heartrate", right: "weather" },
    classic: { left: "weather", top: "health", right: "datemonth", bottom: "steps" },
    large: { bulb: "heartrate", top: "date" },
    bold: { bottom: "weather", left: "weather", right: "datemonth", topright: "heartrate", bottomright: "weather", bottomleft: "steps", topleft: "date" },
    ring: { ring: "steps" },
    words: { top: "empty" },
    photo: { line: "weather" }
}
