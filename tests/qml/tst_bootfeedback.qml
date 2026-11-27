/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-09: the boot-complete feedback (BootFeedback.qml in HomeOverlays), as stock's BootCompletedFeedbackProvider:
// when the boot screen has gone, the launcher asks once whether it is due (firstRun.bootFeedbackDue(): once per boot,
// setup done, not an update's trial boot) and then wakes the screen (mce req_display_state_on) and plays ngfd's
// boot_done (the event name only: nothing is played here). MODE=st (the repo mocks record the bus and ngfd).
import QtQuick
import QtTest
import LauncherTest
import "st/qml"

Item {
    id: top
    width: 384
    height: 384

    QtObject {
        id: firstRun
        property bool answer: true
        property int asked: 0
        function bootFeedbackDue() { asked++; return answer }
    }

    Component { id: fbComp; BootFeedback { } }

    TestCase {
        name: "BootFeedback"
        when: windowShown

        function init() {
            Backend.reset()
            firstRun.answer = true
            firstRun.asked = 0
        }
        function woke() {
            return Backend.calls.filter(function (c) { return c.target === "com.nokia.mce"
                                                             && c.method === "com.nokia.mce.request.req_display_state_on" }).length
        }
        function played() {
            return Backend.calls.filter(function (c) { return c.target === "ngfd" && c.method === "boot_done" }).length
        }

        function test_01_after_the_boot_screen() {
            var fb = createTemporaryObject(fbComp, top, { splashDone: false })
            wait(50)
            compare(firstRun.asked, 0, "not while the boot screen shows")
            compare(woke(), 0)
            compare(played(), 0)
            fb.splashDone = true
            compare(firstRun.asked, 1)
            compare(woke(), 1, "the screen woken")
            compare(played(), 1, "boot_done")
            verify(fb.played)
            // asked once per launcher start
            fb.splashDone = false
            fb.splashDone = true
            compare(firstRun.asked, 1)
            compare(played(), 1)
        }

        function test_02_not_due() {
            firstRun.answer = false
            var fb = createTemporaryObject(fbComp, top, { splashDone: true })
            wait(50)
            compare(firstRun.asked, 1)
            compare(woke(), 0)
            compare(played(), 0)
            verify(!fb.played)
        }

        function test_03_the_event_name() {
            var fb = createTemporaryObject(fbComp, top, { splashDone: false })
            compare(findChild(fb, "bootDoneFeedback").event, "boot_done")
        }
    }
}
