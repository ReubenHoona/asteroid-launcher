/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */
.pragma library

/* The key map of the watch (W2-launcher-keys-lifecycle): what the side
 * button and the crown do in each context, as pure functions so that the
 * whole table is unit tested (tests tst_keymap.qml). KeyRouter.qml feeds
 * them the state of the screen and runs the answer.
 *
 * Order of precedence, from stock CP3A (audit choice-settings-11 "stock"):
 *   1. setup not complete: the keys only wake (PhoneWindowManager.java
 *      :2290-2298, 5152-5160, 5962-5968);
 *   2. a call ringing: a press silences the ringer
 *      (PhoneWindowManager.java:5004-5010, 1499-1512);
 *   3. a firing alarm or timer: the side button is the presenter's (stock
 *      DeskClock maps only KEYCODE_STEM_1 = dismiss: it claims "side"); the
 *      crown is not: it goes to the face and the alarm keeps ringing, no
 *      snooze on the crown (DECISIONS.md Q49, buttons-navigation-22);
 *   4. the app in front may claim the side button (exercise pause/resume:
 *      OVERRIDE_SYSTEM_KEY_BEHAVIOR_IN_FOCUSED_WINDOW);
 *   5. the global map: side press = Recents, double = previous app,
 *      triple = screen reader (only while its shortcut is on), hold = the
 *      assistant; crown press = close keyboard, else Home (on the face the
 *      app list); a crown press while a call runs hides the call view
 *      (PhoneWindowManager.java:5008-5009, 6328: incall_power_button_behavior
 *      default 1 = the key does not end the call).
 */

// Stock's multi-press window (config_multiPressTimeout, 300 ms: PLAN.md
// section 4, row 5) and long press (300 ms: DECISIONS.md Q5b; mce
// side_key_long_press_delay in 61eos-side-key.conf)
var MULTI_PRESS_MS = 300
var HOLD_MS = 300

var OPTION_ASSISTANT = "assistant"
var OPTION_RECENTS = "recents"

function validOption(v) {
    return v === OPTION_RECENTS ? OPTION_RECENTS : OPTION_ASSISTANT
}

/* How many presses make a sequence: the stock press counting waits for
 * three presses only while the screen reader shortcut is on (else two:
 * accessibility-lock-security-19, OVERLAYS.md:129). Option 'assistant'
 * has no press action, so only the screen reader shortcut counts. */
function maxPresses(option, shortcut) {
    if (shortcut)
        return 3
    return validOption(option) === OPTION_RECENTS ? 2 : 1
}

/* A press sequence: state {count, last}; returns the count of this press.
 * A press within MULTI_PRESS_MS of the last one continues the sequence
 * until maxCount; any other press starts a new one. */
function newCounter() { return { count: 0, last: -1e9 } }

function press(counter, now, maxCount) {
    if (counter.count > 0 && counter.count < maxCount && now - counter.last <= MULTI_PRESS_MS)
        counter.count++
    else
        counter.count = 1
    counter.last = now
    return counter.count
}

/* The crown's double press is stock's Wallet shortcut (ResolvePayActivity),
 * which is out of reach: it does nothing, and the second press of a double
 * must not run the single press' action a second time (open the app list,
 * then close it). True if this press is the second of a double. */
function crownIsSecond(counter, now) {
    var second = counter.count > 0 && now - counter.last <= MULTI_PRESS_MS
    counter.count = second ? 2 : 1
    counter.last = now
    return second
}

/* Side button press (released, display on). c:
 *   setup          first run not finished
 *   callRinging    a call view is up, ringing, not silenced
 *   claimSide      the front window (an alarm presenter, or an app that
 *                  claimed the side button) takes it
 *   alertShown     a firing alarm or timer is in front
 *   option         'assistant' | 'recents' (/org/asteroidos/ux/side-button)
 *   shortcut       the screen reader shortcut is on
 * count: the press number in the sequence (press()).
 * Answers: none, silenceCall, claim, recents, previous, screenReader. */
function sidePress(c, count) {
    if (c.setup)
        return "none"
    if (c.callRinging)
        return "silenceCall"
    if (c.claimSide)
        return "claim"
    // a firing alarm that did not claim the key: nothing happens under it
    if (c.alertShown)
        return "none"
    if (c.shortcut && count >= 3)
        return "screenReader"
    if (validOption(c.option) === OPTION_RECENTS) {
        if (count === 1)
            return "recents"
        if (count === 2)
            return "previous"
    }
    return "none"
}

/* Side button held HOLD_MS: the assistant in both options (above a call
 * view too: calls-23, interruptions-08), but not during setup and not
 * over a firing alarm (interruptions-09). */
function sideHold(c) {
    if (c.setup || c.alertShown)
        return "none"
    return "assistant"
}

/* Crown press. c:
 *   setup, callRinging
 *   assistantShown   the assistant is open
 *   splash           the launch splash is up
 *   claimCrown       the front window claimed the crown (an app such as
 *                    the exercise; the alarm presenter does not)
 *   callShown        a call view is up (in progress, or ringing silenced)
 *   appActive        an application window is in front
 * Answers: none, silenceCall, closeAssistant, claim, hideAlert, hideCall,
 * leaveApp, home. */
function crownPress(c) {
    if (c.setup)
        return "none"
    if (c.callRinging)
        return "silenceCall"
    if (c.assistantShown)
        return "closeAssistant"
    if (c.splash)
        return "none"
    if (c.claimCrown)
        return "claim"
    // a firing alarm: its window leaves, the alarm keeps ringing, and the
    // press goes on to the face (Q49: stock Home; no snooze on the crown)
    if (c.alertShown)
        return "hideAlert"
    if (c.callShown)
        return "hideCall"
    if (c.appActive)
        return "leaveApp"
    return "home"
}

/* The crown pressed to wake from the always-on display (mce
 * actions_single_off sends asteroid-crown-wake after it unblanked): stock
 * runs the Home action too, but only if tilt-to-wake and touch-to-wake are
 * both on (KeyGestureUtils.java:83-103, PowerKeyRule.java:130-160). From a
 * fully dark screen the press only wakes. */
function crownWake(c) {
    if (c.setup || !c.fromAmbient || !c.tiltToWake || !c.touchToWake)
        return "none"
    if (c.callRinging || c.callShown || c.assistantShown || c.claimCrown)
        return "none"
    return "face"
}
