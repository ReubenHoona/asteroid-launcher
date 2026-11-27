/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// KeyRouter.qml and an application's full screen keyboard (CR-45): the crown asks the window in front to
// close its keyboard (LipstickCompositorWindow.closeKeyboard) and does nothing else; a window that does not
// send close_keyboard (no keyboard, or its last close went unanswered: closeKeyboard() false) lets the
// press go Home; the wake press from the always-on display does the same. compositor.qml's parts are
// stand-ins with its ids (arbiter, comp, root, launchSplash, homeLoader). MODE=st (the staged tree).
import QtQuick
import QtTest

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
        // the find-my-watch page (D-29)
        property bool findWatchRinging: false
        property int findWatchStops: 0
        function stopFindWatch() { findWatchStops++; return true }
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
        property int left: 0
        function leaveApp(w) { left++ }
    }
    QtObject {
        id: root
        property bool assistantShown: false
        property bool chargingShown: false
        property int closed: 0
        function closeTopmost() { closed++ }
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
            arbiter.findWatchRinging = false
            arbiter.findWatchStops = 0
            homeLoader.item.crown = 0
            homeLoader.item.face = 0
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

        // D-29: while the find-my-watch page rings, the crown (also the press that woke the screen) and the side
        // button stop the sound and do nothing else: the app's keyboard, the app and Home stay as they are
        function test_06_find_my_watch() {
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
