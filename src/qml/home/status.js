/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The face status icon (W2-launcher-status; audit status-indicators-01, -03,
 * -04, -22): which of the 16 status types shows, its icon and words. Pure
 * rules: StatusSources.qml feeds them the state, FaceStatusIcon.qml draws the
 * result in the face's bottom row. Stock CP3A SysUI, "system tray":
 * jpb.java:62-115 (icon and words of each type), ilb.java:38 (priority map,
 * ascending, index 0 wins), naf.java:24-45 (the first active type; "Device is
 * locked" first).
 *
 * The bottom row (N61-17, the look of the Wear OS 6 emulator, BP2A): the
 * face's overlays are one row at 6 o'clock, the same awake and always-on:
 * the ongoing activity's icon, the unread dot, the status icon, left to
 * right, only the visible ones counted and centred as a group on an arc, over
 * one black band at 70 % (FaceOverlayRow.qml). Measured on the emulator's
 * screens S01, S02, X-face-ongoing-stopwatch(-6s), X-face-ongoing-plus-unread,
 * X-ambient-ongoing-plus-unread, X-face-charging(-dnd), X-face-airplane. */

// ilb.java:38: index 0 wins
var ORDER = ["thermal", "wet", "mic", "location", "safety", "screenLock", "charging", "airplane",
             "btOff", "lteDisconnected", "phoneDisconnected", "bedtime", "theater", "dnd",
             "batterySaver", "batteryLow"]

// ---- the bottom row (N61-17) -------------------------------------------------------------------
// One slot is 18 dp (36 px): the status glyph's box, the ongoing icon's box, the dot's place. The
// slots' centres lie on a circle about the screen's centre, 11.5 dp inside the edge (radius 169 px
// on the 384 px screen: a single slot is centred at pixel 191.5, 360.5), 36 px of arc apart.
var ROW_SLOT_DP = 18
var ROW_EDGE_DP = 11.5
// the unread dot: a 6 dp (12 px) white disc (S01, S02: x 186-197, y 355-366)
var ROW_DOT_DP = 6
// the band: an arc stroke 21 dp (42 px) thick on the slots' circle (y 340-382 at 6 o'clock) with
// round caps; between the cap centres it runs n slots less half its thickness (n * 36 - 21 px), so
// it is 57 x 42 px for one slot, 93 for two, 129 for three. Black at 178/255 (the face under it
// reads 0.30 of its value: a numeral's 255 reads 69-77)
var ROW_BAND_DP = 21
var ROW_BAND_OPACITY = 0.7
// a slot shows and goes with opacity and scale 0 <-> 1, its neighbours slide to their new places
// and the band follows, in 300 ms FastOutSlowIn (the legacy overlay's; no capture contradicts it);
// nothing moves in the always-on screen
var ROW_MS = 300
var ROW_CURVE = [0.4, 0, 0.2, 1, 1, 1]
// the ongoing icon's tap target: at least 60 dp (120 px) tall (overlay_icon_min_tap_target_height),
// as wide as the slot's pitch (rowPitch: it ends half way to the next slot's centre), centred on its slot
var ROW_TAP_MIN_DP = 60

// The slots shown, left to right: the ongoing activity, the unread dot, the status icon
function rowSlots(ongoing, dot, status) {
    var out = []
    if (ongoing)
        out.push("ongoing")
    if (dot)
        out.push("dot")
    if (status)
        out.push("status")
    return out
}

/* Slot i of n: its angle in radians from 6 o'clock along the slots' circle (negative to the left,
 * towards 9 o'clock), the group centred: slotPx of arc apart on a circle of radiusPx. */
function rowAngle(i, n, slotPx, radiusPx) {
    return radiusPx > 0 ? (i - (n - 1) / 2) * slotPx / radiusPx : 0
}

// The least horizontal distance between the centres of two neighbouring slots (the outer pair of three:
// 35.7 px for 36 px on 169; a pair of two is 35.9 apart): how wide an upright tap area centred on a slot may
// be without reaching past half way to its neighbour
function rowPitch(slotPx, radiusPx) {
    return radiusPx > 0 ? radiusPx * Math.sin(slotPx / radiusPx) : slotPx
}

// The centre of a slot at that angle on the circle of radiusPx about (cx, cy); the slot stays upright
function rowPoint(angle, cx, cy, radiusPx) {
    return { x: cx + radiusPx * Math.sin(angle), y: cy + radiusPx * Math.cos(angle) }
}

// The band's sweep in degrees for n slots: n slots of arc less half the band's thickness between the
// centres of its round caps (0 for no slot)
function bandSweepDeg(n, slotPx, bandPx, radiusPx) {
    if (n <= 0 || radiusPx <= 0)
        return 0
    return Math.max(0, n * slotPx - bandPx / 2) / radiusPx * 180 / Math.PI
}

// The band's length end to end along its middle, caps included (57, 93, 129 px for 1, 2, 3 slots)
function bandLength(n, slotPx, bandPx) {
    return n > 0 ? n * slotPx + bandPx / 2 : 0
}

// the battery low level when no auto Battery Saver level is set (ojn.java flag 45385279 default 10)
var LOW_BATTERY_DEFAULT = 10

var ICON_DIR = "file:///usr/share/icons/asteroid/"

// the words (w2_status_* of the stock strings) and the icon of each type; the eos-status-* SVGs are
// the bare white glyphs of WO-61-M1 (no disc of their own: the row's band is the only backdrop).
// Touch lock and Water lock share the "wet" type; touch lock has its own glyph (eos-status-touchlock).
var INFO = {
    thermal:           { icon: "eos-status-thermal",            words: "Watch is warm" },
    wet:               { icon: "eos-status-waterlock",          words: "Water lock on" },
    mic:               { icon: "eos-status-microphone",         words: "Microphone on" },
    location:          { icon: "eos-status-location",           words: "Location on" },
    safety:            { icon: "",                              words: "Safety signal is active" },
    screenLock:        { icon: "eos-status-screenlock",         words: "Device is locked" },
    charging:          { icon: "eos-status-charging",           words: "Charging" },
    airplane:          { icon: "eos-status-airplane",           words: "Airplane mode on" },
    btOff:             { icon: "eos-status-bluetooth-off",      words: "Bluetooth off" },
    lteDisconnected:   { icon: "",                              words: "LTE Disconnected" },
    phoneDisconnected: { icon: "eos-status-phone-disconnected", words: "Disconnected from phone" },
    bedtime:           { icon: "eos-status-bedtime",            words: "Bedtime mode on" },
    theater:           { icon: "eos-status-theater",            words: "Theater mode on" },
    dnd:               { icon: "eos-status-dnd",                words: "Do Not Disturb Mode on" },
    batterySaver:      { icon: "eos-status-battery-saver",      words: "Power Save mode on" },
    batteryLow:        { icon: "eos-status-battery-low",        words: "Battery Low" }
}

/* Battery low: the level is at or under low_power_trigger_level when that is
 * above 0, else at or under 10 % (ivm.java default case, hpe.java:41-43). An
 * unknown level (-1) is not low. */
function batteryLow(level, trigger) {
    if (level === undefined || level === null || level < 0)
        return false
    var limit = trigger > 0 ? trigger : LOW_BATTERY_DEFAULT
    return level <= limit
}

/* Phone disconnected: the phone link is down (a state known), the watch is not on Wi-Fi, Bluetooth is on
 * and the watch is not standalone (jqb.java:27-36; jfs.java:22-41). We have no cellular service, so
 * "cellular not in service" always holds and "standalone" never does. */
function phoneDisconnected(s) {
    return s.phoneKnown === true && s.phoneConnected !== true && s.btPowered === true && s.wifiConnected !== true
}

/* The 16 booleans from the state of the watch (gap 03). s: thermal, touchLock, waterLock, mic,
 * location, safety, screenLock, charging, airplane, btPowered, wifiConnected, lteDisconnected,
 * phoneKnown, phoneConnected, bedtime, theater, dnd, batterySaver, batteryLevel, lowTrigger. */
function evaluate(s) {
    return {
        thermal: s.thermal === true,
        wet: s.touchLock === true || s.waterLock === true,
        mic: s.mic === true,
        location: s.location === true,
        safety: s.safety === true,
        screenLock: s.screenLock === true,
        charging: s.charging === true,
        airplane: s.airplane === true,
        btOff: s.btPowered === false,
        lteDisconnected: s.lteDisconnected === true,
        phoneDisconnected: phoneDisconnected(s),
        bedtime: s.bedtime === true,
        theater: s.theater === true,
        // DND counts only while Bedtime is off (jpy.java:29-31, jpv.java:20-25)
        dnd: s.dnd === true && s.bedtime !== true,
        batterySaver: s.batterySaver === true,
        batteryLow: batteryLow(s.batteryLevel, s.lowTrigger)
    }
}

/* The type the face shows: "Device is locked" if active, else the first active type in ORDER
 * (naf.java:24-45); "" when none. */
function current(active) {
    if (active.screenLock)
        return "screenLock"
    for (var i = 0; i < ORDER.length; i++)
        if (active[ORDER[i]])
            return ORDER[i]
    return ""
}

// What fills the slot: the type, the wet kinds apart
function slotKey(type, wetKind) {
    if (type === "wet")
        return wetKind === "water" ? "wet-water" : "wet-touch"
    return type
}

// the glyph of the touch lock (WO-61-M1): it is a status icon of the row like the others
var TOUCH_LOCK_ICON = "eos-status-touchlock"

function iconSource(key) {
    if (key === "")
        return ""
    if (key === "wet-touch")
        return ICON_DIR + TOUCH_LOCK_ICON + ".svg"
    var info = INFO[key === "wet-water" ? "wet" : key]
    return info && info.icon !== "" ? ICON_DIR + info.icon + ".svg" : ""
}

// The content description of the icon (the stock English words, w2_status_*)
function words(key) {
    if (key === "wet-touch")
        return "Touch lock on"
    var info = INFO[key === "wet-water" ? "wet" : key]
    return info ? info.words : ""
}

/* How the slot changes from `prev` to `next`: none, show (the row brings the slot in), hide (the row
 * takes it out), replace (the slot stays; the old glyph gives way to the new one in ROW_MS). */
function transition(prev, next) {
    if (prev === next)
        return "none"
    if (prev === "")
        return "show"
    if (next === "")
        return "hide"
    return "replace"
}

/* What the always-on screen's layout needs to know: the sensor hub draws the face with the row
 * as the AP drew it at the last update (its background picture), so a change of this is a change
 * of that layout (ambient-aod-18). The row is static and at full opacity there. */
function ambientKey(statusKey, chipKey) {
    return (statusKey !== "" ? "s:" + statusKey : "") + (chipKey !== "" ? "|c:" + chipKey : "")
}
