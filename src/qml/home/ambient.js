/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The always-on screen's rules (W2-launcher-ambient) as pure functions, so
 * they are unit tested (tst_ambient.qml). The QML files own the state, this
 * file decides. Stock (CP3A) evidence per block; audit area ambient-aod.
 *
 * 1. Who draws the always-on screen when an application is open
 *    (ambient-aod-01, media-controls-15):
 *    - an application that handles ambient itself stays on screen;
 *    - the media player with a playing or paused session gets its own
 *      ambient layout (buttons as outlines, the time at the top);
 *    - every other application gets Ambient Lite: black, the application's
 *      last frame blurred (radius 15 px) and scaled 0.95, the time in the
 *      middle. The application is not closed.
 *    CSUI ambient/AmbientTaskStateMachine.getExpectedStateLocked,
 *    AmbientLiteOverlay.buildTransitionAnimator / updateWatchFaceStateLocked,
 *    AmbientLiteBackgroundSurface (setBackgroundBlurRadius 15), dimens.xml
 *    ambient_lite_wf_text_size 40sp, MS/gqe.java:84-88, MS/fxa.java:216.
 *
 * 2. The burn-in mask (ambient-aod-07): no pixel shift; a 2x2 tile
 *    {{1,0},{0,1}} in black, phase = minute mod 4 (WS display/burninprotection
 *    ImageMaskTileFactory.getShiftedX/Y, ImageMaskViewController
 *    .enableImageMask: i = minute % 4), from the first whole minute after the
 *    AP-drawn always-on screen began, brightness x2, never while the hub draws.
 *
 * 3. Settings > Display > 'Always-on when off wrist' (choice-settings-07):
 *    CSUI ambient/AmbientEarlyExitTimeoutController.updateAlarm: plugged or
 *    off-body in ambient -> an exact alarm in N min (N = 1:
 *    ro.ambient.plugged_timeout_min); on-body or unplugged restores.
 */

/* ---- 1. Ambient Lite ----------------------------------------------------- */

var LITE = {
    ENTER_MS: 200,                       // buildTransitionAnimator
    EASING: [0.4, 0, 0.2, 1, 1, 1],      // PathInterpolator(0.4, 0, 0.2, 1)
    SNAPSHOT_FROM: 1.0,                  // snapshot scale 1.0 -> 0.95
    SNAPSHOT_TO: 0.95,
    CLOCK_FROM: 1.1,                     // clock scale 1.1 -> 0.95, alpha 0 -> 1
    CLOCK_TO: 0.95,
    BLUR_PX: 15,                         // setBackgroundBlurRadius(15)
    CLOCK_PX: 80,                        // 40 sp at 2 px per dp
    LETTER_EM: 0.02,                     // AmbientLiteOverlayWF_TextAppearance
    HANDOVER_MS: 300                     // the overlay is offloaded after 300 ms
}

// the end state is scale 1.0 (the hub cannot scale a glyph), so the clock's
// font is drawn at its final 0.95 and the animation runs 1.1/0.95 -> 1
function clockRest() { return LITE.CLOCK_TO }
function clockScaleAt(p) {
    var from = LITE.CLOCK_FROM / LITE.CLOCK_TO
    return from + (1 - from) * p
}
function snapshotScaleAt(p) {
    return LITE.SNAPSHOT_FROM + (LITE.SNAPSHOT_TO - LITE.SNAPSHOT_FROM) * p
}
function clockPixelSize() { return Math.round(LITE.CLOCK_PX * LITE.CLOCK_TO) }
// letter spacing in px at that size
function clockLetterSpacing() { return LITE.CLOCK_PX * LITE.CLOCK_TO * LITE.LETTER_EM }

function pad2(n) { return (n < 10 ? "0" : "") + n }

// 'h:mm' (12 h, no AM/PM, no leading zero) or 'HH:mm'; ASCII digits
function clockParts(d, use12h) {
    var h24 = d.getHours()
    var h12 = (h24 + 11) % 12 + 1
    return { hour: use12h ? String(h12) : pad2(h24), minute: pad2(d.getMinutes()) }
}

// The locale's zero digit from "00" formatted by the locale (Qt's Locale
// object has no zeroDigit); "0" when it is plain ASCII or not a single
// contiguous BMP digit set
function zeroOf(zeroZero) {
    var s = String(zeroZero || "")
    if (s.length !== 2 || s.charAt(0) !== s.charAt(1))
        return "0"
    var c = s.charCodeAt(0)
    return c >= 0x30 && c <= 0x39 ? "0" : s.charAt(0)
}

function localizeDigits(s, zero) {
    var z = String(zero || "0").charCodeAt(0)
    if (z === 0x30)
        return String(s)
    var out = ""
    for (var i = 0; i < s.length; i++) {
        var c = s.charCodeAt(i)
        out += c >= 0x30 && c <= 0x39 ? String.fromCharCode(z + c - 0x30) : s.charAt(i)
    }
    return out
}

/* What draws the always-on screen. o: appOpen (an application window in
 * front), handlesAmbient (the window says it draws its own always-on
 * look), media {present, state: "Playing"|"Paused"|"Stopped"} and
 * mediaApp (the window in front is the media player), alwaysOn (the
 * user's Always-on screen, not blocked by a mode). "face" = the watch
 * face (home screen), "lite", "media", "app". */
function mode(o) {
    if (!o.alwaysOn)
        return "none"
    if (!o.appOpen)
        return "face"
    if (o.handlesAmbient === true)
        return "app"
    if (o.mediaApp && mediaActive(o.media))
        return "media"
    return "lite"
}

// a session that plays or is paused (stock: it posts an ongoing activity then)
function mediaActive(m) {
    return !!m && m.present === true && (m.state === "Playing" || m.state === "Paused")
}

// The media layout is rebuilt only for another track or play state
function mediaKey(m) {
    return m ? [m.title || "", m.artist || "", m.state || ""].join("|") : ""
}

/* ---- 2. The burn-in mask -------------------------------------------------- */

var MASK = {
    TILE: [[1, 0], [0, 1]],
    PHASES: 4,
    BRIGHTNESS_FACTOR: 2
}

function maskPhase(minuteOfHour) { return ((minuteOfHour % MASK.PHASES) + MASK.PHASES) % MASK.PHASES }

// ImageMaskTileFactory.getShiftedX(i, x) = ((i % 2) + x) % 2,
// getShiftedY(i, y) = ((i / 2) + y) % 2: the black pixels of a phase
function maskBlack(x, y, phase) {
    var sx = phase % 2, sy = Math.floor(phase / 2)
    for (var ty = 0; ty < 2; ty++)
        for (var tx = 0; tx < 2; tx++)
            if (MASK.TILE[ty][tx] === 1 && ((sx + tx) % 2) === (x % 2) && ((sy + ty) % 2) === (y % 2))
                return true
    return false
}

// which of the two tile pictures a phase is (0: black where x + y is even)
function maskParity(phase) {
    return maskBlack(0, 0, phase) ? 0 : 1
}

// from the first whole minute after the AP-drawn always-on screen began
function maskStarts(entryMinute, nowMinute) { return nowMinute > entryMinute }

/* ---- 3. Always-on when off wrist ------------------------------------------ */

var OFFWRIST = { DELAY_S: 60 }

// away: off the wrist (the hub's off-body sensor), or on the charger. The
// nightstand, on and active, keeps the screen on the charger (ours only).
function offWristAway(s) {
    return s.offBody === true || (s.plugged === true && s.nightstand !== true)
}

/* The decision at each event (off-body change, charger change, display
 * change, the wake after the alarm). s: rule (the setting is false = stock),
 * displayOff (ambient or black: the display is not on), offBody (true, false
 * or undefined = unknown), plugged, nightstand, ended (the screen has gone
 * black), deadline (ms since the epoch of the running alarm, 0 = none), now.
 * Returns {arm, cancel, expire, restore}; at most one of arm / expire. */
function offWristDecide(s) {
    var r = { arm: false, cancel: false, expire: false, restore: false }
    if (!s.rule || !s.displayOff || !offWristAway(s)) {
        r.cancel = s.deadline > 0
        r.restore = s.ended === true
        return r
    }
    if (s.ended)
        return r
    if (!(s.deadline > 0))
        r.arm = true
    else if (s.now >= s.deadline)
        r.expire = true
    return r
}

function offWristDeadline(now) { return now + OFFWRIST.DELAY_S * 1000 }

/* ---- complications in the always-on screen (ambient-aod-11) ---------------- */

/* When the sensor hub draws the always-on screen, values that change between
 * the AP's wakeups would mislead, so they show '--' (the developer guidance
 * for ambient). kinds: "static" (right for the whole day: the date, moon,
 * an app shortcut, the alarm's time, the hourly weather values), "stale"
 * (live data or the time: steps, heart rate, battery, the phone's battery,
 * unread count, the next event's countdown, clocks, timers, the media title). Hub-bound metrics (steps, heart rate)
 * are not available to the layout yet (the hub's metric ids are not known),
 * so they are "stale" too. */
var STALE_KINDS = ["timedate", "worldclock", "steps", "heartrate", "battery", "phonebattery", "notifications",
                   "nextevent", "sun", "timer", "stopwatch", "media"]

function complicationStale(kind, hubDrawn) {
    return hubDrawn === true && STALE_KINDS.indexOf(kind) >= 0
}
