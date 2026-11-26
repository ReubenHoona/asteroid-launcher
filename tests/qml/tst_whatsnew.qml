/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// What's new after an update (src/qml/firstrun/WhatsNew.qml, setup-wizard-15, CR-42) on the repo's dconf
// double: eos-update's three keys (whatsnew-version, -notes, -pending). Pending true with notes shows the
// splash once (pending goes false when it shows), false never, no notes never; it waits for the screen,
// for what must not be covered and for setup; the splash, the pages (Next, Back, Done) and the crown's
// close. MODE=st (the staged tree).
import QtQuick
import QtTest
import LauncherTest
import "st/qml/firstrun/whatsnew.js" as WN

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: firstRun
        property bool running: false
        function isFirstRun() { return running }
    }

    Loader { id: wl; active: false; anchors.fill: parent; source: Qt.resolvedUrl("st/qml/firstrun/WhatsNew.qml") }

    TestCase {
        name: "WhatsNew"
        when: windowShown

        readonly property string kv: "/org/asteroidos/eos-update/whatsnew-version"
        readonly property string kn: "/org/asteroidos/eos-update/whatsnew-notes"
        readonly property string kp: "/org/asteroidos/eos-update/whatsnew-pending"
        property var w: null

        function findChild2(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var lists = [item.children, item.contentItem ? item.contentItem.children : null]
            for (var k = 0; k < lists.length; k++) {
                var d = lists[k]
                for (var i = 0; d && i < d.length; i++) {
                    var r = findChild2(d[i], name)
                    if (r)
                        return r
                }
            }
            return null
        }
        function load(pending, notes) {
            wl.active = false
            Backend.reset()
            firstRun.running = false
            Backend.confSet(kv, "63")
            if (notes !== undefined)
                Backend.confSet(kn, notes)
            if (pending !== undefined)
                Backend.confSet(kp, pending)
            wl.active = true
            tryCompare(wl, "status", Loader.Ready, 20000)
            w = wl.item
            return w
        }
        function cleanup() {
            wl.active = false
        }

        function test_00_rules() {
            var p = WN.pages("Faster: Apps open sooner.| |Battery: Longer days|Just text")
            compare(p.length, 3)
            compare(p[0].headline, "Faster")
            compare(p[0].text, "Apps open sooner.")
            compare(p[2].headline, "")
            compare(p[2].text, "Just text")
            verify(WN.due(true, "A: b"))
            verify(WN.due("true", "A: b"))
            verify(!WN.due(false, "A: b"))
            verify(!WN.due(true, ""))
            verify(!WN.due(true, " | "))
            verify(!WN.due(undefined, "A: b"))
        }

        function test_01_pending_shows_once() {
            load(true, "Faster: Apps open sooner.|Battery: Longer days")
            compare(w.shown, true)
            compare(w.visible, true)
            compare(w.step, -1)
            // the splash, stock's title, Next
            compare(findChild2(w, "whatsNewSplash").visible, true)
            compare(findChild2(w, "whatsNewSplashTitle").text, "Your watch just got better!")
            compare(findChild2(w, "whatsNewSplashNext").text, "Next")
            // shown: not again
            compare(Backend.confGet(kp), false)
            // the pages: Next, then Back from the second, Done on the last
            w.next()
            compare(w.step, 0)
            compare(findChild2(w, "whatsNewSplash").visible, false)
            compare(findChild2(w, "whatsNewHeadline").text, "Faster")
            compare(findChild2(w, "whatsNewText").text, "Apps open sooner.")
            compare(findChild2(w, "whatsNewNext").text, "Next")
            compare(findChild2(w, "whatsNewBack").visible, false)
            w.next()
            compare(w.step, 1)
            compare(findChild2(w, "whatsNewHeadline").text, "Battery")
            compare(findChild2(w, "whatsNewNext").text, "Done")
            compare(findChild2(w, "whatsNewBack").visible, true)
            waitForRendering(w)
            mouseClick(findChild2(w, "whatsNewBack"))
            compare(w.step, 0)
            w.next()
            waitForRendering(w)
            mouseClick(findChild2(w, "whatsNewNext"))
            compare(w.shown, false)
            compare(w.visible, false)
            // a new launcher (a restart): pending is false, nothing
            wl.active = false
            wl.active = true
            tryCompare(wl, "status", Loader.Ready, 20000)
            compare(wl.item.shown, false)
        }

        function test_02_not_pending_or_no_notes_never() {
            load(false, "Faster: Apps open sooner.")
            compare(w.shown, false)
            load(undefined, "Faster: Apps open sooner.")
            compare(w.shown, false)
            load(true, "")
            compare(w.shown, false)
            load(true, undefined)
            compare(w.shown, false)
            compare(Backend.confGet(kp), true, "pending kept: nothing was shown")
            // the notes arrive (eos-update writes them after pending): it shows
            Backend.confSet(kn, "Faster: Apps open sooner.")
            compare(w.shown, true)
            compare(Backend.confGet(kp), false)
        }

        function test_03_waits_for_the_screen_the_surfaces_and_setup() {
            wl.active = false
            Backend.reset()
            Backend.confSet(kn, "Faster: Apps open sooner.")
            Backend.confSet(kp, true)
            firstRun.running = false
            wl.active = true
            tryCompare(wl, "status", Loader.Ready, 20000)
            w = wl.item
            // (shown at once: the defaults are display on, nothing blocking)
            compare(w.shown, true)
            w.close()
            // a new update while the display is off: at the next screen on
            Backend.confSet(kp, true)
            compare(w.shown, true, "display on: at once")
            w.close()
            w.displayOn = false
            Backend.confSet(kp, true)
            compare(w.shown, false)
            compare(Backend.confGet(kp), true)
            w.displayOn = true
            compare(w.shown, true)
            w.close()
            // a call or a firing alarm (blocked): after it
            w.blocked = true
            Backend.confSet(kp, true)
            compare(w.shown, false)
            w.blocked = false
            compare(w.shown, true)
            w.close()
            // setup runs: not before it ended and the screen came on again
            firstRun.running = true
            w.displayOn = false
            Backend.confSet(kp, true)
            w.displayOn = true
            compare(w.shown, false)
            firstRun.running = false
            w.displayOn = false
            w.displayOn = true
            compare(w.shown, true)
        }

        function test_04_render() {
            load(true, "Faster apps: Apps open sooner and the list scrolls more smoothly.|Battery: Longer days")
            waitForRendering(w)
            var img = grabImage(w)
            img.save("/tmp/r2l-shots/l8-splash.png")
            w.next()
            waitForRendering(w)
            grabImage(w).save("/tmp/r2l-shots/l8-page1.png")
            w.next()
            waitForRendering(w)
            grabImage(w).save("/tmp/r2l-shots/l8-page2.png")
            // the title within the splash's 12 % sides
            var t = findChild2(w, "whatsNewSplashTitle")
            verify(t.x >= Math.round(384 * 0.12) - 1)
        }
    }
}
