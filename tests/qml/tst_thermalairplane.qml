/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-08 (launcher half): the cooldown turns Airplane mode on and its end turns it off again, as stock's
// ThermalUiImpl startCooldownMode (airplane on, Theater on, touch block) and the cooldown's end (airplane and
// Theater off) (power-boot-warnings audit, CSUI modes/thermal). Airplane mode is connman's offline mode, as the
// quick panel's; Bluetooth that was on is switched on again 1.5 s later (stock's airplane mode keeps it on) unless
// Settings says Bluetooth goes off in airplane mode. Already on: left alone and left on. The warning alone does
// nothing. MOCKFIRST=1 MODE=st (the repo mocks: Connman, BluetoothStatus and dconf on Backend).
import QtQuick
import QtTest
import LauncherTest

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: modes; property bool theater: false }

    Loader { id: ld; anchors.fill: parent; source: Qt.resolvedUrl("st/qml/system/ThermalUi.qml") }

    TestCase {
        name: "ThermalAirplane"
        when: windowShown
        property var t: null

        function initTestCase() {
            tryCompare(ld, "status", Loader.Ready, 20000)
            t = ld.item
        }
        function init() {
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            wait(30)
            Backend.offline = false
            Backend.btPowered = true
            Backend.confSet("/org/asteroidos/settings/bluetooth-off-in-airplane", false)
            modes.theater = false
            t.phase = "none"
            t.theaterByUs = false
            t.airplaneByUs = false
            wait(30)
        }
        // connman's offline mode switches the radios off, Bluetooth included (the mock does not)
        function radiosOff() { Backend.btPowered = false }

        function test_01_the_cooldown_turns_airplane_mode_on_and_off() {
            Backend.confSet("/org/asteroidos/thermal/state", "cooldown")
            tryCompare(t, "phase", "cooling", 2000)
            compare(Backend.offline, true, "airplane mode on")
            verify(t.airplaneByUs)
            compare(modes.theater, true, "Theater too, as before")
            radiosOff()
            verify(t.restoreBluetooth.running, "Bluetooth comes back once")
            tryCompare(Backend, "btPowered", true, 3000)
            verify(!t.restoreBluetooth.running)
            // the end: off again
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(t, "phase", "none", 2000)
            compare(Backend.offline, false, "airplane mode off at the end")
            verify(!t.airplaneByUs)
            compare(modes.theater, false)
        }

        function test_02_airplane_mode_already_on_is_left_on() {
            Backend.offline = true
            wait(30)
            Backend.confSet("/org/asteroidos/thermal/state", "cooldown")
            tryCompare(t, "phase", "cooling", 2000)
            verify(!t.airplaneByUs)
            verify(!t.restoreBluetooth.running)
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(t, "phase", "none", 2000)
            compare(Backend.offline, true, "still on: it was the user's")
        }

        function test_03_bluetooth_off_in_airplane_mode_stays_off() {
            Backend.confSet("/org/asteroidos/settings/bluetooth-off-in-airplane", true)
            wait(30)
            Backend.confSet("/org/asteroidos/thermal/state", "cooldown")
            tryCompare(t, "phase", "cooling", 2000)
            compare(Backend.offline, true)
            radiosOff()
            verify(!t.restoreBluetooth.running)
            wait(1700)
            compare(Backend.btPowered, false)
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(t, "phase", "none", 2000)
        }

        function test_04_bluetooth_that_was_off_is_not_turned_on() {
            Backend.btPowered = false
            wait(30)
            Backend.confSet("/org/asteroidos/thermal/state", "cooldown")
            tryCompare(t, "phase", "cooling", 2000)
            verify(!t.restoreBluetooth.running)
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(t, "phase", "none", 2000)
            compare(Backend.offline, false)
        }

        function test_05_the_warning_alone_does_nothing() {
            Backend.confSet("/org/asteroidos/thermal/state", "warning")
            tryCompare(t, "phase", "warning", 2000)
            compare(Backend.offline, false)
            verify(!t.airplaneByUs)
            Backend.confSet("/org/asteroidos/thermal/state", "none")
            tryCompare(t, "phase", "none", 2000)
            compare(Backend.offline, false)
        }
    }
}
