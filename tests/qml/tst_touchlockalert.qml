/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// AUDIT-72 D-19: a firing alarm or timer ends touch lock, as stock DeskClock's END_WET_MODE when one starts
// firing (hrz.java:389, hsp.java:543, htg.java:53). system/TouchLock.qml: alertShown becoming true calls
// end(), which turns the lock off (the dconf key back to false, exited()) without the manual exit's tone
// (stock plays the water ejection tone only after a manual exit, TouchLockKeyInterceptorClient.java:296-303);
// the crown hold's exit still plays it; the lock is not turned on by the alert going; compositor.qml binds
// alertShown to arbiter.alertShown and keeps the SOS unlock. MODE=st (the staged tree).
import QtQuick
import QtTest
import LauncherTest

Item {
    id: top
    width: 384
    height: 384

    // the launcher's context object the lock's exit text reads
    QtObject { id: localeManager; property string changesObserver: "" }
    property int under: 0
    MouseArea { anchors.fill: parent; onClicked: top.under++ }
    Loader { id: ld; anchors.fill: parent; z: 10; source: Qt.resolvedUrl("st/qml/system/TouchLock.qml") }

    TestCase {
        id: tc
        name: "TouchLockAlert"
        when: windowShown

        readonly property string key: "/org/asteroidos/settings/touch-lock"
        property var lock: null
        property int tones: 0
        property int exits: 0

        function initTestCase() {
            tryCompare(ld, "status", Loader.Ready, 20000)
            lock = ld.item
            verify(lock !== null)
            lock.exitTone = function () { tc.tones++ }
            lock.exited.connect(function () { tc.exits++ })
        }
        function init() {
            lock.alertShown = false
            if (lock.locked)
                lock.end()
            tones = 0
            exits = 0
            top.under = 0
        }

        function test_01_alert_ends_the_lock() {
            lock.lock()
            tryCompare(lock, "locked", true)
            compare(Backend.confGet(key), true)
            // the lock takes every touch
            mouseClick(top, 192, 192)
            compare(top.under, 0)
            lock.alertShown = true
            compare(lock.locked, false)
            compare(Backend.confGet(key), false)
            compare(exits, 1)
            compare(tones, 0, "no tone: not a manual exit")
            // Stop and Snooze take taps again
            mouseClick(top, 192, 300)
            compare(top.under, 1)
        }

        function test_02_alert_with_the_lock_off_changes_nothing() {
            lock.alertShown = true
            compare(lock.locked, false)
            compare(exits, 0)
            compare(tones, 0)
            lock.alertShown = false
            compare(lock.locked, false)
        }

        function test_03_alert_going_does_not_lock() {
            lock.lock()
            lock.alertShown = true
            compare(lock.locked, false)
            lock.alertShown = false
            compare(lock.locked, false, "the lock stays off when the alarm window goes")
            compare(Backend.confGet(key), false)
        }

        function test_04_lock_turned_on_while_the_alert_rings() {
            // the alert is up (it was sent to the face by the crown and is back, or the lock came from the
            // quick settings over it): the lock goes on; the alert coming to the front again ends it
            lock.alertShown = true
            lock.lock()
            compare(lock.locked, true)
            lock.alertShown = false
            compare(lock.locked, true)
            lock.alertShown = true
            compare(lock.locked, false)
            compare(tones, 0)
        }

        function test_05_manual_exit_keeps_its_tone() {
            lock.lock()
            lock.unlock()
            compare(lock.locked, false)
            compare(tones, 1, "the crown hold's exit plays the tone, as before")
            compare(exits, 1)
        }

        function test_06_compositor_binds_the_alert() {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", Qt.resolvedUrl("st/qml/compositor.qml"), false)
            xhr.send()
            var src = xhr.responseText
            verify(src.length > 1000, "compositor.qml read")
            var at = src.indexOf("TouchLock {")
            verify(at > 0)
            var block = src.substring(at, src.indexOf("\n    }", at))
            verify(block.indexOf("alertShown: arbiter.alertShown") > 0, "the lock follows the alert window")
            // the SOS path is untouched: it still unlocks
            var sos = src.indexOf("function onSosTriggered()")
            verify(sos > 0)
            verify(src.substring(sos, sos + 200).indexOf("touchLock.unlock()") > 0)
        }
    }
}
