/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the tiles carousel (W2-launcher-tiles-carousel) as pure
 * functions, so they are unit tested (tst_pager.qml). PanelsGrid.qml owns
 * the state and the spring; this file decides. The carousel is a Compose
 * HorizontalPager of [face, tile 1 .. tile n] in a ring (stock CP3A SysUI
 * hjw/jmv/jnk/jmw/avl, the pager made in hjw.java:1747).
 *
 * Positions are in pages: q is the pager's continuous position in the
 * grid's "virtual columns" (0 the face, k tile k, -1 the last tile to the
 * left of the face, n + 1 the face again to the right of the last tile);
 * d is how far the content is shifted from the page it rests on, in pages,
 * positive when it was dragged right (the page on the left coming in).
 * Speeds are the finger's, px/s, positive to the right. */

/* ux.N(state, avl, null, nh.i(1.0f, 200.0f, null, 4), 0.35f) (hjw.java:1747):
 * a page change from a drag past 35 % of a page */
var SNAP_FRACTION = 0.35
/* kmy.java:65: a fling of 400 dp/s (800 px/s at 2 px per dp) or more
 * moves one page in its direction; the caller gives it in px/s of the
 * screen it is on (Theme.dp(FLING_DP_S)) */
var FLING_DP_S = 400
var FLING_PX_S = 800
/* the settle after a finger: spring(dampingRatio 1.0, stiffness 200) */
var SWIPE_SPRING = { dampingRatio: 1.0, stiffness: 200 }
/* a move the program asks for (the crown button back to the face):
 * animateScrollToPage's default spring(1.0, 1500) (jlt.java:27,106,
 * nh.java:300-310) */
var PROGRAMMATIC_SPRING = { dampingRatio: 1.0, stiffness: 1500 }
/* the face behind the pager zooms 1.0 -> 0.8 (lcl.java:85-91) while a black
 * layer fades in with alpha = the page offset (hjw.java:1402-1475) */
var FACE_ZOOM = 0.2
/* a long press on a tile opens the editor after the platform's long-press
 * timeout (jmc.java withTimeout(longPressTimeoutMillis);
 * def_long_press_timeout_millis 400, VALUES.tsv) */
var LONG_PRESS_MS = 400

function sign(x) { return x > 0 ? 1 : x < 0 ? -1 : 0 }
function clamp(x, lo, hi) { return Math.max(lo, Math.min(hi, x)) }

/* Where a released drag goes, as a step from the page it started on: -1 the
 * page on the left, 0 stays, 1 the page on the right. At most one page, from
 * the page the pager is nearest to (a flick works from where the finger
 * left the pages):
 *  - |v| >= the fling speed: one page in the finger's direction
 *  - else past SNAP_FRACTION of a page: the page that way
 * "flingPxS" is FLING_PX_S scaled to the display (Theme.dp(FLING_DP_S)). */
function releaseStep(d, v, flingPxS) {
    var fling = flingPxS === undefined ? FLING_PX_S : flingPxS
    var step = 0
    if (Math.abs(v) >= fling) {
        var nearest = Math.abs(d) >= 0.5 ? -sign(d) : 0
        step = nearest + (v < 0 ? 1 : -1)
    } else if (Math.abs(d) >= SNAP_FRACTION) {
        step = d < 0 ? 1 : -1
    }
    return clamp(step, -1, 1)
}

/* The real column (0 the face, 1..n the tiles) of a virtual column of a ring
 * of the face and n tiles */
function realCol(vcol, n) {
    var m = n + 1
    return ((vcol % m) + m) % m
}

/* How far the pager is from the face page, 0 (on it) to 1 (a page away or
 * more): what the face's zoom and black layer follow. Virtual columns 0 and
 * n + 1 are the face. */
function faceDistance(q, n) {
    if (n <= 0)
        return 0
    return clamp(Math.min(Math.abs(q), Math.abs(q - (n + 1))), 0, 1)
}

/* The face's scale: 1 - 0.2 x the distance; none with Reduce animations */
function faceScale(distance, reduceMotion) {
    return reduceMotion ? 1 : 1 - FACE_ZOOM * clamp(distance, 0, 1)
}

/* the black layer between the face and the tiles: alpha = the page offset */
function faceShade(distance) {
    return clamp(distance, 0, 1)
}

/* LinearOutSlowIn (0, 0, 0.2, 1): the icon's drop eases with it as the page
 * settles (jmg.d(): abu(0, 0, 0.2, 1)). Solved for x by bisection. */
function outSlowIn(t) {
    t = clamp(t, 0, 1)
    var lo = 0, hi = 1
    for (var i = 0; i < 30; i++) {
        var u = (lo + hi) / 2
        var x = 3 * u * (1 - u) * (1 - u) * 0 + 3 * u * u * (1 - u) * 0.2 + u * u * u
        if (x < t) lo = u; else hi = u
    }
    var s = (lo + hi) / 2
    return 3 * s * (1 - s) * (1 - s) * 0 + 3 * s * s * (1 - s) * 1 + s * s * s
}

/* The app icons at the top (TilesIndicator, hjw.java:247-440): the tile at
 * page p shows its app icon, 24 dp (the circle: 2x), 3 dp from the top. At
 * rest only the icon of the page shows. In a swipe the icons of the two
 * pages the pager is between slide with the pages, 18 dp apart; with the
 * face as the neighbour (it has no icon) the tile's icon is
 * 78.125 % of the width from the middle (tile_icon_intro_horizontal_padding)
 * and starts 20 % of the height lower (tile_icon_intro_top_padding),
 * the drop easing to 0 with (0, 0, 0.2, 1) as the page settles.
 *
 * pose(q, n, iconPx, gapPx, widthPx, heightPx) -> a list of
 *   { vcol, tile (1..n), dx (px from the middle), dy (px below the slot), alpha }
 * for the icons to draw (none when the face alone is on screen). A neighbour
 * comes in over its first half (alpha 2 x (1 - |s|), at most 1). */
function pose(q, n, iconPx, gapPx, widthPx, heightPx) {
    var out = []
    if (n <= 0)
        return out
    var p0 = Math.floor(q + 1e-6), frac = q - p0
    if (frac < 1e-6)
        frac = 0
    var pages = frac === 0 ? [p0] : [p0, p0 + 1]
    var tiles = pages.map(function (p) { return realCol(p, n) })
    var faceNear = tiles.indexOf(0) >= 0
    for (var i = 0; i < pages.length; i++) {
        if (tiles[i] === 0)
            continue
        var s = pages[i] - q
        var a = Math.abs(s)
        var pitch = faceNear ? 0.78125 * widthPx : iconPx + gapPx
        var drop = faceNear ? 0.2 * heightPx * (1 - outSlowIn(1 - a)) : 0
        out.push({ vcol: pages[i], tile: tiles[i], dx: s * pitch, dy: drop,
                   alpha: frac === 0 ? 1 : clamp(2 * (1 - a), 0, 1) })
    }
    return out
}
