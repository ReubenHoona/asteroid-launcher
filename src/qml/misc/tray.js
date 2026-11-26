/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the trays (W2-launcher-trays) as pure functions, so they are
 * unit tested (tst_trays.qml). PanelsGrid.qml owns the state and the
 * spring; this file decides. Quick settings comes from the top and the
 * notification stream from the bottom, over a watch face that does not move
 * (stock CP3A TrayPositionController, SysUI defpackage iho/ihu/ihr/ihv,
 * ihc FROM_TOP and FROM_BOTTOM).
 *
 * Distances are in px of the 450 x 450 screen (2 px per dp), speeds in px/s.
 * "Open distance" s is how far the tray is out: 0 closed, the panel height
 * open; the fraction is s / height.
 */

/* ui_mode_drag_finger_fudge_width 30 dp (stock VALUES.tsv, sysui) */
var FUDGE_PX = 60
/* config_gestureMinSwipeVelocity 500 dp/s (iho.u: |v| > it decides by direction) */
var FLING_PX_S = 1000
/* closed -> open above a third; open -> stays open from two thirds (iho.u:
 * e > 0.33f, e >= 0.66999996f) */
var OPEN_ABOVE = 0.33
var STAY_OPEN_FROM = 0.67
/* the spring starts at the release speed, at most this (ihu.b) */
var VELOCITY_CAP = 2000
/* the catch-up of a finger that went down beyond the tray's edge + FUDGE_PX:
 * 300 ms, DecelerateInterpolator(1.5) (iho.d, hoz.a) */
var CATCHUP_MS = 300
/* a closing tray jumps to its end at 98 % (ihu.b: f8 >= 0.98f) */
var CLOSE_SKIP = 0.98
/* an open asked for while the screen is not yet interactive waits (iho.p) */
var DELAY_OPEN_MS = 50
/* the crown opens a tray only 500 ms after the last crown close, and closes
 * one only 300 ms after the last crown open (TrayRotaryScrollHandler, jey) */
var CROWN_REOPEN_MS = 500
var CROWN_CLOSE_AFTER_OPEN_MS = 300

/* why a tray moves (iho.q's reason; the spring depends on it) */
var REASON = { none: 1, drag: 2, nonDrag: 3, gesture: 4 }

/* The tray's own black background (ihv.b): transparent below 25 % open, then
 * linear to opaque at 50 %: alpha = f x 1020 - 255 of 255, whole steps of
 * 1/255. The face behind does not move, scale or dim (ihf computes a 0.75
 * dim and discards it). */
function backgroundAlpha(f) {
    if (f < 0.25)
        return 0
    if (f > 0.5)
        return 1
    return Math.round(Math.max(0, Math.min(255, f * 1020 - 255))) / 255
}

/* DecelerateInterpolator(1.5): 1 - (1 - x)^3 */
function catchUpEase(x) {
    var c = Math.max(0, Math.min(1, x))
    var r = 1 - c
    return 1 - r * r * r
}

/* The finger went down at distance u from the tray's edge of origin (the
 * top edge for quick settings, the bottom edge for the stream) while the
 * tray is s out: when it is more than FUDGE_PX past the tray's edge, the
 * tray catches up the difference over CATCHUP_MS (iho.d: ((f - fudge) - b)
 * x direction, only when positive). */
function catchUpLead(s, u) {
    return Math.max(0, (u - FUDGE_PX) - s)
}

/* v: the finger's speed along the opening direction, positive = towards
 * open. A fling decides by its direction (ihc.c / ihc.e); otherwise a closed
 * tray opens past a third and an open one stays open from two thirds. */
function releaseOpens(startedOpen, fraction, v) {
    if (Math.abs(v) > FLING_PX_S)
        return v > 0
    return startedOpen ? fraction >= STAY_OPEN_FROM : fraction > OPEN_ABOVE
}

function clampVelocity(v) {
    return Math.max(-VELOCITY_CAP, Math.min(VELOCITY_CAP, v))
}

/* The spring of a move to open or closed (ihu.b, the jadx fallback decode in
 * audit/motion-transitions/work/ihu.fallback.java):
 *   opening: damping 0.75, stiffness 500 (the Wear OS 6 emulator's open: M06
 *     zeta 0.80 k 488, M07 zeta 0.77 k 527)
 *   closing: damping 1.0,  stiffness 500, ends at 98 % (CP3A); only a close
 *     another gesture asked for still takes it, every other close is a cut
 *     (closeCuts below)
 *   a move another gesture asked for (REASON.gesture, the heads-up card's
 *   tap): stiffness 200, damping 0.8 opening, 1.0 closing */
function spring(opening, reason) {
    var gesture = reason === REASON.gesture
    return {
        stiffness: gesture ? 200 : 500,
        dampingRatio: opening ? (gesture ? 0.8 : 0.75) : 1.0,
        stopAt: opening ? 1.0 : CLOSE_SKIP
    }
}

/* A committed close (the finger let go of a tray that goes back, the crown,
 * a close without a finger) cuts the tray away in one frame, with no retract
 * slide: the Wear OS 6 emulator (M06 and M07 close) lets the tray follow the
 * finger for about 70-100 ms over black (no face behind it) and then shows
 * the face at once, dimmed, which comes up to full in about 100 ms after the
 * stream (98 ms at 10x, 85-100 ms at 1x) or 115 ms after quick settings
 * (108 ms at 10x, about 115 ms at 1x), on standardAccel (0.3, 0, 1, 1). A
 * close another gesture asked for (REASON.gesture) keeps its spring. */
var CLOSE_FADE_STREAM_MS = 100
var CLOSE_FADE_QS_MS = 115
var CLOSE_FADE_EASING = [0.3, 0, 1, 1]
/* The face's brightness at the cut (N61-24 follow-up): 0.35 after the stream,
 * 0.18 after quick settings (the emulator's M06 and M07 close at 10x: the first
 * frames after the cut, flat for about 8 frames before standardAccel lifts
 * them; at 1x the first frame came a little later on the curve). The face
 * that showed through the tray's background at the release (CP3A's drag dim,
 * backgroundAlpha: a tray let go under 50 % out) is not darkened: the fade
 * starts at whichever is brighter. The open drag keeps CP3A's dim: the
 * emulator's face fades with the finger from about 16-25 % to black at about
 * 45-54 % of the screen (R06slow, R07slow), ours from 25 % to 50 %. */
var CLOSE_CUT_BRIGHTNESS_STREAM = 0.35
var CLOSE_CUT_BRIGHTNESS_QS = 0.18
// the background's alpha the fade starts from after the tray of `row`, `alpha` at the release
function cutDim(row, alpha) {
    var stock = 1 - (row > 0 ? CLOSE_CUT_BRIGHTNESS_STREAM : CLOSE_CUT_BRIGHTNESS_QS)
    return Math.max(0, Math.min(alpha, stock))
}

function closeCuts(reason) {
    return reason !== REASON.gesture
}

/* the fade's length after the tray of a row: 1 the stream, -1 quick settings */
function closeFadeMs(row) {
    return row > 0 ? CLOSE_FADE_STREAM_MS : CLOSE_FADE_QS_MS
}

/* The opening direction of a tray as the sign of its coordinate on the
 * grid's content (content.y = sign x s): quick settings (row -1) comes down,
 * the stream (row 1) comes up */
function sign(row) {
    return row < 0 ? 1 : -1
}

/* The crown on the watch face (jey.onGenericMotionEvent): forward (scroll
 * down) opens the stream, backward opens quick settings. Returns the row to
 * open or 0 for none. lastCloseMs: time of the last crown close. */
function crownOpens(direction, now, lastCloseMs) {
    if (direction === 0 || now - lastCloseMs <= CROWN_REOPEN_MS)
        return 0
    return direction > 0 ? 1 : -1
}

/* The crown with a tray open: past the end of the tray, towards its edge of
 * origin, closes it: the stream (row 1) when the crown goes backward (scroll
 * up), quick settings (row -1) forward; not within 300 ms of the crown open. */
function crownCloses(row, direction, now, lastOpenMs) {
    if (row === 0 || now - lastOpenMs <= CROWN_CLOSE_AFTER_OPEN_MS)
        return false
    return row > 0 ? direction < 0 : direction > 0
}
