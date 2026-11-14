/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The setup flow's numbers and rules, as stock CP3A's setup wizard (W3-launcher-setup).
 * Sources are the setup wizard package's VALUES.tsv and decompiled sources; each constant says which.
 * Pure functions only, so the tests can check every number without a screen. */

// ---- timing (VALUES.tsv, com.google.android.wearable.setupwizard) ----
var screenOnSeconds = 360        // pre_pairing_screen_timeout: a setup screen keeps the display on this long
var shutdownSeconds = 3600       // seconds_to_shutdown_when_idle_on_welcome: powered off when idle, off the charger
var autoLanguageSeconds = 180    // seconds_to_auto_jump_locale: the first screen opens the language list by itself
var minBattery = 20              // min_battery_for_oobe
// ours: no word from the phone's bond this long after the watch accepted the code = the bond failed
var bondWaitMs = 30000
// ours: a link that is up with no pairing request this long = an already bonded phone (no code is shown)
var bondedLinkMs = 8000

// ---- the pages' geometry, as fractions of the screen unless the name says dp ----
var first = {
    titleTop: 0.581,             // 0.5312 + the title's 0.05 padding (pairscreen_title_text_position_top_percent, _padding_top_percent)
    titleWidth: 0.72,            // title_text_centered_width_percent
    chipGap: 0.05,               // pairscreen_title_text_padding_bottom_percent
    chipWidthDp: 52, chipHeightDp: 32, chipRadiusDp: 18, chipGlyphDp: 24,   // pairscreen_icon_background_*
    receiverHeight: 0.22,        // pairscreen_interaction_receiver_height_percent
    animationMs: 3500, pauseMs: 1000                                          // the phone and watch animation, then its pause
}
var list = { padV: 0.218, padSide: 0.052, rowDp: 52, rowPadH: 14, rowPadV: 6 }       // list_padding_*, locale_item_height
var instructions = { side: 0.052, top: 0.10, bottom: 0.354, iconDp: 58, downloadGapDp: 8, connectGapDp: 8,
                     helpGapDp: 16 }                                                 // companion_details_padding_percent_bottom, pair_*
var code = { top: 0.10, spacingDp: 11, numeralSp: 30, loopMs: 1670 }                 // fake_dialog_padding_top_percent, pairing_code_key_letter_spacing_v2
var connecting = { orbitMs: 3000 }                                                   // the orbit animation
var complete = { checkDp: 122, checkCenter: 0.333, checkMs: 1000, shrink: 0.82, titleOffsetDp: 58, stiffness: 260,
                 dampingRatio: 1.0, holdMs: 1000, titleWidth: 0.72 }                 // success_screen_*, SuccessMessageComposableScreen
// stock oobe_completed_vibrator_timings / _amplitudes (Pixel Watch overlay): 200/50/50/50 ms at 2/2/2/5 of 255
var completeVibration = { timings: [200, 50, 50, 50], amplitudes: [2, 2, 2, 5] }

// the screens cross-fade (setup-wizard-18): in from alpha 0.1 over 250 ms after 150 ms, out to 0.1 over 150 ms
var fade = {
    inFrom: 0.1, inDelayMs: 150, inMs: 250, inEasing: [0.2, 0, 0, 1],
    outTo: 0.1, outMs: 150, outEasing: [0.3, 0, 1, 1],
    lockScale: 0.85
}

// ---- the battery gate (BatteryLevelProgressBarComposableKt, ChargingIconComposableKt) ----
var gate = {
    strokeDp: 8, gapDp: 1, markDeg: 342,
    fillStart: 270, fillEnd: 339.5,       // the filled arc
    trackStart: 344.5, trackEnd: 270,     // the empty track (the long way round, 344.5 .. 630)
    fillFraction: 0.19,                   // the filled arc is full at level/100 = 0.19, just before the 20 % mark
    boltDp: 20, boltTopDp: 43, levelSp: 50, textSp: 12
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

/* The gate is shown below minBattery, and only while the level is known. */
function gateNeeded(level, known) {
    return known !== false && typeof level === "number" && level >= 0 && level < minBattery
}

/* The sweep in degrees of the filled arc for a battery level in percent: 0 .. 69.5 */
function gateFillSweep(level) {
    var f = clamp((level / 100) / gate.fillFraction, 0, 1)
    return f * (gate.fillEnd - gate.fillStart)
}

/* The sweep of the empty track: 344.5 .. 630 */
function gateTrackSweep() { return 360 + gate.trackEnd - gate.trackStart }

// ---- the language list (setup-wizard-03) ----

/* The first letter capitalised (stock: capitalize the display name) */
function capitalize(s) {
    if (!s || s.length === 0)
        return ""
    return s.charAt(0).toUpperCase() + s.slice(1)
}

/* rows: [{ name, locale, region, regionLabel }] in the model's own (locale aware) order. The name is shown in
 * its own language with the region where the language file has one, the first letter capitalised, and the
 * preferred locale first (stock: preferred_locales en_US, then Collator order). `preferred` is a list of
 * locale codes, first match wins: the first of them present is moved to the front, the rest stay in order. */
function languageList(rows, preferred) {
    var out = []
    for (var i = 0; i < rows.length; i++) {
        var r = rows[i]
        var name = capitalize(r.name)
        var label = r.regionLabel || ""
        if (label !== "" && name.indexOf(label) < 0)
            name = name + " (" + label + ")"
        out.push({ name: name, locale: r.locale, source: i })
    }
    var pref = preferred || []
    for (var p = 0; p < pref.length; p++) {
        for (var j = 0; j < out.length; j++) {
            if (out[j].locale === pref[p] || out[j].locale.replace(/\..*$/, "") === pref[p]) {
                var first = out.splice(j, 1)[0]
                out.unshift(first)
                return out
            }
        }
    }
    return out
}

// ---- the flow ----

/* The pages, in the stack's terms. The stack is the swipe-back history: the first screen is the root and back
 * is ignored there; the language list leads to the instructions (the list is left behind, so back from the
 * instructions is the first screen); the help screen sits on the instructions. After the bond the stack is
 * cleared: nothing goes back to the pairing screens. */
var pages = {
    charge: "charge", first: "first", language: "language", instructions: "instructions", help: "help",
    connecting: "connecting", place: "place", region: "region", city: "city", time: "time", date: "date", complete: "complete"
}

/* the page the stack goes back to from its top, or "" when back is ignored (an empty history) */
function backTarget(stack) {
    return stack.length > 1 ? stack[stack.length - 2] : ""
}

/* the stack after a page is opened */
function pushPage(stack, page) {
    var s = stack.slice()
    if (page === pages.instructions && s.length > 0 && s[s.length - 1] === pages.language)
        s.pop()                       // the language list is not kept: its choice is made
    s.push(page)
    return s
}
function popPage(stack) {
    var s = stack.slice()
    if (s.length > 1)
        s.pop()
    return s
}

/* the pages that have a swipe back at all */
function backAllowed(stack, codeUp) {
    if (codeUp || stack.length < 2)
        return false
    var top = stack[stack.length - 1]
    return top === pages.language || top === pages.instructions || top === pages.help || top === pages.region
           || top === pages.city
}

/* The time zone is asked while it is unknown (setup-wizard-04): the image default and the empty answer. */
function zoneUnknown(tz) {
    return !tz || tz === "" || tz === "UTC" || tz === "Etc/UTC" || tz === "Etc/UCT" || tz === "UCT" || tz === "Zulu"
           || tz === "Etc/Zulu" || tz === "Universal" || tz === "Etc/Universal" || tz === "Etc/Unknown" || tz === "Factory"
}

/* After the bond: the pages the phone could not fill in. `clockFromPhone` is the key btsyncd writes when the
 * phone set the clock; the time zone page is asked while the zone is unknown. */
function pagesAfterBond(tz, clockFromPhone) {
    var p = []
    if (zoneUnknown(tz))
        p.push(pages.place)
    if (!clockFromPhone) {
        p.push(pages.time)
        p.push(pages.date)
    }
    p.push(pages.complete)
    return p
}

// ---- pairing during setup (setup-wizard-09, -14, connectivity-system-ux-04) ----
// lipstick BluetoothAgent::State, in declaration order
var agent = { Idle: 0, ReqPinCode: 1, ReqPasskey: 2, DispPinCode: 3, DispPasskey: 4, ReqConfirmation: 5,
              ReqAuthorization: 6, AuthService: 7 }

/* What the setup does with a request from the agent.
 *   ctx.bonded  a phone has paired already (any later request is another device's)
 * "show-accept"  the numeric comparison: show the code, answer yes at once (stock: no buttons, auto-confirm)
 * "accept"       a plain consent (Just Works) from the first pairing: answered yes, nothing shown
 * "show"         the watch shows a code the phone types: show it, nothing to answer
 * "cancel"       cannot be done during setup (a PIN or passkey to type) or another device after the bond
 * "none"         idle or a service request (the agent answers those itself) */
function agentAction(state, ctx) {
    if (state === agent.Idle || state === agent.AuthService)
        return "none"
    if (ctx && ctx.bonded)
        return "cancel"
    switch (state) {
    case agent.ReqConfirmation: return "show-accept"
    case agent.ReqAuthorization: return "accept"
    case agent.DispPasskey:
    case agent.DispPinCode: return "show"
    default: return "cancel"
    }
}

/* The code screen's title: Legacy for a PIN, else Secure */
function codeKind(state) {
    return state === agent.DispPinCode || state === agent.ReqPinCode ? "legacy" : "secure"
}

/* the code, six digits */
function codeText(state, passkey, pin) {
    if (state === agent.DispPinCode)
        return String(pin)
    return ("000000" + passkey).slice(-6)
}

/* Pairing is done when a link is up and the code was accepted (or no code was needed for an already bonded phone,
 * which the caller turns into `accepted` after bondedLinkMs). */
function pairingDone(connected, accepted) {
    return connected === true && accepted === true
}

// ---- the display policy (setup-wizard-05) ----

/* Whether the display should be held on right now: a setup screen is up, the 360 s since it opened or the last
 * touch have not passed, and the display is not in ambient. */
function holdDisplay(now, lastActivity, ambient) {
    return !ambient && now - lastActivity < screenOnSeconds * 1000
}

/* The idle power-off: armed off the charger, cancelled on it and when setup has finished. `seconds` goes to the
 * exact wake-up alarm; 0 cancels. */
function powerOffSeconds(charging, finished) {
    return charging || finished ? 0 : shutdownSeconds
}

/* A touch re-arms the idle alarm only when the last arming is a minute old (one IPC per minute at most) */
function rearm(now, armedAt) {
    return armedAt <= 0 || now - armedAt >= 60000
}
