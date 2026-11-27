/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// KeyRouter.qml and an application's full screen keyboard (CR-45): the crown asks the window in front to
// close its keyboard (LipstickCompositorWindow.closeKeyboard) and does nothing else; a window that does not
// send close_keyboard (no keyboard, or its last close went unanswered: closeKeyboard() false) lets the
// press go Home; the wake press from the always-on display does the same. compositor.qml's parts are
// stand-ins with its ids (arbiter, comp, root, launchSplash, homeLoader). MODE=st (the staged tree).
// R5 D-10: the router arms "Hey Assistant" (assistant/HotwordArm.qml) from the screen's state and opens the
// assistant on the phrase.
import QtQuick
import QtTest
import LauncherTest
import org.nemomobile.lipstick

Item {
    id: top
    width: 384
    height: 384

    QtObject {
        id: arbiter
        property bool callRinging: false
        property bool callShown: false
        property bool sosShown: false
        property bool powerMenuShown: false
        property bool errorShown: false
        property bool errorCancelable: false
        property bool systemDialogShown: false
        property bool thermalBlocking: false
        property bool headsUpShown: false
        property bool callInProgress: false
        property bool callOngoing: false
        // the find-my-watch page (D-29)
        property bool findWatchRinging: false
        property int findWatchStops: 0
        function stopFindWatch() { findWatchStops++; return true }
        property int headsUpClosed: 0
        property int silenced: 0
        function silenceCall() { silenced++ }
        property var sos: ({})
        function noteInput() {}
        function closeHeadsUp() { headsUpClosed++ }
    }
    QtObject {
        id: comp
        property bool appActive: true
        property var topmostWindow: null
        property bool alertShown: false
        property var alertWindow: ({})
        property bool wakeFromAmbient: false
        property bool displayIsOff: false
        property int left: 0
        function leaveApp(w) { left++ }
    }
    QtObject {
        id: root
        property bool assistantShown: false
        property bool chargingShown: false
        property int closed: 0
        property var opened: []
        function closeTopmost() { closed++ }
        function openAssistant(text, instant) { opened = opened.concat([{ text: text, instant: instant }]) }
    }
    QtObject { id: launchSplash; property bool active: false }
    // the launcher's CrownButton (mce's power_button_trigger): the palm cover comes as triggered("palm-cover")
    QtObject {
        id: crownButton
        signal pressed()
        signal triggered(string action)
    }
    QtObject {
        id: homeLoader
        property var item: QtObject {
            property int crown: 0
            property int face: 0
            function crownPressed() { crown++ }
            function showWatchface() { face++ }
        }
    }
    // the application window (LipstickCompositorWindow) with its keyboard
    QtObject {
        id: win
        property real processId: 4242
        property bool keyboardOpen: true
        // what closeKeyboard() answers: true = close_keyboard sent
        property bool answer: true
        property int closes: 0
        function closeKeyboard() { closes++; return answer }
    }
    QtObject { id: wrapper; property var window: win }

    Loader { id: kl; active: false; source: Qt.resolvedUrl("st/qml/compositor/KeyRouter.qml") }

    TestCase {
        name: "KeyRouterKeyboard"
        when: windowShown

        property var kr: null
        property real now: 1e6

        function initTestCase() {
            kl.active = true
            tryCompare(kl, "status", Loader.Ready, 30000)
            kr = kl.item
            kr.clock = function () { return now }
        }

        function init() {
            // presses far apart: no double press, no SOS count
            now += 10000
            comp.appActive = true
            comp.topmostWindow = wrapper
            comp.wakeFromAmbient = false
            win.keyboardOpen = true
            win.answer = true
            win.closes = 0
            root.closed = 0
            arbiter.headsUpShown = false
            arbiter.findWatchRinging = false
            arbiter.findWatchStops = 0
            homeLoader.item.crown = 0
            homeLoader.item.face = 0
        }

        // R5 D-10: armed only with a detector, the display fully on and the hold's rules met; the phrase opens
        // the assistant as the hold does (instant)
        function test_10_hotword() {
            var hw = kr.hotwordLoader.item
            verify(hw !== null)
            compare(hw.armed, false)             // image 72: no detector
            Backend.confSet("/org/asteroidos/assistant/hotword-supported", true)
            compare(hw.armed, true)
            comp.displayIsOff = true
            compare(hw.armed, false)
            comp.displayIsOff = false
            Lipstick.compositor.displayAmbient = true
            compare(hw.armed, false)
            Lipstick.compositor.displayAmbient = false
            compare(hw.armed, true)
            comp.alertShown = true               // a firing alarm (interruptions-09)
            compare(hw.armed, false)
            comp.alertShown = false
            arbiter.callShown = true
            compare(hw.armed, false)
            arbiter.callShown = false
            root.assistantShown = true
            compare(hw.armed, false)
            root.assistantShown = false
            // the hold's own switch is not the hotword's
            Backend.confSet("/org/asteroidos/assistant/press-and-hold", false)
            compare(hw.armed, true)
            root.opened = []
            compare(Backend.emitSignal("org.asteroidos.assistant", "org.asteroidos.assistant", "HotwordHeard", []), 1)
            compare(root.opened.length, 1)
            compare(root.opened[0].instant, true)
            compare(root.opened[0].text, "")
            Backend.confSet("/org/asteroidos/assistant/press-and-hold", true)
            Backend.confSet("/org/asteroidos/assistant/hotword-supported", false)
            tryCompare(hw, "armed", false)
        }

        function test_00_context_reads_the_window() {
            verify(kr.context().appKeyboardOpen)
            win.keyboardOpen = false
            verify(!kr.context().appKeyboardOpen)
            win.keyboardOpen = true
            comp.appActive = false
            verify(!kr.context().appKeyboardOpen)
        }

        function test_01_first_press_closes_the_keyboard_only() {
            kr.crownPressed()
            compare(win.closes, 1)
            compare(root.closed, 0)               // the app stays
            compare(homeLoader.item.crown, 0)
            // the client closed it: the next press goes Home
            win.keyboardOpen = false
            now += 10000
            kr.crownPressed()
            compare(win.closes, 1)
            compare(root.closed, 1)
        }

        function test_02_unanswered_close_goes_home() {
            // the window did not send close_keyboard (its last one went unanswered)
            win.answer = false
            kr.crownPressed()
            compare(win.closes, 1)
            compare(root.closed, 1)
        }

        function test_03_overlays_first() {
            arbiter.headsUpShown = true
            kr.crownPressed()
            compare(arbiter.headsUpClosed, 1)
            compare(win.closes, 0)
            compare(root.closed, 0)
        }

        function test_04_no_app_goes_home() {
            comp.appActive = false
            kr.crownPressed()
            compare(win.closes, 0)
            compare(homeLoader.item.crown, 1)
        }

        // R5 B-03: mce 0014's power_button_trigger("palm-cover"): mce's req_display_state_lpm (ambient,
        // or off without the always-on screen), or a ringing call silenced and the screen kept
        function lpmCalls() {
            return Backend.calls.filter(function (c) { return c.target === "com.nokia.mce"
                                                             && c.method === "com.nokia.mce.request.req_display_state_lpm" }).length
        }
        function test_06_palm_cover_sleeps() {
            Backend.clearCalls()
            arbiter.silenced = 0
            comp.left = 0
            crownButton.triggered("palm-cover")
            compare(lpmCalls(), 1)
            compare(arbiter.silenced, 0)
            // the app in front and its keyboard are not touched (the key never reaches them)
            compare(win.closes, 0)
            compare(root.closed, 0)
            compare(comp.left, 0)
            // another trigger is not the palm
            crownButton.triggered("asteroid-crown-other")
            compare(lpmCalls(), 1)
        }
        function test_07_palm_cover_silences_a_ringing_call() {
            Backend.clearCalls()
            arbiter.silenced = 0
            arbiter.callShown = true
            arbiter.callRinging = true
            crownButton.triggered("palm-cover")
            compare(arbiter.silenced, 1)
            compare(lpmCalls(), 0, "the screen stays")
            // silenced: the next palm keeps the screen too
            arbiter.callRinging = false
            crownButton.triggered("palm-cover")
            compare(arbiter.silenced, 1)
            compare(lpmCalls(), 0)
            // answered: a palm puts the screen to sleep
            arbiter.callOngoing = true
            crownButton.triggered("palm-cover")
            compare(lpmCalls(), 1)
            arbiter.callShown = false
            arbiter.callOngoing = false
        }

        // D-29: while the find-my-watch page rings, the crown (also the press that woke the screen) and the side
        // button stop the sound and do nothing else: the app's keyboard, the app and Home stay as they are
        function test_06b_find_my_watch() {
            var left0 = comp.left
            arbiter.findWatchRinging = true
            verify(kr.context().findWatchRinging)
            kr.crownPressed()
            compare(arbiter.findWatchStops, 1)
            compare(win.closes, 0)
            compare(root.closed, 0)
            compare(homeLoader.item.crown, 0)
            now += 10000
            kr.sidePressed()
            compare(arbiter.findWatchStops, 2)
            now += 10000
            comp.wakeFromAmbient = true
            kr.crownWoke()
            compare(arbiter.findWatchStops, 3)
            compare(comp.left, left0)
            compare(homeLoader.item.face, 0)
            comp.wakeFromAmbient = false
            // the page went: the crown closes the keyboard again
            arbiter.findWatchRinging = false
            verify(!kr.context().findWatchRinging)
            now += 10000
            kr.crownPressed()
            compare(arbiter.findWatchStops, 3)
            compare(win.closes, 1)
        }

        function test_05_wake_press() {
            comp.wakeFromAmbient = true
            kr.crownWoke()
            compare(win.closes, 1)
            compare(homeLoader.item.face, 0)      // the app and its keyboard close only
            compare(comp.left, 0)
            now += 10000
            win.answer = false
            kr.crownWoke()
            compare(win.closes, 2)
            compare(comp.left, 1)                 // to the face
            compare(homeLoader.item.face, 1)
        }
    }
}
