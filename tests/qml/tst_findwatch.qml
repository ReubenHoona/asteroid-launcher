/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// D-29 (apps-misc-14): the find-my-watch page (src/qml/notifications/FindWatch.qml). The phone's find device comes as
// asteroid-btsyncd's card (invented here in the hints btsyncd posts: x-asteroid-find-watch, the phone action found,
// x-nemo-feedback find_my_watch); the page shows over everything with Find Hub's words (com.google.android.apps.adm
// ringing "Playing sound…", stop_ring "Stop sound", ring_device_message_1 / spot_how_to_stop_ringing), turns the
// display on (mce, not in Theater), and Stop sound or a swipe away invokes the card's found action once; the phone's
// removal of the card takes the page away; calls, other cards and an alert older than ten minutes (restored by
// lipstick at start) do not ring. The page plays nothing itself: the ring is the card's feedback, whose event name
// is only checked here, never played (the quiet rule). Shots in /tmp/r5c-shots. MODE=st (the staged tree).
import QtQuick
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick
import LauncherTest

Item {
    id: testRoot
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: modes; property bool theater: false }

    // the wall clock the page reads (ms), moved by the tests
    property real clockMs: new Date(2026, 10, 25, 10, 5, 0).getTime()

    Rectangle { anchors.fill: parent; color: "black" }
    // something under the page that must not take a touch while it rings
    MouseArea { id: under; anchors.fill: parent; property int taps: 0; onClicked: taps++ }
    Loader { id: loader; anchors.fill: parent; active: false; source: Qt.resolvedUrl("st/qml/FindWatch.qml") }
    // the round edge of the watch
    Canvas {
        anchors.fill: parent
        z: 100
        onPaint: {
            var ctx = getContext("2d")
            ctx.fillStyle = "#000000"
            ctx.beginPath()
            ctx.rect(0, 0, width, height)
            ctx.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI, true)
            ctx.fill()
        }
    }

    Component {
        id: notificationComp
        QtObject {
            property int replacesId: 41
            property string appName: "Gadgetbridge"
            property string summary: "Gadgetbridge"
            property string body: ""
            property var hints: ({})
            property date timestamp: new Date(testRoot.clockMs)
            property var invoked: []
            property int removes: 0
            function actionInvoked(key) { var l = invoked.slice(); l.push(key); invoked = l }
            function removeRequested() { removes++ }
        }
    }

    TestCase {
        name: "FindWatch"
        when: windowShown

        property var fw: null

        function findHints() {
            // what btsyncd posts for Gadgetbridge's onFindDevice(true) (notificationservice.cpp post())
            return { "x-asteroid-find-watch": true, "x-asteroid-phone-actions": "found",
                     "x-nemo-feedback": "find_my_watch", "urgency": 3 }
        }
        function note(id, hints, ageMs) {
            return notificationComp.createObject(testRoot, { replacesId: id, hints: hints,
                                                             timestamp: new Date(testRoot.clockMs - (ageMs || 0)) })
        }
        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var lists = [item.children, item.contentItem ? item.contentItem.children : null]
            for (var k = 0; k < lists.length; k++) {
                var d = lists[k]
                for (var i = 0; d && i < d.length; i++) {
                    var r = find(d[i], name)
                    if (r)
                        return r
                }
            }
            return null
        }
        function mceCalls(method) {
            return Backend.calls.filter(function (c) { return c.method === "com.nokia.mce.request." + method })
        }
        function ngfCalls() {
            return Backend.calls.filter(function (c) { return c.target === "ngfd" })
        }
        function shot(name) {
            testRoot.grabToImage(function (r) { r.saveToFile("/tmp/r5c-shots/" + name + ".png") })
            wait(120)
        }

        function init() {
            Backend.reset()
            modes.theater = false
            under.taps = 0
            testRoot.clockMs = new Date(2026, 10, 25, 10, 5, 0).getTime()
            loader.active = true
            fw = loader.item
            verify(fw !== null)
            fw.clock = function () { return testRoot.clockMs }
            fw.model.populated = true
        }
        function cleanup() {
            loader.active = false
            fw = null
            wait(0)
        }

        function test_01_rules() {
            verify(fw.isFindAlert(note(1, findHints())))
            // an older btsyncd: no hint, the phone action found alone
            verify(fw.isFindAlert(note(2, { "x-asteroid-phone-actions": "found" })))
            verify(fw.isFindAlert(note(3, { "x-asteroid-find-watch": "true" })))
            // a call, a message, a card that has found among a call's actions, no hints: not the alert
            verify(!fw.isFindAlert(note(4, { "x-asteroid-phone-actions": "answer,reject" })))
            verify(!fw.isFindAlert(note(5, { "x-asteroid-phone-actions": "reply,open,mute" })))
            verify(!fw.isFindAlert(note(6, { "x-asteroid-phone-actions": "found,answer" })))
            verify(!fw.isFindAlert(note(7, {})))
            verify(!fw.isFindAlert(null))
            // ten minutes: a fresh one rings, an older one (restored at start) does not
            compare(fw.maxAgeMs, 600000)
            verify(fw.isRinging(note(8, findHints(), 599000)))
            verify(!fw.isRinging(note(9, findHints(), 601000)))
        }

        function test_02_arrival_shows_the_page() {
            verify(!fw.shown)
            var n = note(41, findHints())
            fw.model.add(n)
            verify(fw.shown)
            compare(fw.alert, n)
            tryCompare(fw.dialog, "alpha", 1)
            compare(find(fw, "findWatchTitle").text, "Playing sound…")
            compare(find(fw, "findWatchNote").text, "To stop the sound, you can also press a button on your watch.")
            compare(fw.stopButton.iconName, "ms-volume_off")
            compare(fw.stopButton.Accessible.name, "Stop sound")
            // the words end above the button (nothing under it at rest)
            var noteLabel = find(fw, "findWatchNote")
            var bottom = noteLabel.mapToItem(testRoot, 0, noteLabel.height).y
            verify(bottom <= fw.stopButton.mapToItem(testRoot, 0, 0).y + fw.stopButton.height - fw.stopButton.preferredHeight,
                   "note bottom " + bottom)
            compare(find(fw, "findWatchIcon").name, "ms-volume_up")
            // the display comes on for it (mce's notification request, renewed while it rings)
            var on = mceCalls("notification_begin_req")
            compare(on.length, 1)
            compare(on[0].args[0], "asteroid-find-watch")
            compare(on[0].args[1], 30000)
            // the page plays nothing itself; the ring is the card's feedback event (btsyncd's PostPlan)
            compare(ngfCalls().length, 0)
            compare(n.hints["x-nemo-feedback"], "find_my_watch")
            // nothing under the page takes the touch
            mouseClick(testRoot, 192, 120)
            compare(under.taps, 0)
            shot("findwatch-ringing")
        }

        function test_03_stop_sound() {
            var n = note(41, findHints())
            fw.model.add(n)
            tryCompare(fw.dialog, "alpha", 1)
            mouseClick(fw.stopButton)
            compare(n.invoked, ["found"])
            verify(!fw.shown)
            compare(mceCalls("notification_end_req").length, 1)
            // the same card again (lipstick has removed it; a late update): not shown again
            fw.model.add(n)
            verify(!fw.shown)
            // stop() with nothing shown does nothing
            verify(!fw.stop())
            compare(n.invoked, ["found"])
            compare(ngfCalls().length, 0)
        }

        function test_04_phone_stops_it() {
            var n = note(41, findHints())
            fw.model.add(n)
            verify(fw.shown)
            // Gadgetbridge's onFindDevice(false): btsyncd closes the card
            fw.model.remove(n)
            verify(!fw.shown)
            compare(n.invoked, [])
            tryCompare(fw.dialog, "shown", false)
        }

        function test_05_swipe_away_stops_it() {
            var n = note(41, findHints())
            fw.model.add(n)
            tryCompare(fw.dialog, "alpha", 1)
            fw.dialog.dismissRequested()
            compare(n.invoked, ["found"])
            verify(!fw.shown)
        }

        function test_06_not_for_other_cards() {
            fw.model.add(note(51, { "x-asteroid-phone-actions": "answer,reject", "x-nemo-feedback": "ringtone" }))
            fw.model.add(note(52, { "x-asteroid-phone-actions": "reply,open" }))
            fw.model.add(note(53, { "x-asteroid-category": "health-alert" }))
            verify(!fw.shown)
            compare(mceCalls("notification_begin_req").length, 0)
        }

        function test_07_restored_at_start() {
            // lipstick restores its cards before populated: an old alert does not ring, a fresh one does
            loader.active = false
            wait(0)
            loader.active = true
            fw = loader.item
            fw.clock = function () { return testRoot.clockMs }
            var old = note(61, findHints(), 3600000)
            fw.model.items = [old]
            fw.model.populated = true
            verify(!fw.shown)
            fw.model.populated = false
            var fresh = note(62, findHints(), 20000)
            fw.model.items = [fresh, old]
            fw.model.populated = true
            verify(fw.shown)
            compare(fw.alert, fresh)
        }

        function test_08_theater_keeps_the_screen_off() {
            modes.theater = true
            var n = note(41, findHints())
            fw.model.add(n)
            verify(fw.shown)
            compare(mceCalls("notification_begin_req").length, 0)
            // the buttons still stop it (keymap.js), here through the page's stop()
            verify(fw.stop())
            compare(n.invoked, ["found"])
        }

        function test_09_gives_up_the_display() {
            // a phone that never ends the ring: the page goes after maxAgeMs, the card stays (its own button)
            fw.maxAgeMs = 300
            var n = note(41, findHints())
            fw.model.add(n)
            verify(fw.shown)
            tryCompare(fw, "shown", false, 3000)
            compare(n.invoked, [])
            compare(mceCalls("notification_end_req").length, 1)
            // and does not come back for that card
            fw.model.add(n)
            verify(!fw.shown)
        }

        function test_10_two_alerts() {
            var a = note(71, findHints())
            var b = note(72, findHints())
            fw.model.add(a)
            fw.model.add(b)
            // the newest is shown; stopping it shows the other one still ringing
            compare(fw.alert, b)
            verify(fw.stop())
            compare(b.invoked, ["found"])
            compare(fw.alert, a)
            verify(fw.stop())
            compare(a.invoked, ["found"])
            verify(!fw.shown)
        }
    }
}
