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
}
