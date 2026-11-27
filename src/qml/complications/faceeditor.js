/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The rules and numbers of the watch face editor (W3-launcher-face-editor), as
 * plain functions, so the tests run them without a screen. Stock Wear OS (CP3A,
 * SysUI watchfaceeditor): a full-screen editor over the face, a horizontal
 * pager with a page per list setting, then "Complications", then the boolean
 * settings three to a page ("Other options"), page dots along the bottom arc.
 * Sizes in dp (1 dp = 2 px on the 384 px screen: Theme.dp), percentages of the
 * screen; every number cites the stock file it comes from.
 */

// ---- the editor window (activity_editor.xml, ic_fader.xml, jeu.java:41) ------------

// the bottom fader: a vertical gradient over the whole screen, clear to 65.1 %,
// #a3000000 at 82.29 %, black at 100 % (_ic_fader__0_res_0x7f08004f.xml)
var FADER = [
    { at: 0.0,    color: "#00000000" },
    { at: 0.651,  color: "#00000000" },
    { at: 0.8229, color: "#a3000000" },
    { at: 1.0,    color: "#ff000000" }
]
// 15 s without a touch or a crown event: the editor finishes, changes kept (jeu.java:41 g = 15000)
var IDLE_MS = 15000
// the picker under the editor hides itself 500 ms after the editor opened (kdn.java:28-32)
var PICKER_HIDE_MS = 500
// the editor shows at once over the picker: its theme's windowAnimationStyle is @null
// (SU/res/values/styles.xml:1462-1466; motion K8), no fade

// ---- list setting page (fragment_list_type.xml, VALUES wf_editor_mini_chip_*) ------

var CHIP_HEIGHT_DP = 20             // wf_editor_mini_chip_fixed_height
var CHIP_PADDING_DP = 10            // wf_editor_mini_chip_padding, each side
var CHIP_TEXT_DP = 12               // wf_editor_mini_chip_text_size (dp, not sp)
var CHIP_BOTTOM_DP = 29             // wf_editor_mini_chip_margin_bottom
var CHIP_MAX_WIDTH_DP = 140         // wf_editor_mini_chip_max_width
var CHIP_MARQUEE_DP = 120           // wf_editor_mini_chip_marquee_threshold
var CHIP_TAP_HEIGHT_DP = 50         // wf_editor_mini_chip_tap_target_height
var CHIP_TAP_PAD_DP = 22            // wf_editor_mini_chip_tap_target_width_padding
var MARQUEE_DELAY_MS = 2000         // CurrentListOptionView.java:30-35 (postDelayed 2000), repeat limit 1
// the crown: one option per 96 px of scroll (the stepper's item height, WatchFaceEditorActivity:222-245)
var STEP_PX = 96
var STEP_SUM_MS = 200               // scroll events less than 200 ms apart are summed

// the selector indicator on the right edge (RSBControl, epq.java, rsb_* dimens)
var SELECTOR_SWEEP = 51             // degrees of the track, centred on 3 o'clock (rsbControlType attr 3 default)
var SELECTOR_STROKE_DP = 6          // rsb_stroke
var SELECTOR_OUTSIDE_DP = 5         // rsb_outside_padding (+ half the stroke from the edge)
var SELECTOR_TRACK = "#4dffffff"    // rsb_track_color
var SELECTOR_MOVE_MS = 450          // jda.java:25-46
var SELECTOR_FADE_MS = 250          // ViewConfiguration.getScrollBarFadeDuration
var SELECTOR_HOLD_MS = 1200         // getScrollDefaultDelay (300) x 4, then it fades out
var SELECTOR_MIN_SCALE = 0.65       // RSBControl.a: scaleY 0.65 -> 1 while it fades in

/* The thumb of the selector for option `index` of `count`, in Qt angles
 * (degrees, 0 = 3 o'clock, positive = clockwise as on screen): {start, sweep}.
 * Stock draws the arc from start = g / 2 - (g - len) / h * d with sweep -len,
 * len = max(g / (h + 1), g x 0.1), h = count - 1, and d = count - index - 1, so
 * the first option is at the top of the track and the last at the bottom. */
function selectorThumb(index, count) {
    var g = SELECTOR_SWEEP
    var h = Math.max(1, count - 1)
    var len = Math.max(g / (h + 1), g * 0.1)
    var i = Math.max(0, Math.min(count - 1, index))
    var d = Math.max(0, Math.min(h, count - i - 1))
    var start = g / 2 - (g - len) / h * d
    // Android: from `start` anticlockwise (negative sweep) by len; as a Qt arc: from start - len, sweep len
    return { start: start - len, sweep: len }
}

/* The chip: its width for a text of `textPx`, in px of a screen with `dp` px per dp.
 * Up to the marquee threshold the chip wraps its text (10 dp padding each side); a
 * longer text makes it the maximum width (140 dp), and the text scrolls once. */
function chipWidth(textPx, dp) {
    if (needsMarquee(textPx, dp))
        return CHIP_MAX_WIDTH_DP * dp
    return Math.min(CHIP_MAX_WIDTH_DP * dp, textPx + 2 * CHIP_PADDING_DP * dp)
}
function needsMarquee(textPx, dp) { return textPx > CHIP_MARQUEE_DP * dp }
// how far the marquee moves: the text's width less the room it has inside the chip
function marqueeDistance(textPx, dp) {
    return Math.max(0, textPx - (CHIP_MAX_WIDTH_DP - 2 * CHIP_PADDING_DP) * dp)
}

// ---- the options list (fragment_list_options.xml) -----------------------------------

var OPTIONS_TOP = 0.1664            // wf_editor_header_padding_percent
var OPTIONS_BOTTOM = 0.3645         // wf_editor_footer_padding_percent
var OPTIONS_SIDE = 0.052            // wf_editor_horizontal_margin_percent
var OPTIONS_GAP_DP = 4              // wf_editor_list_item_separator_margin
var OPTIONS_TITLE_SIDE = 0.073      // wf_editor_title_horizontal_padding_percent

// ---- boolean settings page (fragment_bool_type.xml, editor_transparent_chip.xml) ----

var BOOL_PER_PAGE = 3               // jeu.java:405-500 (dyj.aV(list, 3, 3))
var BOOL_CHIP_HEIGHT_DP = 48        // wf_editor_transparent_toggle_chip_height (minimum)
var BOOL_MARGIN_DP = 12             // wf_editor_transparent_chip_horizontal_margin

// ---- complications page (jcb.java, jbz.java, VALUES wf_editor_comp_outline) ---------

var HIGHLIGHT_COLOR = "#999aa0a6"   // wf_editor_comp_outline: #9aa0a6 at 60 %
var HIGHLIGHT_FILL = "#1fffffff"    // the inside faintly white (ComplicationHighlightRenderer)
var HIGHLIGHT_STROKE_PX = 4         // "about 4 px"
var PULSE_DELAY_MS = 500            // jcb.java: postDelayed 500 after the page shows
var PULSE_MS = 300                  // 1.0 -> 0.5 in 300 ms, reversing, forever
var PULSE_LOW = 0.5
// the invisible tap target round a slot is at least this fraction of the width on a side (a finger)
var SLOT_TAP_MIN_FRACTION = 0.16

/* Whether a point (dx, dy), in face px from the face's middle, lies on the band
 * of an arc slot: between the two radii and inside the angles from `start` over
 * `sweep` (degrees, 0 = 3 o'clock, clockwise as on screen). */
function inArc(dx, dy, start, sweep, inner, outer) {
    var r = Math.sqrt(dx * dx + dy * dy)
    if (r < inner || r > outer)
        return false
    var a = Math.atan2(dy, dx) * 180 / Math.PI
    var d = ((a - start) % 360 + 360) % 360
    return d <= sweep
}

// ---- page dots (VALUES wear_page_indicator_*; activity_editor.xml page_indicator_overlay) ----

var DOT_PX = 12                     // radius 3 dp: 6 dp across = 12 px
var DOT_GAP_PX = 12                 // straight row only (square screens): dot plus padding 6 dp
var DOT_STEP_DEG = 6.6              // round screens: fixed angle per dot, hcy.java a(): canvas.rotate(-((i - f) * 6.6f))
var DOT_SELECTED_ALPHA = 1.0        // 255
var DOT_OTHER_ALPHA = 0.5           // 127 / 255 (0.498)
var DOT_EDGE_DP = 6                 // wear_page_indicator_padding 6 dp: inset from the edge; the arc radius is min/2 - 6 dp - dotRadius/2 (hcy.java c())

// ---- the pages -----------------------------------------------------------------------

/* The settings of our faces, as stock's editor sees them: list settings first
 * (one page each), then the complications when the face has slots, then the
 * boolean settings, three to a page. `id` is the FaceStyle option. */
var LIST_SETTINGS = [
    { id: "ambient-style", options: ["dim", "outline"] }
]
var BOOL_SETTINGS = [
    { id: "show-date" },
    { id: "show-seconds" }
]

/* A face with a schema (its eosOptions, W3-launcher-faces watchface-catalogue-10) has its
 * own pages: a list setting per list option, in the schema's order (stock: Color, Layout,
 * Styles, Fonts ...), the boolean options (Bold Time, Seconds ...) three to a page. The
 * Always-on and Date settings of the other faces are not stock's: a schema face owns its
 * always-on look and has its date in a slot. */
function schemaLists(schema) {
    var out = []
    var s = schema || []
    for (var i = 0; i < s.length; i++)
        if (s[i].kind === "list")
            out.push({ id: s[i].id, options: s[i].values, labels: s[i].labels })
    return out
}
function schemaBools(schema) {
    var out = []
    var s = schema || []
    for (var i = 0; i < s.length; i++)
        if (s[i].kind === "bool")
            out.push({ id: s[i].id })
    return out
}
// the stored key of an option: the schema's "seconds" is the old "show-seconds"
function storeKey(id) { return id === "seconds" ? "show-seconds" : id }

function chunk(list, n) {
    var out = []
    for (var i = 0; i < list.length; i += n)
        out.push(list.slice(i, i + n))
    return out
}

/* The pager's pages, in stock's order (jeu.java:405-500): a page per list
 * setting, "Complications" when `hasSlots`, then the boolean settings in
 * chunks of three. Each page: {kind: "list", setting}, {kind: "slots"} or
 * {kind: "bool", settings: [...]}. */
function pages(lists, bools, hasSlots) {
    var out = []
    for (var i = 0; i < lists.length; i++)
        out.push({ kind: "list", setting: lists[i] })
    if (hasSlots)
        out.push({ kind: "slots" })
    var groups = chunk(bools, BOOL_PER_PAGE)
    for (var g = 0; g < groups.length; g++)
        out.push({ kind: "bool", settings: groups[g] })
    return out
}

// the page the editor opens on: the one it was left on (kept for the next open), when it still exists
function openPage(last, count) {
    if (count <= 0)
        return 0
    return Math.max(0, Math.min(count - 1, last))
}

/* The idle timer: restarted by a touch or a crown event, never runs while a
 * finger is down or the display is not on (nothing runs in the always-on screen). */
function idleRunning(shown, touching, awake) {
    return shown && awake && !touching
}

// ---- the complication chooser (iqm.java:61-85, inn.java:118-126) ----------------------

/* The app each data source belongs to, as the chooser's second line (stock shows
 * the providing app: Health, Weather, Calendar, Clock, Settings for the system
 * providers, stock-providers.tsv). The values are the string ids' source texts. */
var APPS = {
    date: "settings", daymonth: "settings", datemonth: "settings", weekday: "settings", timedate: "settings",
    battery: "settings", phonebattery: "settings", notifications: "settings",
    worldclock: "settings", app: "settings",
    steps: "health", heartrate: "health", health: "health",
    weather: "weather", uv: "weather", precipitation: "weather", aqi: "weather", sun: "weather",
    nextevent: "calendar",
    alarm: "clock", timer: "clock", stopwatch: "clock", moon: "clock", countdown: "clock",
    media: "media", assistant: "assistant", map: "maps", contact: "contacts"
}
function appOf(kind) {
    return APPS.hasOwnProperty(kind) ? APPS[kind] : "settings"
}

/* The data types (A-14). Stock lists only the sources that can fill the slot: the chooser asks the
 * system for getSupportedComplicationDataSources(the slot's supported types) (SysUI inn.java:110-126,
 * WearSdkComplicationBackend.getComplicationProviderApps); a source is listed when one of the types it
 * declares is one the slot takes. The types each source declares are its stock provider's
 * (stock-providers.tsv; ICON is MONOCHROMATIC_IMAGE; Phone battery, ours only, as Battery). */
var SOURCE_TYPES = {
    date: ["SHORT_TEXT"], daymonth: ["SHORT_TEXT"], datemonth: ["SHORT_TEXT"], weekday: ["SHORT_TEXT"],
    timedate: ["SHORT_TEXT"], worldclock: ["SHORT_TEXT"],
    steps: ["RANGED_VALUE", "SHORT_TEXT", "GOAL_PROGRESS"], heartrate: ["RANGED_VALUE", "SHORT_TEXT"],
    distance: ["RANGED_VALUE", "SHORT_TEXT", "GOAL_PROGRESS"], calories: ["GOAL_PROGRESS", "RANGED_VALUE", "SHORT_TEXT"],
    floors: ["RANGED_VALUE", "SHORT_TEXT", "GOAL_PROGRESS"], azm: ["GOAL_PROGRESS", "RANGED_VALUE", "SHORT_TEXT"],
    exercisedays: ["WEIGHTED_ELEMENTS"],
    battery: ["RANGED_VALUE", "SHORT_TEXT", "LONG_TEXT", "MONOCHROMATIC_IMAGE"],
    phonebattery: ["RANGED_VALUE", "SHORT_TEXT", "LONG_TEXT", "MONOCHROMATIC_IMAGE"],
    notifications: ["SHORT_TEXT", "MONOCHROMATIC_IMAGE"], health: ["MONOCHROMATIC_IMAGE", "SHORT_TEXT"],
    exercise: ["SHORT_TEXT", "MONOCHROMATIC_IMAGE"],
    weather: ["SHORT_TEXT", "LONG_TEXT", "SMALL_IMAGE", "RANGED_VALUE"], uv: ["SHORT_TEXT", "RANGED_VALUE"],
    precipitation: ["SHORT_TEXT", "RANGED_VALUE"], aqi: ["SHORT_TEXT", "RANGED_VALUE"],
    sun: ["SHORT_TEXT", "MONOCHROMATIC_IMAGE"], moon: ["SHORT_TEXT", "LONG_TEXT"],
    nextevent: ["SHORT_TEXT", "LONG_TEXT", "MONOCHROMATIC_IMAGE"],
    alarm: ["SHORT_TEXT"], timer: ["SHORT_TEXT"], stopwatch: ["SHORT_TEXT"], countdown: ["SHORT_TEXT", "LONG_TEXT"],
    media: ["LARGE_IMAGE", "SMALL_IMAGE", "LONG_TEXT"], assistant: ["MONOCHROMATIC_IMAGE", "SMALL_IMAGE", "LONG_TEXT"],
    app: ["SMALL_IMAGE", "LONG_TEXT"]
}
/* The types a slot takes, by its shape, as the Pixel faces declare their slots (watch_face_*.xml, RWF
 * strings.xml:86,100,172; watchface-catalogue AUDIT 2.5): a round bulb, a line, an edge arc, the long slot
 * (Utility's bottom), Track's ring (watch_face_soloring.xml: RANGED_VALUE only). The older faces' "circle"
 * is a bulb. A slot may name its own list (EosSlot supportedTypes). */
var BULB_TYPES = ["WEIGHTED_ELEMENTS", "GOAL_PROGRESS", "RANGED_VALUE", "SHORT_TEXT", "MONOCHROMATIC_IMAGE", "SMALL_IMAGE"]
var SLOT_TYPES = {
    bulb: BULB_TYPES,
    circle: BULB_TYPES,
    text: ["SHORT_TEXT", "WEIGHTED_ELEMENTS", "GOAL_PROGRESS", "RANGED_VALUE", "MONOCHROMATIC_IMAGE"],
    arc: ["WEIGHTED_ELEMENTS", "GOAL_PROGRESS", "RANGED_VALUE", "SHORT_TEXT"],
    long: ["LONG_TEXT"],
    ring: ["RANGED_VALUE"]
}
// the types of a slot: its own list when it names one, else its shape's (null: a shape we do not know)
function slotTypes(shape, declared) {
    if (declared && declared.length !== undefined && declared.length > 0)
        return declared
    return SLOT_TYPES.hasOwnProperty(shape) ? SLOT_TYPES[shape] : null
}
// whether a source (its kind, "app:x" is "app") can fill a slot that takes `types` (null: any); Empty always
function accepts(kind, types) {
    var k = String(kind)
    var at = k.indexOf(":")
    if (at >= 0)
        k = k.slice(0, at)
    if (k === "empty" || !types)
        return true
    var mine = SOURCE_TYPES.hasOwnProperty(k) ? SOURCE_TYPES[k] : null
    if (!mine)
        return true
    for (var i = 0; i < mine.length; i++)
        if (types.indexOf(mine[i]) >= 0)
            return true
    return false
}

/* The chooser's order: "Empty" first, then the sources alphabetically by their
 * (translated) name; the collator of the user's language decides (stock sorts the
 * flat list with Collator.getInstance(), iqm.java:73). `nameOf(id)` is the name.
 * `types` (optional): the slot's types; a source that fills none of them is left out. */
function chooserOrder(ids, nameOf, types) {
    var rest = []
    for (var i = 0; i < ids.length; i++)
        if (ids[i] !== "empty" && accepts(ids[i], types))
            rest.push(ids[i])
    rest.sort(function (a, b) {
        var x = String(nameOf(a))
        var y = String(nameOf(b))
        return x.localeCompare(y)
    })
    return ids.indexOf("empty") >= 0 ? ["empty"].concat(rest) : rest
}

// where the chooser opens: scrolled to the source in the slot (the first row when it is not listed);
// a source with its choice ("worldclock:+0530") opens on its kind
function chooserIndex(order, current) {
    var s = String(current)
    var at = s.indexOf(":")
    var i = order.indexOf(at < 0 ? s : s.slice(0, at))
    return i < 0 ? 0 : i
}

// ---- the sources that need a choice first (watchface-catalogue-20, -21) ----------------
//
// World clock, Countdown to date and App shortcut (ComplicationSources.parameterised) are in
// the chooser with the others; a tap opens their second page, whose choice is the source
// stored for the slot: "worldclock:<zone id>", "countdown:<YYYY-MM-DD>", "app:<desktop>".

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

/* The World clock's zone chooser (A-13), as stock's WorldClockProviderConfigActivity: a list of the
 * regions (isn.java: sorted by their names with the locale's collator), then the zones of the region
 * as "City (CODE)" (iqj: sorted by their offset now, then by name; WorldZones.zones gives that order).
 * keys: the regions the zone list has; names: key -> the region's name. */
var REGION_PREFIX = "worldregion:"
function regionRows(keys, names) {
    var rows = (keys || []).map(function (k) {
        return { value: REGION_PREFIX + k, title: names && names[k] ? names[k] : k, icon: "ms-language" }
    })
    rows.sort(function (a, b) { return a.title.localeCompare(b.title) })
    return rows
}
function isRegionRow(value) { return String(value).indexOf(REGION_PREFIX) === 0 }
function regionOfRow(value) { return String(value).slice(REGION_PREFIX.length) }
/* The Favorite contact's choice (A-16, stock ACTION_CHOOSE_CONTACTS_COMPLICATION): the contacts of the
 * Contacts module (cached list [{ key, name, starred }]), starred first, then by name.
 * param(key, name) -> the source's parameter (ComplicationSources.contactParam). */
function contactRows(contacts, param) {
    var l = (contacts || []).filter(function (c) { return c && c.key && c.name })
    l.sort(function (a, b) {
        if ((a.starred === true) !== (b.starred === true))
            return a.starred === true ? -1 : 1
        return String(a.name).localeCompare(String(b.name))
    })
    return l.map(function (c) {
        return { value: "contact:" + param(c.key, c.name), title: String(c.name), icon: "ios-contact" }
    })
}
// zones: [{ id, city, code }] (WorldZones.zones)
function zoneRows(zones) {
    return (zones || []).map(function (z) {
        return { value: "worldclock:" + z.id, title: z.city + " (" + z.code + ")", icon: "ms-language" }
    })
}

// the day -> the source: "countdown:2026-12-25" (month 1-12)
function countdownParam(year, month, day) {
    return "countdown:" + year + "-" + pad2(month) + "-" + pad2(day)
}
// the day the date picker opens on: the slot's ("2026-12-25"), else `today`
function countdownDay(param, today) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(param))
    if (!m)
        return today
    return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}

/* The App shortcut's apps: the launcher's apps (items with filePath, title, iconId), by name
 * as the app list sorts them; the source names the desktop file: "app:asteroid-music" */
function appId(filePath) {
    var f = String(filePath).split("/").pop()
    return f.slice(-8) === ".desktop" ? f.slice(0, -8) : f
}
function appRows(items) {
    var rows = []
    for (var i = 0; i < items.length; i++) {
        var it = items[i]
        if (!it || !it.filePath)
            continue
        rows.push({ value: "app:" + appId(it.filePath), title: String(it.title || appId(it.filePath)),
                    icon: it.iconId ? String(it.iconId) : "ios-apps" })
    }
    rows.sort(function (a, b) { return a.title.localeCompare(b.title) })
    return rows
}
// the row of the value (0 when it is not listed)
function rowIndex(rows, value) {
    for (var i = 0; i < rows.length; i++)
        if (rows[i].value === value)
            return i
    return 0
}

// ---- the system theme follows the face (jbz.java:136-146, DynamicColorOverlayModule) ----

/* The colour a face gives the system theme: its own `seedColor` property when it
 * declares one, else the colour its preview was sampled to (FACE_COLORS, made once
 * from the shipped previews), else "" (no colour: the theme falls back to the
 * default seed). `declared` is the face item's seedColor ("" or a colour string). */
// (the dominant saturated colour of the shipped preview: hue histogram weighted by saturation x value;
// the white and grey faces have none and leave the theme on its default seed)
var FACE_COLORS = {
    "002-analog-70s-classic": ["#ee0b0b"],
    "005-analog-circle-shades": ["#c80606"],
    "006-analog-weather-satellite": ["#1ea46e"],
    "008-numerals-duo-synth-neon-green": ["#0de9f8"],
    "009-analog-scientific-v2": ["#0792e7"],
    "010-analog-aviator": ["#d2b31a"],
    "011-bold-hour-bebas": ["#6487ad"],
    "012-analog-words": ["#f70000"],
    "013-analog-nordic": ["#f30101"],
    "014-analog-50s-americana": ["#f20202"],
    "015-funky-town-words": ["#ff3466"],
    "017-contemporary-digital-rings": ["#e4b90e"]
}

function stemOf(file) {
    return String(file).split("/").pop().replace(/\.qml$/, "")
}
function normalColor(c) {
    var s = String(c === undefined || c === null ? "" : c)
    var m = /^#([0-9a-fA-F]{6})$/.exec(s)
    if (m)
        return "#" + m[1].toLowerCase()
    m = /^#([0-9a-fA-F]{2})([0-9a-fA-F]{6})$/.exec(s)   // #AARRGGBB, as Qt writes a color
    if (m)
        return "#" + m[2].toLowerCase()
    return ""
}
function faceColors(file, declaredSeed, declaredAccent) {
    var seed = normalColor(declaredSeed)
    var accent = normalColor(declaredAccent)
    if (seed === "") {
        var t = FACE_COLORS[stemOf(file)]
        if (t) {
            seed = normalColor(t[0])
            accent = t.length > 1 ? normalColor(t[1]) : ""
        }
    }
    return { seed: seed, accent: seed === "" ? "" : accent }
}

/* Whether the colours go to the theme now: stock applies them at once on the
 * face, and on the way back to the face otherwise; never in the always-on
 * screen or with the display off (no work there). */
function reportNow(awake, ambient) {
    return awake && !ambient
}
