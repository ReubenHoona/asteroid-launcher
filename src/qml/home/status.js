/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

.pragma library

/* The face status icon (W2-launcher-status; audit status-indicators-01, -03,
 * -04, -22): which of the 16 status types shows, its icon and words, and how
 * a change animates. Pure rules: StatusSources.qml feeds them the state,
 * FaceStatusIcon.qml draws the result. Stock CP3A SysUI, "system tray":
 * jpb.java:62-115 (icon and words of each type), ilb.java:38 (priority map,
 * ascending, index 0 wins), naf.java:24-45 (the first active type; "Device is
 * locked" first), nae.java:24,76-140 and assets/system_tray.css (the fades). */

// ilb.java:38: index 0 wins
var ORDER = ["thermal", "wet", "mic", "location", "safety", "screenLock", "charging", "airplane",
             "btOff", "lteDisconnected", "phoneDisconnected", "bedtime", "theater", "dnd",
             "batterySaver", "batteryLow"]

// assets/system_tray.css: .fade-in 0.35 s, .fade-out 0.15 s; nae.java:24 the replacement's fade-in
// starts 350 ms after the change (begin "custom+0.35")
var FADE_IN_MS = 350
var FADE_OUT_MS = 150
var REPLACE_DELAY_MS = 350
// cubic-bezier(0.0, 0.0, 0.0, 1.0) and cubic-bezier(0.3, 0.0, 1.0, 1.0) as Easing.BezierSpline
var FADE_IN_CURVE = [0, 0, 0, 1, 1, 1]
var FADE_OUT_CURVE = [0.3, 0, 1, 1, 1, 1]
// .status-icon: y 1dp, 18 x 18 dp
var TOP_DP = 1
var SIZE_DP = 18

// the battery low level when no auto Battery Saver level is set (ojn.java flag 45385279 default 10)
var LOW_BATTERY_DEFAULT = 10

var ICON_DIR = "file:///usr/share/icons/asteroid/"

// the words (w2_status_* of the stock strings) and the icon of each type; the eos-status-* SVGs are
// W2-meta-icons-fonts' (an 18 dp black disc at 85 % and the glyph). Touch lock draws its own disc
// (system/TouchLock.qml): the tray holds the slot for it and draws nothing.
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

// What fills the slot: the type, the wet kinds apart ("wet-touch" has no icon here)
function slotKey(type, wetKind) {
    if (type === "wet")
        return wetKind === "water" ? "wet-water" : "wet-touch"
    return type
}

function iconSource(key) {
    if (key === "" || key === "wet-touch")
        return ""
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

/* How the slot changes from `prev` to `next` (nae.java:76-140): none, show (first icon: fade in 350 ms),
 * hide (last icon: fade out 150 ms, then display none), replace (the old one fades out in 150 ms, the
 * new one fades in over 350 ms starting 350 ms after the change). */
function transition(prev, next) {
    if (prev === next)
        return "none"
    if (prev === "")
        return "show"
    if (next === "")
        return "hide"
    return "replace"
}

/* What the always-on screen's layout needs to know: the sensor hub draws the face with the icons
 * as the AP drew them at the last update, so a change of this is a change of that layout
 * (ambient-aod-18). The icons are static and at full opacity there. */
function ambientKey(statusKey, chipKey) {
    return (statusKey !== "" ? "s:" + statusKey : "") + (chipKey !== "" ? "|c:" + chipKey : "")
}
