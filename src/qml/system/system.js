/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The rules of the power system surfaces (W2-launcher-power-system) as pure
 * functions, so that every number of the audit is a test assertion
 * (tst_system.qml): the power menu, the touch lock, Emergency SOS, the
 * screenshot overlay and the error dialogs.
 *
 * Stock evidence (CP3A, audit gaps in brackets):
 *   power menu       WearGlobalActionsProvider, PhoneWindowManager.java:
 *                    619-626 (power-boot-warnings-01)
 *   touch lock       CSUI modes/touchlock/TouchLockUiComposer,
 *                    TouchLockAnimationController (wake-sleep-display-03)
 *   SOS              GestureLauncherService.java:42-46, 209-218, 244-257,
 *                    safetyhub nry.java, tnt.java (apps-misc-07)
 *   screenshot       WearScreenshotService$$ExternalSyntheticLambda0
 *                    (system-dialogs-misc-08)
 *   error dialogs    AppErrorDialog, AppNotRespondingDialog
 *                    (system-dialogs-misc-01, -03)
 */

/* ---- power menu -------------------------------------------------------- */

// config_veryLongPressTimeout (RRO android.overlay.buttons) with
// veryLongPressOnPowerBehavior = 1: the crown held 3000 ms (mce
// long_press_delay in 60eos-crown.conf sends power_button_trigger
// "asteroid-crown-long")
var VERY_LONG_PRESS_MS = 3000

/* The rows, in order (WearGlobalActionsProvider_Factory.java:102-280, rows
 * after setup): Power off, Restart, Touch lock. No emergency rows: they
 * have nothing to open on this watch (DECISIONS Q32). Touch lock is there
 * only where the touch lock exists. */
function powerMenuRows(touchLockAvailable) {
    var rows = [
        { id: "powerOff", icon: "ios-power" },
        { id: "restart", icon: "ios-refresh" }
    ]
    if (touchLockAvailable)
        rows.push({ id: "touchLock", icon: "ms-screen_lock_portrait" })
    return rows
}

/* Layout of the menu on the 384 px screen (VALUES.tsv global_actions_*
 * horizontal 5.2 %, vertical 21.8 %; row 52 dp = 104 px, 2 dp above and
 * below each row = 8 px between rows, corners 26 dp, content padding 14 x
 * 6 dp, icon 24 dp, icon gap 6 dp) */
function powerMenuMetrics(width, height) {
    return {
        sideMargin: Math.round(0.052 * width),
        verticalMargin: Math.round(0.218 * height),
        rowHeight: 104,
        rowGap: 8
    }
}

/* ---- touch lock --------------------------------------------------------- */

// the crown held 2000 ms turns it off (TouchLockAnimationController
// 22-47); the exit view hides 2000 ms after it appeared (TouchLockUiComposer
// 147-238)
var TOUCH_EXIT_HOLD_MS = 2000
var TOUCH_HINT_MS = 2000
// the ring: 8 dp stroke from 12 o'clock clockwise (666-745)
var TOUCH_RING_WIDTH = 16
// the row's side padding 7.4 % of the width; the crown motif 60 x 44 dp,
// 8 dp from the text (touch_lock_padding_percentage 0.074,
// touch_lock_lottie_animation_width/height)
var TOUCH_SIDE_FRACTION = 0.074
var TOUCH_MOTIF_W = 120
var TOUCH_MOTIF_H = 88
var TOUCH_MOTIF_GAP = 16
// the ring springs back when the crown is let go early: damping 1.0,
// stiffness 260 (TouchLockUiComposer$ProgressIndicator$1$1 207-230)
var TOUCH_SPRING_DAMPING = 1.0
var TOUCH_SPRING_STIFFNESS = 260

/* wrist-orientation-13: the crown motif sits on the physical crown. The
 * wrist-orientation mode (Settings > Display > Wrist orientation,
 * /org/asteroidos/settings/wrist-orientation-mode): 0 left wrist crown on
 * the right (the default), 1 left wrist crown on the left, 2 right wrist
 * crown on the right, 3 right wrist crown on the left. A launcher that
 * turns its screen over 180 degrees for the flipped modes (stock rotates
 * the display, rotation 2 selects the mirrored layout) passes
 * displayRotated: the crown is then on the right again in the screen's own
 * coordinates. */
function crownOnRight(mode, displayRotated) {
    var m = Number(mode)
    var physicalRight = (m === 0 || m === 2 || !(m >= 0 && m <= 3))
    return displayRotated ? !physicalRight : physicalRight
}

/* Where the exit ring stands: the crown went down at downAt (ms), now is
 * `now`; 0..1 linear over 2000 ms */
function ringProgress(downAt, now) {
    if (downAt < 0)
        return 0
    return Math.max(0, Math.min(1, (now - downAt) / TOUCH_EXIT_HOLD_MS))
}

/* The ring springs back (critically damped, stiffness 260): the time it
 * takes to settle (99 %) in ms, as the closed form 6.64 / sqrt(k) s */
function springBackMs() {
    return Math.round(6640 / Math.sqrt(TOUCH_SPRING_STIFFNESS))
}

/* The keys touch lock filters (config_touchLockButtonGesturesToFilter =
 * power_button_short_press | long_press | very_long_press |
 * stem_primary_button_short_press): the crown press and hold, the side
 * button's short press. The side button's hold (assistant) is not filtered. */
var FILTERED_KEYS = ["crownPress", "crownLong", "sidePress"]
function filters(key) { return FILTERED_KEYS.indexOf(key) >= 0 }

/* ---- Emergency SOS ------------------------------------------------------- */

var SOS_PRESSES = 5
// each press at most 500 ms after the one before, the five together took
// longer than 600 ms (config_defaultMinEmergencyGestureTapDurationMillis
// 200 -> 600 in android.overlay.buttons), then 3000 ms in which presses
// do not count (GestureLauncherService.java:42-46)
var SOS_MAX_INTERVAL_MS = 500
var SOS_MIN_TOTAL_MS = 600
var SOS_COOLDOWN_MS = 3000
// the vibration at the trigger (config_mashPressPowerButtonVibrateDurationMillis)
var SOS_VIBRATE_MS = 500
// the countdown (safetyhub tnt.java: 5 s; x2 with a touch-exploration screen reader)
var SOS_COUNTDOWN_MS = 5000
var SOS_COUNTDOWN_SCREEN_READER_FACTOR = 2

function newSosCounter() {
    return { count: 0, first: 0, last: 0, cooldownUntil: 0 }
}

/* A crown press at `now` (ms): "trigger" for the fifth press that makes a
 * gesture, else "count". Presses in the cooldown, and a fifth press that
 * came too fast (a key mash of under 600 ms), do not trigger. */
function sosPress(counter, now) {
    if (now < counter.cooldownUntil) {
        counter.count = 0
        return "count"
    }
    if (counter.count > 0 && now - counter.last <= SOS_MAX_INTERVAL_MS) {
        counter.count++
    } else {
        counter.count = 1
        counter.first = now
    }
    counter.last = now
    if (counter.count < SOS_PRESSES)
        return "count"
    // five presses
    counter.count = 0
    if (now - counter.first <= SOS_MIN_TOTAL_MS)
        return "count"
    counter.cooldownUntil = now + SOS_COOLDOWN_MS
    return "trigger"
}

/* A burst in progress: a second press (or later) of a sequence that may
 * still become the gesture. The presses of a burst do not run the crown's
 * Home action (the app list would open and close five times). */
function sosBurst(counter, now) {
    return counter.count >= 2 && now - counter.last <= SOS_MAX_INTERVAL_MS
}

/* The countdown in ms (SOS_COUNTDOWN_MS, twice as long for a screen reader) */
function sosCountdownMs(screenReaderExploring) {
    return SOS_COUNTDOWN_MS * (screenReaderExploring ? SOS_COUNTDOWN_SCREEN_READER_FACTOR : 1)
}

/* The local emergency number: stock's table by region (the first number
 * of each country in the Safety app's config 45716896), 112 as stock's
 * default for the rest. A number the user set wins. */
var REGION_NUMBERS = {
    AT: "112", AU: "000", BE: "112", BG: "112", BR: "190", CA: "911", CH: "112",
    CZ: "112", DE: "112", DK: "112", ES: "112", FI: "112", FR: "112", GB: "999",
    IE: "112", IN: "112", IT: "112", IQ: "911", JP: "110", KR: "112", MX: "911",
    NL: "112", NO: "112", PL: "112", PT: "112", SE: "112", SK: "112", SG: "999",
    TW: "110", US: "911", TR: "112"
}
function emergencyNumber(localeName, override) {
    var o = String(override || "").replace(/[^0-9+*#]/g, "")
    if (o !== "")
        return o
    var m = /_([A-Za-z]{2})/.exec(String(localeName || ""))
    var region = m ? m[1].toUpperCase() : ""
    return REGION_NUMBERS[region] || "112"
}

/* Layout of the countdown screen (emergency_alert_activity.xml, dimens in
 * dp x 2): the ring 5 dp (10 px) wide, "Calling" 31 dp (62 px) from the
 * top, the number 12 dp (24 px) below it, the cancel button 19 dp (38 px)
 * from the bottom. Colours: ring #ee675c on #532420, the X's tint #303133. */
var SOS_RING_WIDTH = 10
var SOS_TITLE_TOP = 62
var SOS_NUMBER_GAP = 24
var SOS_CANCEL_BOTTOM = 38
var SOS_COLOR_MAIN = "#ee675c"
var SOS_COLOR_TRACK = "#532420"
var SOS_COLOR_ICON = "#303133"

/* ---- screenshot ---------------------------------------------------------- */

// the display is held on 3000 ms (the service asks mce)
var SHOT_DISPLAY_HOLD_MS = 3000
// white flash alpha 0 -> 0.18 in 150 ms, 0.18 -> 0 in 150 ms, both linear
var SHOT_FLASH_ALPHA = 0.18
var SHOT_FLASH_RISE_MS = 150
var SHOT_FLASH_FALL_MS = 150
// the preview (circle, 6 dp = 12 px inset, 8 dp ring #32312F) scales 1.0 ->
// 0.4 in 250 ms path(0.2, 0, 0, 1), pivot bottom centre; held 1350 ms;
// translateY 0 -> 400 px in 150 ms path(0.3, 0, 0.8, 0.49)
var SHOT_INSET = 12
var SHOT_RING = 16
var SHOT_RING_COLOR = "#32312F"
var SHOT_SCALE_TO = 0.4
var SHOT_SCALE_MS = 250
var SHOT_SCALE_EASING = [0.2, 0, 0, 1, 1, 1]
var SHOT_HOLD_MS = 1350
var SHOT_EXIT_Y = 400
var SHOT_EXIT_MS = 150
var SHOT_EXIT_EASING = [0.3, 0, 0.8, 0.49, 1, 1]
// the thud 100 ms after the capture
var SHOT_HAPTIC_DELAY_MS = 100

/* ---- error dialogs --------------------------------------------------------- */

// AppErrorDialog: the buttons do nothing for 1000 ms after the dialog shows
// (BaseErrorDialog.java:67-71), it closes by itself after 300000 ms
// (AppErrorDialog.java:59-81, the dialog's own timeout)
var ERROR_BUTTON_LOCK_MS = 1000
var ERROR_AUTO_CLOSE_MS = 300000
// a second crash of the same program within 120000 ms shows the dialog, one
// dialog per program per 120000 ms (ActivityManagerConstants.java:1111)
var CRASH_INTERVAL_MS = 120000
// no pong for 5000 ms (the input dispatching timeout)
var ANR_TIMEOUT_MS = 5000
