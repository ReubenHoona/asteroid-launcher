/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The edge transformation of the Wear app list and grid (W2-launcher-app-list,
 * app-launcher-07 and -16) as pure functions, so every number is a test
 * assertion (tests tst_applist.qml).
 *
 * Stock CP3A lays the list and the grid out in a TransformingLazyColumn with
 * a launcher-only TransformationSpec for 192 dp screens (SysUI isf.java:15,
 * ivl.java:15; library 192 dp defaults fbb.java:21-30). The values of an
 * item come from where it is in the viewport (hca.java:2621-2658 hca.l,
 * hqf.java:6-14 hqf.a):
 *
 *   h     = the item's height / the viewport's height, top = its top / the same
 *   area  = lerp(minTransitionArea, maxTransitionArea,
 *                clamp((h - minElementHeight) / (maxElementHeight - minElementHeight)))
 *           at most (h + 1) / 2
 *   near the top (bottom < 1 - top):  l = min(bottom / area - 1, 0)   (-1 at the edge)
 *   else:                             l = max(1 - (1 - top) / area, 0)  (+1 at the edge)
 *   x     = l < 0 ? l + 1 : 1 - l        (0 at the screen edge, 1 inside)
 *   value = (1 - e) edge + e target,  e = easing(clamp((x - enter) / (exit - enter)))
 *   edge  = l < 0 ? topValue : bottomValue
 *
 * The scale is about the item's top centre and the item is laid out at
 * ceil(scale x height) (transformedHeight), so shrunk rows stay packed.
 * Variable specs are TransformationVariableSpec(topValue, targetValue = 1,
 * bottomValue, enterFraction, exitFraction). */

/* Stock's long press timeout (def_long_press_timeout_millis 400, as the
 * tiles: pager.js) */
var LONG_PRESS_MS = 400

function variable(top, bottom, enter, exit) {
    return { top: top, target: 1, bottom: bottom, enter: enter, exit: exit }
}

/* The app list: area 0.5 (min and max), element height 0.2-0.6, easing
 * CubicBezier(0, 0, 0.6, 1); containerAlpha 0.3 at the top and 0 at the
 * bottom, zone 0-0.75; contentAlpha 0.5 / 0, zone 0.25-0.45; scale 0.5 / 0,
 * zone 0-1. (isf.java:15: new fbf(0.3f, 0, 0, 0.75f) = top, bottom, enter,
 * exit.) */
var LIST = {
    minElementHeight: 0.2, maxElementHeight: 0.6, minArea: 0.5, maxArea: 0.5,
    easing: [0, 0, 0.6, 1],
    containerAlpha: variable(0.3, 0, 0, 0.75),
    contentAlpha: variable(0.5, 0, 0.25, 0.45),
    scale: variable(0.5, 0, 0, 1),
    sideOffset: null
}

/* The grid: the same area and easing; both alphas 0 at both edges (zone
 * 0.1-0.6), scale 0.2 at both edges (zone 0.12-1.0); the side columns of a
 * full row move by height x (0.08 at the top, -0.08 at the bottom, zone
 * 0.1-0.75) (ivl.java:15-21, iuz.java:87). */
var GRID = {
    minElementHeight: 0.2, maxElementHeight: 0.6, minArea: 0.5, maxArea: 0.5,
    easing: [0, 0, 0.6, 1],
    containerAlpha: variable(0, 0, 0.1, 0.6),
    contentAlpha: variable(0, 0, 0.1, 0.6),
    scale: variable(0.2, 0.2, 0.12, 1),
    sideOffset: { top: 0.08, target: 0, bottom: -0.08, enter: 0.1, exit: 0.75 }
}

/* Nothing transformed (Reduce animations, or no size yet) */
var REST = { l: 0, x: 1, scale: 1, containerAlpha: 1, contentAlpha: 1, sideOffset: 0 }

function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }

/* y of a cubic Bezier through (0, 0), (x1, y1), (x2, y2), (1, 1) at x (the
 * AOSP PathInterpolator / Compose CubicBezierEasing) */
function bezier(e, x) {
    if (x <= 0) return 0
    if (x >= 1) return 1
    var lo = 0, hi = 1, s = x
    for (var i = 0; i < 32; i++) {
        var u = 1 - s
        var bx = 3 * u * u * s * e[0] + 3 * u * s * s * e[2] + s * s * s
        if (Math.abs(bx - x) < 1e-7)
            break
        if (bx < x) lo = s; else hi = s
        s = (lo + hi) / 2
    }
    var v = 1 - s
    return 3 * v * v * s * e[1] + 3 * v * s * s * e[3] + s * s * s
}

/* The transition progress l of an item (hca.l): top and h in viewport
 * fractions */
function progress(spec, top, h) {
    var bottom = top + h
    var hf = clamp01((h - spec.minElementHeight) / (spec.maxElementHeight - spec.minElementHeight))
    var area = spec.minArea * (1 - hf) + spec.maxArea * hf
    area = Math.min(area, (h + 1) / 2)
    if (bottom < 1 - top) {
        var near = bottom / area - 1
        return near > 0 ? 0 : near
    }
    var far = 1 - (1 - top) / area
    return far < 0 ? 0 : far
}

/* One variable at progress l (hqf.a) */
function value(l, v, easing) {
    var edge = l < 0 ? v.top : v.bottom
    var x = l < 0 ? l + 1 : 1 - l
    var f = clamp01((x - v.enter) / (v.exit - v.enter))
    var e = bezier(easing, f)
    return (1 - e) * edge + e * v.target
}

/* Everything for an item: scale, the alpha of the container and of the
 * content, the side column offset (a fraction of the item's height) */
function evaluate(spec, top, h, reduced) {
    if (reduced || !(h > 0))
        return REST
    var l = progress(spec, top, h)
    return {
        l: l,
        x: l < 0 ? l + 1 : 1 - l,
        scale: value(l, spec.scale, spec.easing),
        containerAlpha: value(l, spec.containerAlpha, spec.easing),
        contentAlpha: value(l, spec.contentAlpha, spec.easing),
        sideOffset: spec.sideOffset ? value(l, spec.sideOffset, spec.easing) : 0
    }
}

/* The height an item is laid out at (ResponsiveTransformationSpecImpl: ceil) */
function transformedHeight(h, scale) {
    return Math.ceil(h * scale)
}

/* The column shift of a grid row of n cells of width w at scale s: the cells
 * come together as they shrink (iuz.java:70-95): the first moves right by
 * w (1 - s), the last left by the same (half of it in a row of two) */
function columnShift(index, n, w, s) {
    if (n === 3 || n === 2) {
        var k = n === 2 ? 0.5 : 1
        if (index === 0)
            return w * (1 - s) * k
        if (index === n - 1)
            return -w * (1 - s) * k
    }
    return 0
}

/* The side columns of a full row also move up or down (iuz.java:87) */
function columnLift(index, n, h, sideOffset) {
    return n === 3 && (index === 0 || index === n - 1) ? h * sideOffset : 0
}

/* ---- the packed layout of a list ----
 *
 * Stock lays the items out at their transformed height, so shrunk items stay
 * packed. The rows here keep their natural place in the Flickable (a list
 * that scrolls evenly, at its natural length, with the rows made only near
 * the screen); what moves is their picture. This computes where every item
 * is drawn: the item nearest the middle of the screen stays where it is, the
 * ones below follow it downwards from its bottom and the ones above upwards
 * from its top, each at ceil(scale x height) and the gap, with the scale of
 * the place it comes to. Every step uses what the step before it gave, so
 * there is no loop, and it is the same layout from the same scroll position.
 *
 *   tops[i]   the natural top of item i, in viewport px
 *   hs[i]     its height
 *   gaps[i]   the gap between item i and item i + 1
 *   vh        the viewport's height
 * Returns for every item { y, height, scale, containerAlpha, contentAlpha,
 * sideOffset, shown }: y the top of its picture and height its transformed
 * height (the picture is scaled about its top). Items beyond the screen
 * have shown false, the edge value of the place they would be at, and a
 * place off the screen. */

function placed(y, h, e) {
    return { y: y, height: transformedHeight(h, e.scale), scale: e.scale, containerAlpha: e.containerAlpha,
             contentAlpha: e.contentAlpha, sideOffset: e.sideOffset, shown: true }
}

function layout(spec, tops, hs, gaps, vh, reduced) {
    var n = tops.length
    var out = new Array(n)
    if (n === 0 || !(vh > 0))
        return out
    function eval1(top, h) { return evaluate(spec, top / vh, h / vh, reduced) }
    function gone(top, h, e) {
        return { y: top, height: 0, scale: e.scale, containerAlpha: 0, contentAlpha: 0, sideOffset: e.sideOffset, shown: false }
    }
    var a = 0, best = 1e30
    for (var i = 0; i < n; i++) {
        var d = Math.abs(tops[i] + hs[i] / 2 - vh / 2)
        if (d < best) { best = d; a = i }
    }
    out[a] = placed(tops[a], hs[a], eval1(tops[a], hs[a]))
    // downwards from the anchor's bottom
    var bottom = out[a].y + out[a].height
    for (var k = a + 1; k < n; k++) {
        var top = bottom + gaps[k - 1]
        var e = eval1(top, hs[k])
        if (top >= vh) {
            for (var r = k; r < n; r++)
                out[r] = gone(vh + hs[r], hs[r], e)
            break
        }
        out[k] = placed(top, hs[k], e)
        bottom = top + out[k].height
    }
    // upwards from the anchor's top: the item that ends at `end` is judged as it would
    // be untransformed, which is what its edge progress (its bottom edge) needs
    var start = out[a].y
    for (var j = a - 1; j >= 0; j--) {
        var end = start - gaps[j]
        var e2 = eval1(end - hs[j], hs[j])
        var h2 = transformedHeight(hs[j], e2.scale)
        if (end <= 0) {
            for (var q = j; q >= 0; q--)
                out[q] = gone(-hs[q], hs[q], e2)
            break
        }
        out[j] = placed(end - h2, hs[j], e2)
        start = out[j].y
    }
    return out
}

/* An item that is not in the layout (before it is made): at rest, where it is */
var UNPLACED = { y: 0, height: 0, scale: 1, containerAlpha: 1, contentAlpha: 1, sideOffset: 0, shown: true, unplaced: true }
