/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/*
 * The numbers of the heads-up views (W2-launcher-heads-up), in px at the 384 px
 * screen (2 px per dp); the views scale them with width / 384. Stock CP3A
 * SysUI: ksx.java, klj.java, ktk.java, kte.java, ktr.java, juh.java,
 * hun_window_view.xml, VALUES.tsv default_glanceable_*, hun_*.
 */

// ---- the glanceable (audit heads-up-alerts-01) ----
var GLANCE = {
    // the primary icon: 30 dp, its top at 19.6 % of the screen height
    iconSize: 60,
    iconTopFraction: 0.196,
    // the glyph inside the icon's circle (the stream's 18 / 24 dp ratio)
    glyphFraction: 0.75,
    // side padding 9.2 % of the width
    sidePaddingFraction: 0.092,
    // the title: displayMedium with its size overridden, 24 sp on a 27 sp line, 3 lines
    titleSize: 48,
    titleLine: 54,
    titleLines: 3,
    // a conversation: 26 / 29 sp, 2 lines
    chatTitleSize: 52,
    chatTitleLine: 58,
    chatTitleLines: 2,
    // 6 dp between the icon and the title
    titleGap: 12,
    // the app name along the bottom edge: arcMedium 15 / 18 sp, 4 dp from the edge
    nameEdge: 8,
    // the picture of a conversation: 104 dp, pill radius 41 dp (one to one);
    // a group: a 116 x 96 dp box around a 72 dp picture
    picture: 208,
    pictureRadius: 82,
    groupBoxWidth: 232,
    groupBoxHeight: 192,
    groupPicture: 144,
    // an app badge: 12 dp, 20 dp from the start
    badgeSize: 24,
    badgeStart: 40
}

// How the glanceable comes in (ksx.java:74-200, 1230-1332): springs, damping 1
var ENTRY = {
    // icon, photo and title alpha and offset: MotionScheme slow spec
    stiffness: 260,
    // the photo's scale
    photoScaleStiffness: 130,
    iconScaleFrom: 0.75,
    photoScaleFrom: 0.88,
    // the offset: 10 % of the screen height
    offsetFraction: 0.10,
    // the title and the app name start 67 ms later
    titleDelayMs: 67
}

// ---- glanceable -> full view -> face (heads-up-alerts-02, -07) ----
var MORPH = {
    glanceFadeMs: 100,
    glanceScaleTo: 1.15,
    detailFadeMs: 100,
    detailScaleFrom: 0.85,
    detailScaleMs: 500,
    // Easing.InOutQuad stands in for the AccelerateDecelerate interpolator
    // a crown press: alpha and scale to 0 in 300 ms
    crownCloseMs: 300
}

// the glanceable stays this long, then becomes the full view: Show new notifications =
// On wrist raise / Immediately (juh.java:360-399)
var STAGE = { hold: 1000, holdImmediate: 1500 }

// ---- the bubble (heads-up-alerts-03, -04) ----
var BUBBLE = {
    // the strip: 48 dp tall, a gradient from transparent at 12 dp to black at 48 dp
    stripHeight: 96,
    gradientFrom: 24,
    // the icon: a 48 dp touch target with 12 dp padding = 24 dp icon (48 px)
    touchTarget: 96,
    icon: 48,
    iconScaleFrom: 0.5,
    iconAlphaFrom: 0.5,
    // springs, damping 1
    riseStiffness: 150,
    sinkStiffness: 100,
    sinkQueuedStiffness: 300,
    expandStiffness: 300,
    stayMs: 3000,
    // a drag released with the window top above 45 % of the screen height expands
    expandTopFraction: 0.45,
    // the touch counts within the centre +-48 dp and the bottom 48 dp
    hitHalfWidth: 96,
    hitHeight: 96,
    // a downward fling (px/s) that sinks it however high it is
    flingDown: 500,
    // closing the expanded view: 300 ms, cubic (0, 0, 0.2, 1)
    closeMs: 300,
    closeEasing: [0, 0, 0.2, 1, 1, 1]
}

// 0..1 of the screen height that the bubble's top has risen (rest: the strip)
function restProgress(height, u) {
    return height > 0 ? BUBBLE.stripHeight * u / height : 0.25
}

/* The black scrim over the app while the window grows from the strip to the
 * screen: (progress - 96/384) / (1 - 96/384) (ktk.java:253-258) */
function scrimOpacity(progress, height, u) {
    var rest = restProgress(height, u)
    return Math.max(0, Math.min(1, (progress - rest) / (1 - rest)))
}

/* The finger let go of the bubble: expand when its top is above 45 % of the
 * screen height and the finger is not flinging down (ktk.java:191-196,
 * 311-316). top: the window's top y in px, vy: the finger's vertical speed
 * (px/s, + down). */
function releaseExpands(top, vy, height) {
    return top < BUBBLE.expandTopFraction * height && !(vy > BUBBLE.flingDown)
}

// A touch point of the bubble counts: the centre +-48 dp and the bottom 48 dp
function inHitArea(x, y, width, height, u) {
    return Math.abs(x - width / 2) <= BUBBLE.hitHalfWidth * u && y >= height - BUBBLE.hitHeight * u
}

// ---- what a glanceable says ----

function hint(n, key) {
    var v = n && n.hints ? n.hints[key] : undefined
    return v === undefined || v === null ? "" : String(v)
}

// the phone's messages [{ s, t, me, p }], oldest first, [] for a plain notification
function messages(n) {
    var raw = hint(n, "x-asteroid-messages")
    if (raw === "")
        return []
    try {
        var list = JSON.parse(raw)
        if (!Array.isArray(list))
            return []
        return list.filter(function (m) { return m && typeof m.t === "string" })
    } catch (e) {
        return []
    }
}

function isChat(n) {
    return messages(n).length > 0
}

/* Title = the newest message for chats, else the text (the body; the title
 * of the notification when it has no body). */
function titleOf(n) {
    if (!n)
        return ""
    var m = messages(n)
    for (var i = m.length - 1; i >= 0; i--) {
        if (m[i].t !== "")
            return m[i].t
    }
    var body = n.body !== undefined && n.body !== null ? String(n.body) : ""
    if (body !== "")
        return body
    return n.summary !== undefined && n.summary !== null ? String(n.summary) : ""
}

// the newest message's picture ("" for none)
function pictureOf(n) {
    var m = messages(n)
    for (var i = m.length - 1; i >= 0; i--) {
        if (typeof m[i].p === "string" && m[i].p !== "")
            return m[i].p
        if (m[i].t !== "")
            break
    }
    return hint(n, "x-asteroid-picture")
}

// a group: a sender that is neither the user nor the title
function isGroup(n) {
    var m = messages(n)
    var title = n && n.summary ? String(n.summary) : ""
    for (var i = 0; i < m.length; i++) {
        if (m[i].me !== true && typeof m[i].s === "string" && m[i].s !== "" && m[i].s !== title)
            return true
    }
    return false
}
