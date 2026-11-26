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
// the previews' centre on the 384 px screen: the Wear OS 6 emulator's ring is x 69-314, y 48-293 (S15, its
// pixel centre 170.5; the QML box 48-294), 21 px above the middle (N61-35)
var PREVIEW_CY_PX = 171
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
// the centre of the previews at rest on a screen h px high: 171 on 384
function previewCy(h) { return PREVIEW_CY_PX * h / 384 }
// the alpha of an item whose centre is distance px from the middle (ManagementView.java:499-508)
function itemAlpha(distance, itemWidth) {
    return 1 - 0.5 * Math.min(1, Math.abs(distance) / itemWidth)
}
// how far the open is, from the previews' scale: 0 at the face's size (openScale), 1 at the carousel's (above 1
// while the scale spring overshoots)
function openProgress(w, scale) {
    var s = openScale(w)
    return (s - scale) / (s - 1)
}

/* The open (Wear OS 6 emulator, motion M11, N61-36): a cut from the face to its 10:09 preview at full size (the
 * centre preview exactly covers the screen), held 30 ms (M11: the ring leaves the bezel about 30 ms after the cut;
 * the springs below fit the frames with that start, RMS 6.5 px against 16 px without it), then two underdamped
 * springs: the previews' scale 1.613 -> 1
 * (screen 1 -> 0.69, dipping to 0.66: 6 % overshoot, settled in 259 ms) on zeta 0.67, k 627, and their centre
 * from the screen's middle (192) up to PREVIEW_CY_PX on zeta 0.53, k 700 (13-14 % overshoot, 320-340 ms).
 * The names, the chip and the arrows are hidden for 100 ms after the cut and full 50 ms later. Leaving without
 * a change (back) is a cut to the live face, no zoom and no fade (1-2 black frames on the emulator). The tile
 * editor is the same management view and moves the same way. */
var OPEN_HOLD_MS = 30
var OPEN_SCALE_STIFFNESS = 627
var OPEN_SCALE_DAMPING = 0.67
var OPEN_Y_STIFFNESS = 700
var OPEN_Y_DAMPING = 0.53
// the springs come to rest within these (the scale: 1/1000 of it; the centre: 0.1 px)
var OPEN_SCALE_THRESHOLD = 0.001
var OPEN_Y_THRESHOLD = 0.1

// timing, ms (ManagementView.java:563-599, 740-787)
// a face put on (a tap, the crown, the idle timeout): the carousel grows back into it (CP3A, not captured)
var CLOSE_MS = 300
var NAMES_HIDDEN_MS = 100           // names, chip and arrows hidden after the cut, then fade in
var NAMES_FADE_MS = 50
var TAP_WAIT_MS = 200               // a tap on a side face: scroll to it, wait, apply
var SCROLL_MS = 250                 // the carousel's own move
var IDLE_MS = 15000                 // iaf.java:49-57
var LIFT_SCALE = 1.1                // the moved item (kdu.java:463-505)
var LIFT_MS = 150
var SETTLE_MS = 300
var BUTTONS_CHANGE_MS = 375         // ChangeBounds and Slide of the arrow buttons
var BUTTONS_FADE_MS = 450
// the bottom row (management_ui_root_layout.xml:31-65, values-round/dimens.xml): the chip 52 x 32 dp in the
// middle, the arrows 32 dp, 4 dp from it (managementui_rearrange_padding_settings); the area is 8 dp of padding
// on top, 13 dp of margin (managementui_rearrange_circular_settings), the 32 dp buttons, 5 dp of padding below
var ROW_GAP_DP = 4
var ROW_HEIGHT_DP = 58
// the propagation delays of the buttons' Slide (ibj.java); a change starts each button at its delay less the
// smallest delay of the buttons that change with it (rowWaits)
var ROW_CHIP_WAIT_MS = 75
var ROW_ARROW_WAIT_MS = 150

/* The waits of the row's slides for one change from `from` to `to` ({ left, chip, right }: shown or not).
 * Stock sets the arrows and the chip of one centred item together (kdu.java:221-240, iaf.java:188-199), each
 * call begins the same delayed transition (ManagementView.java:180-191: one beginDelayedTransition per frame),
 * and Transition.createAnimators starts every animator of the Slide at its propagation delay less the smallest
 * delay among them (AOSP android.transition.Transition; the androidx copy in Maps keeps it:
 * com.google.android.apps.maps/sources/androidx/transition/Transition.java:629, 686, 732). Only the buttons
 * whose visibility changes get a Slide animator. Returns { left, chip, right }: the wait in ms of each button
 * that changes, -1 for one that does not. */
function rowWaits(from, to) {
    var base = { left: ROW_ARROW_WAIT_MS, chip: ROW_CHIP_WAIT_MS, right: ROW_ARROW_WAIT_MS }
    var keys = ["left", "chip", "right"]
    var min = -1
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i]
        if (from[k] !== to[k] && (min < 0 || base[k] < min))
            min = base[k]
    }
    var out = {}
    for (var j = 0; j < keys.length; j++) {
        var q = keys[j]
        out[q] = from[q] !== to[q] ? base[q] - min : -1
    }
    return out
}

// the glyphs of the bottom row, CP3A's vector drawables (sysui res/drawable): the arrows are
// quantum_gm_ic_arrow_left/right_vd_theme_24 (management_ui_root_layout.xml:47, 62), a 24 x 24 viewport in a
// 24 dp box; the chip shows pencil_icon.xml (iaf.java:277-283, WearChipButton.r()), a 20 x 18 viewport drawn
// even-odd (an outline), inset 2 dp and 3 dp in its 24 dp box
var GLYPH_BOX_DP = 24
var GLYPH_ARROW_LEFT = "M14,7l-5,5 5,5V7z"
var GLYPH_ARROW_RIGHT = "M10,17l5,-5 -5,-5v10z"
var PENCIL_W_DP = 20
var PENCIL_H_DP = 18
var GLYPH_PENCIL = "M18.4088,1.9375L17.0588,0.5875C16.2788,-0.1925 15.0088,-0.1925 14.2288,0.5875L0.9988,13.8175"
                   + "V17.9975H5.1788L18.4088,4.7675C19.1988,3.9875 19.1988,2.7175 18.4088,1.9375Z"
                   + "M4.4088,16.0575L2.9988,15.9975V14.6375L12.8188,4.8175L14.2288,6.2275L4.4088,16.0575Z"

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

/* The preview that flies in from the add list is round, as stock's: stock flies a bitmap of the list item's
 * preview frame (a disc, its corners transparent) into the carousel item's border (ManagementView.java:289-380).
 * The flyer's pictures are square (the wallpaper snapshot, a shipped picture such as 026's photo), and a mask
 * of black corners (RoundMask) would hide the delete button and the arrows it flies over, so the flyer cuts
 * them round with plain clips: centred rectangles, k from the middle out, each as wide as the circle at y_k and
 * as tall as 2 y_(k+1). Together they cover the disc of radius r; the corner of one lies at
 * sqrt(r^2 - y_k^2 + y_(k+1)^2) from the centre, r + margin when y_(k+1)^2 = y_k^2 + 2 r margin + margin^2,
 * so nothing is drawn further out than the ring covers. Sizes are fractions of the picture's side
 * (r = 0.5); each rectangle { width, height }.
 */
function roundCut(margin) {
    if (!(margin > 0))
        return [{ width: 1, height: 1 }]     // no room past the circle (or no size yet): the square, uncut
    var r = 0.5
    var c = 2 * r * margin + margin * margin
    var out = []
    var y = 0
    while (y < r) {
        var next = Math.min(r, Math.sqrt(y * y + c))
        out.push({ width: 2 * Math.sqrt(r * r - y * y), height: 2 * next })
        y = next
    }
    return out
}

/* The add list's swipe to dismiss. Stock wraps the list in a SwipeDismissFrameLayout
 * (management_ui_root_layout.xml:66-71, ManagementView.java:954-958; androidx's, as decompiled in sysui
 * gar.java / gax.java). While the finger moves right by p of the width the list is scaled 1 - 0.3 p about its
 * centre and moved right by (1 - scale) W / 2, so its right edge stays put, and darkened by min(0.3, p / 2)
 * (gar.java:174-184, gax.java:116-127). On release it goes when it was dragged past 0.33 of the width and the
 * UP is not left of the last MOVE (not moving back, gar.java:192), or on a fling right of
 * config_viewMinFlingVelocity (500 dp/s on a watch, framework values-watch/dimens.xml) faster than up or
 * down; a fling back of that speed keeps it
 * (gar.java:186-194). Then a spring 1.0/600, minimum visible change 0.5 px, from where it is at the finger's
 * speed to the width (gone: the carousel is back, iax.java:15-26) or to 0 (gar.java:201-250,
 * gax.java:51-67); along it the scale is 1 - 2 x / W held in 0.7 .. 1 and the dim follows the largest
 * progress reached (gax.java:69-84). */
var ADD_DISMISS_SCALE = 0.3
var ADD_DISMISS_MIN_SCALE = 0.7
var ADD_DISMISS_MAX_DIM = 0.3
var ADD_DISMISS_COMMIT = 0.33
var ADD_DISMISS_FLING_DP = 500
var ADD_DISMISS_STIFFNESS = 600
var ADD_DISMISS_DAMPING = 1.0
var ADD_DISMISS_MIN_CHANGE = 0.5

// the dim of the list at progress p
function addDismissDim(p) {
    return Math.max(0, Math.min(ADD_DISMISS_MAX_DIM, p / 2))
}
// the scale while the finger moves it by p of the width
function addDismissDragScale(p) {
    return 1 - ADD_DISMISS_SCALE * Math.max(0, p)
}
// the scale on the spring, at x px of a width w
function addDismissSpringScale(x, w) {
    return Math.max(ADD_DISMISS_MIN_SCALE, Math.min(1 - 2 * x / w, 1))
}
// whether a swipe of dx px released at vx, vy px/s (movingBack: the release is left of the last move, gar.java:192)
// dismisses the list
// of width px, with dpPx px per dp
function addDismissCommits(dx, vx, vy, movingBack, width, dpPx) {
    var fling = ADD_DISMISS_FLING_DP * dpPx
    var go = (dx > width * ADD_DISMISS_COMMIT && !movingBack) || (vx >= fling && vx > Math.abs(vy))
    if (go && vx < -fling)
        go = false
    return go
}

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
// W3-launcher-faces left the list as it was: the faces it adds are found by these names
// (modular, bold-numerals, classic, large, list, stacked), and the user's rule is "do what
// stock does" (stock's favourites include the analog Analog Bold and Classic).
// The order of stock Wear OS 6's fresh carousel (S15: Concentric, Utility, Classic, ..., Big Time last):
// Concentric, the default face, leads, Modular stands in for Utility, Large for Big Time.
var DEFAULT_FACES = ["concentric", "modular", "classic", "bold-numerals", "list", "stacked",
                     "default-digital", "analog-aviator", "large"]

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

// ---- the 10:09 pictures of the carousel (N61-35) ------------------------------

/* Every carousel item, the face on the watch included, is the face drawn at 10:09 on Thursday 24 May (the Wear OS 6
 * emulator: S15, S15-b 'THU MAY 24 10:09'), never a snapshot of the face as it is now. An eos face (eoskit
 * EosFace, which has eosPreviewTime) is drawn once per favourite with the favourite's own style and complications
 * by FacePreviewRenderer, into the launcher's cache (FacePreviews) under renderKey(id); the upstream faces
 * (000-017 of the system folder, which read wallClock directly) show their shipped picture
 * (watchfaces-preview/384, the D60-28 GL renderer at 10:09). */
var SYSTEM_FACES = "file:///usr/share/asteroid-launcher/watchfaces/"
var FIRST_EOS_FACE = 18
function previewTime() { return new Date(2018, 4, 24, 10, 9, 0) }
// the cache file of a favourite's picture: "<id>-1009" (the files of the old live snapshots, "<id>", go at the
// next keepOnly)
function renderKey(id) { return id === "" ? "" : id + "-1009" }
// an upstream face of the system folder (000-017): the launcher never draws it at 10:09, its shipped picture is it
function upstreamFace(file) {
    var f = String(file)
    if (f.indexOf(SYSTEM_FACES) !== 0)
        return false
    var m = /^([0-9]+)-/.exec(f.slice(SYSTEM_FACES.length))
    return m !== null && parseInt(m[1], 10) < FIRST_EOS_FACE
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
// the default of a face's "seconds" option (facekit.js secondsDefault): undefined for a face without one
function secondsDefault(schema) {
    var s = schema || []
    for (var i = 0; i < s.length; i++)
        if (s[i].id === "seconds")
            return s[i].def === true
    return undefined
}

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
