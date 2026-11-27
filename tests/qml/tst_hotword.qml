/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 D-10: "Hey Assistant" (src/qml/assistant/HotwordArm.qml) on the repo mocks: the daemon's Hotword(b) is asked
// only on a change, only while the watch has a detector (assistant/hotword-supported), the setting and the
// Assistant are on, the display is fully on and nothing blocks it; HotwordHeard (taken only while armed) gives
// heard() once and the daemon is asked again when it is wanted again. Image 72 (no detector): never asked.
// MODE=st (the staged tree).
import QtQuick
import QtTest
import LauncherTest

Item {
    id: top
    width: 384
    height: 384

    Loader { id: hl; active: false; source: Qt.resolvedUrl("st/qml/assistant/HotwordArm.qml") }
    property int heardCount: 0
    Connections { target: hl.item; function onHeard() { top.heardCount++ } }

    TestCase {
        name: "Hotword"
        when: windowShown

        readonly property string svc: "org.asteroidos.assistant"
        property var hw: null

        // the Hotword calls so far: [true, false, ...]
        function asked() {
            var l = []
            for (var i = 0; i < Backend.calls.length; i++)
                if (Backend.calls[i].target === svc && Backend.calls[i].method === svc + ".Hotword")
                    l.push(Backend.calls[i].args[0])
            return l
        }
        function hear() { return Backend.emitSignal(svc, svc, "HotwordHeard", []) }
        function load(supported) {
            hl.active = false
            Backend.reset()
            if (supported !== undefined)
                Backend.confSet("/org/asteroidos/assistant/hotword-supported", supported)
            Backend.clearCalls()
            heardCount = 0
            hl.active = true
            tryCompare(hl, "status", Loader.Ready, 30000)
            hw = hl.item
        }

        function test_00_no_detector_never_asks() {
            load()
            compare(hw.supported, false)
            hw.awake = true
            hw.blocked = false
            hw.awake = false
            hw.awake = true
            compare(asked(), [])
            compare(hw.armed, false)
            compare(hear(), 0)
            compare(heardCount, 0)
        }

        function test_01_armed_only_while_fully_awake_and_free() {
            load(true)
            compare(asked(), [])                 // blocked and asleep at the start
            hw.blocked = false
            compare(asked(), [])                 // the display is not on
            hw.awake = true
            compare(asked(), [true])
            compare(hw.armed, true)
            hw.awake = true                      // no change, no call
            compare(asked(), [true])
            hw.awake = false                     // dimmed or off
            compare(asked(), [true, false])
            hw.awake = true
            hw.blocked = true                    // the assistant, a call, the lock screen ...
            compare(asked(), [true, false, true, false])
        }

        function test_02_settings_off() {
            load(true)
            hw.awake = true
            hw.blocked = false
            compare(asked(), [true])
            Backend.confSet("/org/asteroidos/assistant/hotword", false)
            compare(asked(), [true, false])
            Backend.confSet("/org/asteroidos/assistant/hotword", true)
            compare(asked(), [true, false, true])
            Backend.confSet("/org/asteroidos/assistant/enabled", false)
            compare(asked(), [true, false, true, false])
            Backend.confSet("/org/asteroidos/assistant/enabled", true)
            Backend.confSet("/org/asteroidos/assistant/hotword-supported", false)
            compare(asked(), [true, false, true, false, true, false])
        }

        // a daemon that cannot listen (no detector installed) answers false: not told to stop, asked again at
        // the next wake only
        function test_04_daemon_cannot_listen() {
            load(true)
            Backend.replies[svc + ".Hotword"] = false
            hw.blocked = false
            hw.awake = true
            compare(asked(), [true])
            compare(hw.armed, false)
            hw.awake = false
            compare(asked(), [true])
            hw.awake = true
            compare(asked(), [true, true])
            // the daemon unreachable: the same
            Backend.errors = { "org.asteroidos.assistant.Hotword": "org.freedesktop.DBus.Error.ServiceUnknown" }
            hw.awake = false
            hw.awake = true
            compare(asked(), [true, true, true])
            compare(hw.armed, false)
        }

        function test_03_heard_once_then_asked_again_when_wanted() {
            load(true)
            hw.awake = true
            hw.blocked = false
            compare(asked(), [true])
            compare(hear(), 1)
            compare(heardCount, 1)
            compare(hw.armed, false)
            // the assistant opened (blocked): not asked again; a second signal is not taken
            hw.blocked = true
            compare(hear(), 0)
            compare(heardCount, 1)
            wait(50)
            compare(asked(), [true])
            // it closed: listening again
            hw.blocked = false
            compare(asked(), [true, true])
            // nothing opened after the phrase (blocked did not change): asked again at once
            compare(hear(), 1)
            tryVerify(function () { return asked().length === 3 }, 1000)
            compare(asked(), [true, true, true])
            compare(heardCount, 2)
        }
    }
}
