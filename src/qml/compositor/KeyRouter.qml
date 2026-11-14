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
import "../system/system.js" as Sys

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
 * Wallet, out of reach); held 3 s (mce "asteroid-crown-long"): the power menu
 * (W2-launcher-power-system). Five presses, each within 500 ms of the one
 * before and over 600 ms in all, are Emergency SOS (Sys.sosPress), counted in
 * every state of the display and of the touch lock; the presses of that
 * burst do not run the Home action. With touch lock on the crown press, the
 * crown hold and the side button's press only show its exit view
 * (keymap.js touchLocked); mce's crown down and up edges drive its 2 s exit
 * ring.
 * A ringing call is silenced by either key. A firing alarm or timer: the
 * crown sends its window away to the face and the alarm keeps ringing (no
 * snooze, DECISIONS.md Q49); the side button is the presenter's, by a claim
 * ("side", KeyClaims, D-Bus org.asteroidos.launcher.Keys; dismiss is the
 * presenter's job, W2-app-alarms). An app in front may claim the keys too
 * (exercise); during setup the keys only wake.
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
            fromAmbient: comp.wakeFromAmbient,
            touchLocked: touchLocked(),
            sosShown: arbiter.sosShown,
            powerMenuShown: arbiter.powerMenuShown,
            errorDialogShown: arbiter.errorShown,
            errorDialogCancelable: arbiter.errorCancelable,
            systemDialogShown: arbiter.systemDialogShown,
            thermalBlocking: arbiter.thermalBlocking,
            headsUpShown: arbiter.headsUpShown,
            chargingShown: root.chargingShown,
            holdConsumed: false
        }
    }

    // touch lock (system/TouchLock.qml, a context id of compositor.qml)
    function touchLocked() {
        return typeof touchLock !== "undefined" && touchLock !== null && touchLock.locked === true
    }

    /* ---- the side button ---------------------------------------------- */

    property var sideCounter: KeyMap.newCounter()
    // Recents was opened by the first press of this sequence
    property bool recentsByPress: false

    function sidePressed() {
        arbiter.noteInput()
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
        case "touchLockHint":
            touchLock.showHint()
            break
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
            // no haptic here: the first one is the assistant's mic-open thud (stock
            // PhoneWindowManager gives none for the hold), and no transition
            root.openAssistant("", true)
        }
        function onOpenRequested(text) { root.openAssistant(text) }
    }

    /* ---- the crown ------------------------------------------------------ */

    property var crownCounter: KeyMap.newCounter()

    // Emergency SOS: five presses (Sys.sosPress)
    property var sosCounter: Sys.newSosCounter()
    // the touch lock was turned off by the ring while the crown was still down:
    // the rest of that hold (its release, the 3 s hold) is no press
    property real consumeHoldAt: -1
    property bool crownIsDown: false

    function holdConsumed() {
        if (consumeHoldAt < 0)
            return false
        var fresh = clock() - consumeHoldAt < 5000
        consumeHoldAt = -1
        return fresh
    }

    /* Count a press for the SOS gesture; true when it was the fifth. */
    function sosCount() {
        if (setupActive() || arbiter.sosShown)
            return false
        if (Sys.sosPress(sosCounter, clock()) !== "trigger")
            return false
        arbiter.sos.screenReaderExploring = typeof screenReader !== "undefined" && screenReader !== null
                                            && screenReader.touchExploring === true
        arbiter.triggerSos()
        return arbiter.sosShown
    }

    function crownPressed() {
        arbiter.noteInput()
        if (holdConsumed())
            return
        // the fifth press: Emergency SOS, nothing else
        if (sosCount())
            return
        // the presses of a burst do not toggle the app list five times
        if (sosCounter.count >= 3)
            return
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
        case "touchLockHint":
            touchLock.showHint()
            break
        case "closePowerMenu":
            arbiter.closePowerMenu()
            break
        case "closeErrorDialog":
            arbiter.closeError()
            break
        case "closeSystemDialog":
            arbiter.closeSystemDialog()
            break
        case "silenceCall":
            arbiter.silenceCall()
            break
        case "closeHeadsUp":
            // a new notification's view ends (alpha and scale to 0 in 300 ms); the
            // notification stays in the list, the face or the app is under it
            arbiter.closeHeadsUp()
            break
        case "closeCharging":
            // the charging screen (or its quality screen) closes, to the face, until the next screen off
            root.dismissCharging()
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.showWatchface()
            break
        case "closeAssistant":
            // the crown dismisses the assistant, wherever it was opened
            root.closeAssistant()
            break
        case "hideAlert":
            // the alarm keeps ringing, only its window goes: Home
            comp.hideAlert()
            if (comp.appActive)
                root.closeTopmost()
            else if (homeLoader.item)
                homeLoader.item.showWatchface()
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
        if (holdConsumed())
            return
        if (sosCount())
            return
        if (sosCounter.count >= 3)
            return
        if (KeyMap.crownIsSecond(crownCounter, clock()))
            return
        var wake = KeyMap.crownWake(context())
        if (wake === "touchLockHint") {
            touchLock.showHint()
            return
        }
        if (wake !== "face")
            return
        if (comp.appActive)
            comp.leaveApp(comp.topmostWindow)
        if (homeLoader.item)
            homeLoader.item.showWatchface()
    }

    /* The crown held 3000 ms (mce long_press_delay): the power menu, from any
     * display state, while the button is still down. */
    function crownLong() {
        var c = context()
        c.holdConsumed = holdConsumed()
        switch (KeyMap.crownLong(c)) {
        case "powerMenu":
            arbiter.showPowerMenu()
            break
        case "touchLockExit":
            // mce without the crown edge triggers: the 3 s hold is the exit
            touchLock.unlock()
            break
        default:
            break
        }
    }

    property Connections crownButtonConnection: Connections {
        target: typeof crownButton !== "undefined" ? crownButton : null
        ignoreUnknownSignals: true
        function onPressed() { keyRouter.crownPressed() }
        function onWakePressed() { keyRouter.crownWoke() }
        function onLongPressed() { keyRouter.crownLong() }
        // the edges (only with the crown trigger patch of mce): touch lock's exit ring
        function onPressStarted() {
            keyRouter.crownIsDown = true
            if (keyRouter.touchLocked())
                touchLock.crownDown()
        }
        function onReleased() {
            keyRouter.crownIsDown = false
            if (typeof touchLock !== "undefined" && touchLock !== null)
                touchLock.crownUp()
        }
        // mce's chord of the crown and the side button within 150 ms
        function onScreenshotRequested() { keyRouter.screenshot() }
    }

    // Settings > Buttons > Chord press > Screenshot (default on, stock screenshot_enabled)
    property QtObject screenshotSetting: ConfigurationValue {
        key: "/org/asteroidos/settings/screenshot-enabled"
        defaultValue: true
    }
    function screenshot() {
        if (setupActive())
            return
        if (screenshotSetting.value === false || screenshotSetting.value === "false")
            return
        if (typeof screenshotOverlay !== "undefined" && screenshotOverlay !== null)
            screenshotOverlay.capture()
    }

    // the ring completed with the crown still down
    property Connections touchLockConnection: Connections {
        target: typeof touchLock !== "undefined" ? touchLock : null
        ignoreUnknownSignals: true
        function onExited() {
            if (keyRouter.crownIsDown)
                keyRouter.consumeHoldAt = keyRouter.clock()
        }
    }
}
