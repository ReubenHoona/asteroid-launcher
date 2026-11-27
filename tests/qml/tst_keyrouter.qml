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
        property int headsUpClosed: 0
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
