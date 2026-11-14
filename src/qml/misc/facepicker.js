/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The rules and numbers of the watch face picker (W2-launcher-face-picker),
 * as plain functions: the face long press, the favourites list, the picker
 * geometry and the animations of stock Wear OS (CP3A, SysUI managementui).
 * Pixels are the stock px of the 384 px screen (1 dp = 2 px); the QML files
 * scale them with width / 384.
 */

// ---- the long press on the face (face-interaction-01, -02, -03) ------------

// Android's long-press timeout (def_long_press_timeout_millis 400, hun.java:27-29), seconds
var LONG_PRESS_S = 0.4
// the centre circle: hypot(nx, ny) <= 0.6, nx and ny = -1..1 across the screen (hum.java:31)
var LONG_PRESS_RADIUS = 0.6

// a long press that starts at (x, y) of a w x h face counts (hum.java:17-37)
function longPressInside(x, y, w, h) {
    var nx = (x - w / 2) * 2 / w
    var ny = (y - h / 2) * 2 / h
    return Math.sqrt(nx * nx + ny * ny) <= LONG_PRESS_RADIUS
}

// the radius of that circle in px of a screen w px wide (115.2 on the eos)
function longPressRadius(w) { return LONG_PRESS_RADIUS * w / 2 }

/* Whether a long press opens the picker: the display was on (not asleep, not
 * the always-on screen) when the finger came down: a touch that woke the
 * watch is no long press (stock: "DelayAwareLongPress", a down event older
 * than the timeout is ignored, hum.java / hun.java:33-49); and no mode that
 * claims the long press. Returns "picker", "bedtime" (Bedtime mode: its
 * settings open instead, ked.java:391-407) or "" (nothing). */
function longPressAction(awakeAtDown, ambient, bedtime, firstRun) {
    if (!awakeAtDown || ambient || firstRun)
        return ""
    return bedtime ? "bedtime" : "picker"
}

// ---- the picker's geometry (face-interaction-07, -12, -13, -14, -15, -16, -17) ----

var ITEM_FRACTION = 0.62            // preview 62 % of the width: 238 px (ManagementView.java:702-722)
var ITEM_PADDING_DP = 8             // managementui_items_padding, each side
var BORDER_DP = 2                   // managementui_items_border_width
var OFFSET_Y_DP = 4                 // managementui_animation_offsety: the pivot is 4 dp above the centre
var NAME_TOP_PERCENT = 2.1          // managementui_top_margin
var NAME_SWEEP = 90                 // managementui_max_sweep_degrees
var NAME_SIZE_DP = 15               // managementui_title_non_scalable_font_size (not scaled)
var RING_COLOR = "#202124"          // wear_material_gray_900 (managementui_border_color)
var PLACEHOLDER = "#32000000"       // w3_watch_face_picker_placeholder_bg
var NAME_SHADOW = "#dd000000"       // managementui_item_title_shadow_color
var ALL_RING_COLOR = "#404040"      // managementui_all_border_color (w2_cw_gray_25)

// the preview diameter for a screen of w px: 238 on 384
function itemSize(w) { return Math.round(w * ITEM_FRACTION) }
// the pitch of the carousel: preview + 2 x (4 px ring + 16 px padding) = 278
function pitch(w) { return itemSize(w) + 2 * (BORDER_DP + ITEM_PADDING_DP) * w / 192 }
// the zoom the carousel starts at: the centre preview exactly covers the face: 384 / 238 = 1.613
function openScale(w) { return w / itemSize(w) }
// the alpha of an item whose centre is distance px from the middle (ManagementView.java:499-508)
function itemAlpha(distance, itemWidth) {
    return 1 - 0.5 * Math.min(1, Math.abs(distance) / itemWidth)
}
// the zoom scale between the face (0) and the settled carousel (1)
function zoomScale(w, zoom) {
    var s = openScale(w)
    return s + (1 - s) * zoom
}

// timing, ms (ManagementView.java:563-599, 740-787)
var OPEN_MS = 266
var CLOSE_MS = 300
var NAMES_HIDDEN_MS = 166           // names and delete buttons hidden, then fade in
var NAMES_FADE_MS = 100
var TAP_WAIT_MS = 200               // a tap on a side face: scroll to it, wait, apply
var SCROLL_MS = 250                 // the carousel's own move
var IDLE_MS = 15000                 // iaf.java:49-57
var LIFT_SCALE = 1.1                // the moved item (kdu.java:463-505)
var LIFT_MS = 150
var SETTLE_MS = 300
var BUTTONS_CHANGE_MS = 375         // ChangeBounds and Slide of the arrow buttons
var BUTTONS_FADE_MS = 450

// the add list (face-interaction-18)
var ADD_SCALE_FROM = 0.25           // sysui_common_activity_away_scale
var ADD_SCALE_MS = 250
var ADD_ALPHA_MS = 75
var ADD_FLASH_COLOR = "#12ffffff"
var ADD_FLASH_HOLD_MS = 75
var ADD_FLASH_FADE_MS = 750
var ADD_FLY_MS = 300                // the preview flies into its slot
var ADD_LIST_FADE_MS = 300
var ADD_ROW_DELAY_MS = 150
var ADD_ROW_MS = 300
var ADD_ROW_FROM = 0.15             // the bottom row slides up from 15 % of the height

// ---- the crown and the idle timer (face-interaction-10, -11) -----------------

/* The crown button in the picker: what it does. `view` is "carousel", "add"
 * (the add list) or "editor"; `centred` the item in the middle ("add" for the
 * Add new item, "" while a face loads, else its id). Returns "apply" (put the
 * centred face on and close), "close" (close without a change), "back"
 * (from the add list to the carousel), "editor" (the editor's own back). */
function crownAction(view, centred) {
    if (view === "add")
        return "back"
    if (view === "editor")
        return "editor"
    if (centred === "" || centred === "add")
        return "close"
    return "apply"
}

/* What the 15 s idle timer does (iaf.java:49-57, kdu.java:551-558): the
 * centred face is applied and the picker closes; with the add list open it
 * closes without applying; the editor stops it. */
function idleAction(view, centred) {
    if (view === "editor")
        return "none"
    if (view === "add")
        return "close"
    return centred === "" || centred === "add" ? "close" : "apply"
}

// ---- the favourites (face-interaction-18, -20, watchface-catalogue-12) ------

// The fresh watch's carousel, in order (watchface-catalogue-12): the face's
// name, after its number, must start with one of these. The stock eight are
// Utility, Analog Bold, Adventure, Analog Arcs, Index, Large Scale, Classic,
// Everyday; ours are the faces of the catalogue that stand in for them.
var DEFAULT_FACES = ["modular", "bold-numerals", "classic", "large", "list", "stacked",
                     "default-digital", "analog-aviator"]

function stemOf(file) {
    return String(file).split("/").pop().replace(/\.qml$/, "")
}
function plainName(file) {
    return stemOf(file).replace(/^[0-9]+-/, "")
}
function matchesDefault(file, key) {
    var n = plainName(file)
    return n === key || n.indexOf(key + "-") === 0
}

// "id:file" -> {id, file}; broken entries and repeated ids are dropped
function parse(list) {
    var out = []
    var seen = {}
    var l = list || []
    if (typeof l === "string")
        l = l === "" ? [] : [l]
    for (var i = 0; i < l.length; i++) {
        var s = String(l[i])
        var c = s.indexOf(":")
        if (c <= 0 || c === s.length - 1)
            continue
        var id = s.slice(0, c)
        if (seen[id])
            continue
        seen[id] = true
        out.push({ id: id, file: s.slice(c + 1) })
    }
    return out
}
function serialize(entries) {
    var out = []
    for (var i = 0; i < entries.length; i++)
        out.push(entries[i].id + ":" + entries[i].file)
    return out
}
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b) }

function indexOfId(entries, id) {
    for (var i = 0; i < entries.length; i++)
        if (entries[i].id === id)
            return i
    return -1
}
function indexOfFile(entries, file) {
    for (var i = 0; i < entries.length; i++)
        if (entries[i].file === file)
            return i
    return -1
}

// a dconf-safe id: the face's name, with -2, -3 for a face that is a favourite twice
function newId(entries, file) {
    var base = stemOf(file).toLowerCase().replace(/[^a-z0-9_-]/g, "-")
    if (base === "")
        base = "face"
    var id = base
    for (var n = 2; indexOfId(entries, id) >= 0; n++)
        id = base + "-" + n
    return id
}

/* The carousel of a fresh watch: DEFAULT_FACES that are installed, in that
 * order, and the face on the watch (always a favourite). `installed` is the
 * list of face file URLs. */
function defaults(installed, currentFile) {
    var out = []
    for (var k = 0; k < DEFAULT_FACES.length; k++)
        for (var i = 0; i < installed.length; i++)
            if (matchesDefault(installed[i], DEFAULT_FACES[k]) && indexOfFile(out, installed[i]) < 0) {
                out.push({ id: newId(out, installed[i]), file: installed[i] })
                break
            }
    if (currentFile && indexOfFile(out, currentFile) < 0)
        out.push({ id: newId(out, currentFile), file: currentFile })
    return out
}

/* The list as it must be now: a favourite whose face is gone from the system
 * folder or the user's folder is dropped (not the face on the watch), the
 * face on the watch is always in it, and `currentId` names its entry.
 * `gone(file)` says whether a face file has been removed. Returns
 * {entries, currentId}. */
function settle(entries, currentId, currentFile, gone) {
    var out = []
    for (var i = 0; i < entries.length; i++)
        if (entries[i].file === currentFile || !(gone && gone(entries[i].file)))
            out.push(entries[i])
    var at = indexOfId(out, currentId)
    if (at < 0 || out[at].file !== currentFile) {
        at = indexOfFile(out, currentFile)
        if (at < 0 && currentFile) {
            out.push({ id: newId(out, currentFile), file: currentFile })
            at = out.length - 1
        }
    }
    return { entries: out, currentId: at >= 0 ? out[at].id : "" }
}

// a face added at the end (the add list): {entries, id}
function add(entries, file) {
    var out = entries.slice()
    var id = newId(out, file)
    out.push({ id: id, file: file })
    return { entries: out, id: id }
}

/* A favourite removed (the last one cannot be): {entries, currentId, applied}.
 * Removing the face on the watch makes the next one (same index, or the new
 * last) the face on the watch (grc.java:104-141). */
function remove(entries, id, currentId) {
    var at = indexOfId(entries, id)
    if (at < 0 || entries.length <= 1)
        return { entries: entries, currentId: currentId, applied: false, ok: false }
    var out = entries.slice()
    out.splice(at, 1)
    if (id !== currentId)
        return { entries: out, currentId: currentId, applied: false, ok: true }
    return { entries: out, currentId: out[Math.min(at, out.length - 1)].id, applied: true, ok: true }
}

// the left or right arrow: the favourite swaps with its neighbour (dir -1, +1)
function canMove(entries, id, dir) {
    var at = indexOfId(entries, id)
    return at >= 0 && at + dir >= 0 && at + dir < entries.length
}
function move(entries, id, dir) {
    if (!canMove(entries, id, dir))
        return entries
    var out = entries.slice()
    var at = indexOfId(entries, id)
    var t = out[at]
    out[at] = out[at + dir]
    out[at + dir] = t
    return out
}

// ---- names (face-interaction-14, watchface-catalogue-11) --------------------

// The faces of the image. A face this table does not know gets its file
// name's words, in title case ("020-modular-grid" is "Modular Grid").
var NAMES = {
    "000-default-digital": "Digital", "001-words-worte-palabras-mots": "Words",
    "002-analog-70s-classic": "Seventies", "003-alternative-digital-2": "Split",
    "004-alternative-scifi": "Sci-fi", "005-analog-circle-shades": "Bubbles",
    "006-analog-weather-satellite": "Satellite", "007-digital-outfit": "Outfit",
    "008-numerals-duo-synth-neon-green": "Neon", "009-analog-scientific-v2": "Scientific",
    "010-analog-aviator": "Aviator", "011-bold-hour-bebas": "Bold Hour",
    "012-analog-words": "Petals", "013-analog-nordic": "Nordic",
    "014-analog-50s-americana": "Americana", "015-funky-town-words": "Funky",
    "016-masked-spartan": "Spartan", "017-contemporary-digital-rings": "Rings"
}
function displayName(file) {
    var stem = stemOf(file)
    if (NAMES.hasOwnProperty(stem))
        return NAMES[stem]
    var words = plainName(file).split(/[-_ ]+/)
    var out = []
    for (var i = 0; i < words.length; i++)
        if (words[i] !== "")
            out.push(words[i].charAt(0).toUpperCase() + words[i].slice(1))
    return out.join(" ")
}

// ---- the per-favourite style (face-interaction-20) ---------------------------

var STYLE_KEY = "/org/asteroidos/watchface/style/"
var COMPLICATIONS_KEY = "/org/asteroidos/watchface/complications/"
function styleKey(id) { return id === "" ? "" : STYLE_KEY + id }
function complicationsKey(id) { return COMPLICATIONS_KEY + id }

// the style a favourite stores: a JSON object, {} when it has none yet
function parseStyle(s) {
    if (typeof s !== "string" || s === "")
        return {}
    try {
        var o = JSON.parse(s)
        return o && typeof o === "object" ? o : {}
    } catch (e) {
        return {}
    }
}
