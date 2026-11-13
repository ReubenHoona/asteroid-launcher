/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2013 John Brooks <john.brooks@dereferenced.net>
 *               2013 Jolla Ltd.
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.utils
import org.nemomobile.lipstick
import "keymap.js" as KeyMap

/* The hardware keys in the compositor (split out of compositor.qml): one
 * router that walks the context of the screen for each key event and stops
 * at the first taker (keymap.js: the order of precedence of stock CP3A and
 * the whole table). Owned by W2-launcher-keys-lifecycle.
 *
 * Fed by:
 *  - assistantKey (mce's power_button_trigger from the side button): "side-key"
 *    sent at the release of a short press and "side-key-long" when the
 *    button has been held 300 ms (mce 0005, side_key_long_press_delay in
 *    61eos-side-key.conf). Presses are counted here (300 ms window, stock
 *    config_multiPressTimeout), so mce needs no counting patch.
 *  - crownButton ("asteroid-crown" at the first release of a press, and
 *    "asteroid-crown-wake" for a press that woke the display).
 *
 * Side button, Settings > Buttons > Side button (dconf
 * /org/asteroidos/ux/side-button, choice 5):
 *   'assistant' (default, the user's): press nothing; hold the assistant.
 *   'recents' (stock): press Recents, double press the previous app (else
 *   the face), hold the assistant. Triple press toggles the screen reader
 *   in both options, only while its shortcut is on.
 * Crown (fixed): press = close the keyboard or viewer, else the face, on
 * the face the app list; the second press of a double does nothing (stock:
 * Wallet, out of reach); held: mce's power menu.
 * A ringing call is silenced by either key; a firing alarm or timer (a
 * claim by the presenter) takes both, an app in front may claim the side
 * button (KeyClaims, D-Bus org.asteroidos.launcher.Keys); during setup the
 * keys only wake.
 *
 * Reads compositor.qml's ids (root, comp, launchSplash, homeLoader, arbiter)
 * through the context. */
QtObject {
    id: keyRouter

    /* ---- the state of the screen the map reads ------------------------ */

    property QtObject sideButtonSetting: ConfigurationValue {
        key: "/org/asteroidos/ux/side-button"
        defaultValue: "assistant"
    }
    readonly property string sideOption: KeyMap.validOption(String(sideButtonSetting.value))

    // Settings > Gestures (mce, which the modes engine mirrors): both on is
    // stock's default; the crown's Home action from the always-on display
    // needs both (buttons-navigation-18)
    property bool tiltToWakeOn: typeof modes !== "undefined" && modes !== null ? modes.tiltToWake : true
    property bool touchToWakeOn: typeof modes !== "undefined" && modes !== null ? modes.touchToWake : true

    // the screen reader's shortcut (Accessibility > Button shortcut), when a
    // screen reader exists in this image
    readonly property bool screenReaderShortcut: typeof screenReader !== "undefined" && screenReader !== null
                                                 && screenReader.shortcutEnabled === true

    // a clock in ms for the press windows (tests replace it)
    property var clock: function () { return Date.now() }

    // the process of the window the keys go to: the alert (a firing alarm),
    // else the application in front
    readonly property real frontPid: comp.alertShown && comp.alertWindow.window ? comp.alertWindow.window.processId
                                     : comp.topmostWindow && comp.topmostWindow.window ? comp.topmostWindow.window.processId : 0
    property Binding frontPidToClaims: Binding {
        target: typeof keyClaims !== "undefined" ? keyClaims : null
        property: "frontPid"
        value: keyRouter.frontPid
        when: typeof keyClaims !== "undefined" && keyClaims !== null
    }

    function setupActive() {
        return typeof firstRun !== "undefined" && firstRun !== null && firstRun.isFirstRun()
    }
    function claimed(key) {
        return typeof keyClaims !== "undefined" && keyClaims !== null && keyClaims.claimed(key)
    }
    function offer(key, count) {
        return typeof keyClaims !== "undefined" && keyClaims !== null && keyClaims.offer(key, count)
    }

    function context() {
        return {
            setup: setupActive(),
            callRinging: arbiter.callRinging,
            callShown: arbiter.callShown,
            claimSide: claimed("side"),
            claimCrown: claimed("crown"),
            alertShown: comp.alertShown,
            assistantShown: root.assistantShown,
            splash: launchSplash.active,
            appActive: comp.appActive,
            option: sideOption,
            shortcut: screenReaderShortcut,
            tiltToWake: tiltToWakeOn,
            touchToWake: touchToWakeOn,
            fromAmbient: comp.wakeFromAmbient
        }
    }

    /* ---- the side button ---------------------------------------------- */

    property var sideCounter: KeyMap.newCounter()
    // Recents was opened by the first press of this sequence
    property bool recentsByPress: false

    function sidePressed() {
        var c = context()
        var count = KeyMap.press(sideCounter, clock(), KeyMap.maxPresses(c.option, c.shortcut))
        var a = KeyMap.sidePress(c, count)
        if (a === "claim" && !offer("side", count)) {
            // the app let go of the key since: the global map
            c.claimSide = false
            a = KeyMap.sidePress(c, count)
        }
        runSide(a)
    }

    function runSide(a) {
        switch (a) {
        case "silenceCall":
            arbiter.silenceCall()
            break
        case "recents":
            // the assistant over the face goes first
            if (root.assistantShown)
                root.closeAssistant()
            recentsByPress = root.toggleRecents()
            break
        case "previous":
            // the second press: Recents the first one opened closes again
            if (recentsByPress)
                root.toggleRecents()
            recentsByPress = false
            comp.previousApp()
            break
        case "screenReader":
            if (recentsByPress)
                root.toggleRecents()
            recentsByPress = false
            if (typeof screenReader !== "undefined" && screenReader !== null)
                screenReader.toggle()
            break
        default:
            break
        }
    }

    property Connections assistantKeyConnection: Connections {
        target: typeof assistantKey !== "undefined" ? assistantKey : null
        // "side-key": a short press released with the display on
        function onPressed() { keyRouter.sidePressed() }
        function onLongPressed() {
            // mce: held 300 ms, from any display state (it turns the
            // display on first)
            var a = KeyMap.sideHold(keyRouter.context())
            if (a !== "assistant")
                return
            Haptics.longPress()
            root.openAssistant("")
        }
        function onOpenRequested(text) { root.openAssistant(text) }
    }

    /* ---- the crown ------------------------------------------------------ */

    property var crownCounter: KeyMap.newCounter()

    function crownPressed() {
        // the second press of a double (Wallet, out of reach) does nothing
        if (KeyMap.crownIsSecond(crownCounter, clock()))
            return
        var c = context()
        var a = KeyMap.crownPress(c)
        if (a === "claim" && !offer("crown", 1)) {
            c.claimCrown = false
            a = KeyMap.crownPress(c)
        }
        runCrown(a)
    }

    function runCrown(a) {
        switch (a) {
        case "silenceCall":
            arbiter.silenceCall()
            break
        case "closeAssistant":
            // the crown dismisses the assistant, wherever it was opened
            root.closeAssistant()
            break
        case "hideCall":
            // a call in progress goes on, only its view goes: Home
            arbiter.hideCall()
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.showWatchface()
            break
        case "leaveApp":
            root.closeTopmost()
            break
        case "home":
            if (homeLoader.item)
                homeLoader.item.crownPressed()
            break
        default:
            break
        }
    }

    // the press that woke the display: Home too, if the wake came from the
    // always-on display and tilt- and touch-to-wake are both on
    function crownWoke() {
        if (KeyMap.crownIsSecond(crownCounter, clock()))
            return
        if (KeyMap.crownWake(context()) !== "face")
            return
        if (comp.appActive)
            comp.leaveApp(comp.topmostWindow)
        if (homeLoader.item)
            homeLoader.item.showWatchface()
    }

    property Connections crownButtonConnection: Connections {
        target: typeof crownButton !== "undefined" ? crownButton : null
        ignoreUnknownSignals: true
        function onPressed() { keyRouter.crownPressed() }
        function onWakePressed() { keyRouter.crownWoke() }
    }
}
