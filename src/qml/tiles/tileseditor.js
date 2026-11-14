/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the tiles editor (W3-launcher-tiles-editor) as pure
 * functions, tested in tst_editor_rules.qml. TilesEditor.qml and
 * TileAddList.qml own the state; this file decides. The editor is stock
 * CP3A's ManagementView (SysUI managementui), the view the watch face picker
 * is made on too: the carousel, its zoom and its bottom row share the
 * numbers of facepicker.js (item 62 %, pitch 278 px, zoom 266 / 300 ms);
 * what only tiles have is here. Sizes are px on the 384 px Pixel Watch 2
 * screen (2 px per dp); `u` scales them for another width (width / 384). */

/* "maximum_tile_count" of the eos overlay (WearServicesOverlayTilesEos 15,
 * base 10; TileStoreImpl.java:163) */
var MAX_TILES = 15

/* the inactivity timeout: iaf.java:49-58, 15000 ms */
var IDLE_MS = 15000

/* cancel (the crown button; jif.java:196-209): the editor shrinks to 0.25
 * (sysui_common_activity_away_scale) in 350 ms on (0.2, 0, 0.2, 1) while it
 * fades out in 300 ms on fast_out_linear_in (0.4, 0, 1, 1) */
var CANCEL_SCALE = 0.25
var CANCEL_SCALE_MS = 350
var CANCEL_SCALE_CURVE = [0.2, 0, 0.2, 1, 1, 1]
var CANCEL_ALPHA_MS = 300
var CANCEL_ALPHA_CURVE = [0.4, 0, 1, 1, 1, 1]

/* a tap on a side card: it scrolls to the middle (the carousel's own 250 ms
 * move), the 200 ms start delay, then the zoom (iaf.java:249-262) */
var TAP_SCROLL_MS = 250
var TAP_WAIT_MS = 200

/* the card's controls, px */
var BUTTON = 64                     // managementui_rearrange_button_size 32 dp, delete button 32 dp
var BUTTON_TAP = 104                // managementui_rearrange_button_tap_target_size 52 dp
var DELETE_INSET = 8                // management_ui_tile_delete_button_margin_top / _end 4 dp
var MINUS_W = 32                    // ic_management_ui_delete.xml: M20,13H4v-2h16v2z = 16 x 2 dp
var MINUS_H = 4
var PLUS = 28                       // ic_management_ui_plus.xml 14 x 14 dp, bars 2 dp
var PLUS_BAR = 4
var ADD_BUTTON = 120                // managementui_add_more_favorites_button_width/height 60 dp
var ARROW_GAP = 30                  // managementui_rearrange_padding 7.5 dp each side of the middle: 15 dp apart
var ARROW_GAP_CHIP = 8              // managementui_rearrange_padding_settings 4 dp from the chip
var CHIP_W = 104                    // managementui_rearrange_chip_width 52 dp
var CHIP_H = 64
var BOTTOM = 10                     // managementui_bottom_button_margin 5 dp
var LIFT = 12                       // managementui_rearrange_circular 6 dp (no chip)
var LIFT_CHIP = 26                  // managementui_rearrange_circular_settings 13 dp (a chip)

/* the add list (managementui_all_*) */
var LIST_COLUMNS = 2
var LIST_PREVIEW = 160              // managementui_all_preview_size 80 dp
var LIST_RING = 4                   // managementui_all_preview_border_width 2 dp
var LIST_ICON = 32                  // managementui_all_attribution_icon_* 16 dp
var LIST_NAME_TOP = 12              // managementui_all_title_padding_top 6 dp
var LIST_NAME_BOTTOM = 32           // managementui_all_title_padding_bottom 16 dp
var LIST_TITLE_TOP = 2.08           // managementui_all_list_title_top_margin %
var LIST_BOTTOM = 0.3646            // managementui_all_list_bottom_padding_percent
var LIST_RING_COLOR = "#404040"     // managementui_all_border_color (w2_cw_gray_25)
var LIST_TOP = 64                   // the grid starts under the header (as the face list; inferred)

/* a move by `by` (+1 right, -1 left) of the tile at i among n: it wraps, the
 * first moved left becomes the last (jif.java:80-126). One tile: no move. */
function moveTarget(i, by, n) {
    if (n <= 1 || i < 0 || i >= n)
        return i
    return (i + by + n) % n
}

/* the arrows are there for two tiles or more (jif.java:247-249, :318-320) */
function arrowsVisible(n) {
    return n > 1
}

/* where an added tile goes: at the end, then it is centred (jif.java:542-544) */
function addIndex(n) {
    return n
}

/* what a tap on "Add new" does: nothing left to add ("none": "All widgets
 * in use", jif.java:521-524), at the limit ("full": "Carousel is full",
 * jif.java:526-529), else "list" opens the add list. `hiddenCount` is the
 * number of tiles not in the carousel. */
function addAction(shownCount, hiddenCount) {
    if (hiddenCount <= 0)
        return "none"
    if (shownCount >= MAX_TILES)
        return "full"
    return "list"
}

/* the middle card after removing tile `r` while `current` is the middle one
 * and `tilesAfter` tiles are left: a tile before the middle one moves it one
 * back; removing the middle tile centres the one that took its place ("Add
 * new", index tilesAfter, when it was the last); a tile after it changes
 * nothing. */
function indexAfterRemove(current, r, tilesAfter) {
    if (r < current)
        return current - 1
    if (r === current)
        return Math.min(r, tilesAfter)
    return current
}

/* the tile that the editor ends on when the middle card is `current` of
 * `tileCount` tiles (the "Add new" card ends on the last tile, -1: none) */
function endIndex(current, tileCount) {
    return current < tileCount ? current : tileCount - 1
}

/* What the crown button does, whatever the editor shows (the carousel, its
 * dialog or the add list): the editor is cancelled to the watch face, with
 * the cancel animation (jif.java:196-209 "Home button pressed -> Notifying
 * close to Watch Face"). */
function crownAction() {
    return "cancel"
}

/* What the inactivity timer does (iaf.java:49-58): closes on the middle tile,
 * from the carousel and from the add list. */
function idleAction() {
    return "close"
}

/* The bottom row, px, for a screen of width w x h. `chip`: the middle tile has
 * an edit chip, which the arrows then make room for. The chip's slot is always
 * the middle one; without a tile that has settings it is invisible and the
 * arrows are 30 px apart. Returns the arrows' and the chip's x, y. */
function row(w, h, chip, arrows) {
    var u = w / 384
    var b = BUTTON * u
    var bottom = BOTTOM * u
    var y = h - bottom - (chip ? LIFT_CHIP * u : LIFT * u) - b
    var chipW = CHIP_W * u
    var cx = (w - chipW) / 2
    var gap = chip ? ARROW_GAP_CHIP * u : ARROW_GAP * u / 2
    return {
        arrowY: y,
        left: { x: chip ? cx - gap - b : w / 2 - gap - b },
        right: { x: chip ? cx + chipW + gap : w / 2 + gap },
        chip: { x: cx, y: h - bottom - CHIP_H * u, w: chipW, h: CHIP_H * u },
        arrows: arrows
    }
}

/* the cell of the add list for a screen of width w, px: icon, preview in its
 * ring, the name under it */
function cell(w, captionLine) {
    var u = w / 384
    var ring = LIST_PREVIEW * u + 2 * LIST_RING * u
    return {
        icon: LIST_ICON * u,
        ring: ring,
        preview: LIST_PREVIEW * u,
        nameTop: LIST_NAME_TOP * u,
        nameBottom: LIST_NAME_BOTTOM * u,
        height: LIST_ICON * u + ring + LIST_NAME_TOP * u + captionLine + LIST_NAME_BOTTOM * u
    }
}

/* the tiles not in the carousel, in the registry's order */
function hiddenOf(ids, shown) {
    return ids.filter(function (t) { return shown.indexOf(t) < 0 })
}
