/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The crown and an application's full screen keyboard (keymap.js crownPress and crownWake, CR-45): stock
// Wear OS (config_shortPressOnPowerBehavior 5, SHORT_PRESS_POWER_CLOSE_IME_OR_GO_HOME) closes the input
// method with the first press and goes Home with the next. Pure functions, run in place (MODE=repo).
import QtQuick
import QtTest
import "../../src/qml/compositor/keymap.js" as KeyMap

TestCase {
    name: "KeyMapKeyboard"

    // a plain screen: nothing special in front
    function ctx(over) {
        var c = { setup: false, callRinging: false, callShown: false, claimSide: false, claimCrown: false,
                  alertShown: false, assistantShown: false, splash: false, appActive: false,
                  appKeyboardOpen: false, option: "assistant", shortcut: false, tiltToWake: true,
                  touchToWake: true, fromAmbient: false }
        for (var k in over)
            c[k] = over[k]
        return c
    }

    function test_00_crown_closes_the_keyboard_first() {
        compare(KeyMap.crownPress(ctx({ appActive: true, appKeyboardOpen: true })), "closeKeyboard")
        // the client closed it (set_keyboard_open 0): the next press goes Home
        compare(KeyMap.crownPress(ctx({ appActive: true, appKeyboardOpen: false })), "leaveApp")
        // no application in front: the flag of a window behind does not count
        compare(KeyMap.crownPress(ctx({ appActive: false, appKeyboardOpen: true })), "home")
        // a context without the flag (older callers) is a closed keyboard
        var c = ctx({ appActive: true })
        delete c.appKeyboardOpen
        compare(KeyMap.crownPress(c), "leaveApp")
    }

    function test_01_what_is_above_the_app_goes_first() {
        var k = { appActive: true, appKeyboardOpen: true }
        function with_(o) {
            var c = ctx(k)
            for (var n in o)
                c[n] = o[n]
            return KeyMap.crownPress(c)
        }
        compare(with_({ setup: true }), "none")
        compare(with_({ touchLocked: true }), "touchLockHint")
        compare(with_({ powerMenuShown: true }), "closePowerMenu")
        compare(with_({ callRinging: true }), "silenceCall")
        compare(with_({ headsUpShown: true }), "closeHeadsUp")
        compare(with_({ systemDialogShown: true }), "closeSystemDialog")
        compare(with_({ keyguardLocked: true }), "showBouncer")
        compare(with_({ chargingShown: true }), "closeCharging")
        compare(with_({ assistantShown: true }), "closeAssistant")
        compare(with_({ splash: true }), "none")
        // the app claimed the crown (OVERRIDE_SYSTEM_KEY_BEHAVIOR_IN_FOCUSED_WINDOW): its own
        compare(with_({ claimCrown: true }), "claim")
        compare(with_({ alertShown: true }), "hideAlert")
        compare(with_({ callShown: true }), "hideCall")
    }

    function test_02_wake_press_closes_the_keyboard() {
        // the press from the always-on display runs the Home action (tilt- and touch-to-wake on)
        compare(KeyMap.crownWake(ctx({ fromAmbient: true, appActive: true, appKeyboardOpen: true })), "closeKeyboard")
        compare(KeyMap.crownWake(ctx({ fromAmbient: true, appActive: true })), "face")
        compare(KeyMap.crownWake(ctx({ fromAmbient: true, appKeyboardOpen: true })), "face")
        // from a fully dark screen, or without both wake gestures: the press only wakes
        compare(KeyMap.crownWake(ctx({ fromAmbient: false, appActive: true, appKeyboardOpen: true })), "none")
        compare(KeyMap.crownWake(ctx({ fromAmbient: true, tiltToWake: false, appActive: true, appKeyboardOpen: true })), "none")
        compare(KeyMap.crownWake(ctx({ fromAmbient: true, appActive: true, appKeyboardOpen: true, callShown: true })), "none")
    }

    // R5 B-03: a palm over the screen (mce 0014 "palm-cover") as stock's KEYCODE_SLEEP: a ringing call is
    // silenced (config_silenceRingerOnSleepKey), else goToSleep (ambient or off)
    function test_03_palm_cover() {
        compare(KeyMap.palmCover(ctx({})), "sleep")
        compare(KeyMap.palmCover(ctx({ callRinging: true, callShown: true })), "silenceCall")
        // a ringing call already silenced keeps its screen; a call in progress goes to sleep with the rest
        compare(KeyMap.palmCover(ctx({ callShown: true, callOngoing: false })), "none")
        compare(KeyMap.palmCover(ctx({ callShown: true, callOngoing: true })), "sleep")
        // the key never reaches the window in front: an app, its keyboard, a claim, setup, touch lock,
        // an alert or the assistant change nothing
        var others = [{ appActive: true }, { appActive: true, appKeyboardOpen: true }, { claimCrown: true },
                      { claimSide: true }, { setup: true }, { touchLocked: true }, { alertShown: true },
                      { assistantShown: true }, { headsUpShown: true }, { chargingShown: true },
                      { keyguardLocked: true }, { powerMenuShown: true }]
        for (var i = 0; i < others.length; i++)
            compare(KeyMap.palmCover(ctx(others[i])), "sleep", JSON.stringify(others[i]))
        // ringing wins over all of them
        compare(KeyMap.palmCover(ctx({ callRinging: true, callShown: true, setup: true, appActive: true })), "silenceCall")
    }

    // D-29: the find-my-watch page rings (the phone's find device): the crown and the side button stop the sound,
    // as Find Hub says ("To stop the sound, you can also press the power button", com.google.android.apps.adm
    // ring_device_message_1), also the press that wakes the screen and also on a locked watch (a lost watch)
    function test_03b_find_my_watch_press_stops_the_sound() {
        var f = { findWatchRinging: true }
        function with_(o) {
            var c = ctx(f)
            for (var n in o)
                c[n] = o[n]
            return c
        }
        compare(KeyMap.crownPress(with_({})), "stopFindWatch")
        compare(KeyMap.sidePress(with_({}), 1), "stopFindWatch")
        compare(KeyMap.crownWake(with_({ fromAmbient: false })), "stopFindWatch")
        compare(KeyMap.crownWake(with_({ fromAmbient: true })), "stopFindWatch")
        // above the lock, the heads-up, a system dialog, an app's claim, the charging screen and the assistant
        compare(KeyMap.crownPress(with_({ keyguardLocked: true })), "stopFindWatch")
        compare(KeyMap.crownWake(with_({ keyguardLocked: true })), "stopFindWatch")
        compare(KeyMap.sidePress(with_({ keyguardLocked: true }), 1), "stopFindWatch")
        compare(KeyMap.crownPress(with_({ headsUpShown: true })), "stopFindWatch")
        compare(KeyMap.crownPress(with_({ systemDialogShown: true })), "stopFindWatch")
        compare(KeyMap.crownPress(with_({ claimCrown: true, appActive: true })), "stopFindWatch")
        compare(KeyMap.sidePress(with_({ claimSide: true }), 1), "stopFindWatch")
        compare(KeyMap.crownPress(with_({ chargingShown: true })), "stopFindWatch")
        compare(KeyMap.crownPress(with_({ assistantShown: true })), "stopFindWatch")
        compare(KeyMap.sidePress(with_({ option: "recents" }), 1), "stopFindWatch")
        // what stays above it: setup, touch lock (its hint), the SOS countdown, the power menu, a ringing call
        compare(KeyMap.crownPress(with_({ setup: true })), "none")
        compare(KeyMap.crownPress(with_({ touchLocked: true })), "touchLockHint")
        compare(KeyMap.sidePress(with_({ touchLocked: true }), 1), "touchLockHint")
        compare(KeyMap.crownWake(with_({ touchLocked: true })), "touchLockHint")
        compare(KeyMap.crownPress(with_({ sosShown: true })), "none")
        compare(KeyMap.sidePress(with_({ sosShown: true }), 1), "none")
        compare(KeyMap.crownPress(with_({ powerMenuShown: true })), "closePowerMenu")
        compare(KeyMap.crownPress(with_({ callRinging: true })), "silenceCall")
        compare(KeyMap.sidePress(with_({ callRinging: true }), 1), "silenceCall")
        // the side button's hold is the assistant's as before (the page does not take it)
        compare(KeyMap.sideHold(with_({})), "assistant")
        // without the page nothing changes
        compare(KeyMap.crownPress(ctx({ findWatchRinging: false })), "home")
        compare(KeyMap.sidePress(ctx({ findWatchRinging: false }), 1), "none")
        compare(KeyMap.crownWake(ctx({ findWatchRinging: false })), "none")
    }
}
