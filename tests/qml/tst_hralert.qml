/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// M4 WO-12: the heart rate alert screen (src/qml/system/HrAlert.qml), as stock's HeartRateAlertInfoActivity (Fitbit
// 4.01.1: HrAlertService.java:60-110, aaog.java:905-990, aaut.java, zqb.java:225-280, aabb.java:557-567) on the
// repo's doubles: the notification server hands over asteroid-sensorlogd's alert (a presenter double with
// fullScreenRequested, as lipstick's for x-asteroid-category health-alert), invented alerts in the hints sensorlogd
// posts (x-asteroid-health: hr-high 128 bpm over 120 from 9:40 to 9:50; hr-low), a fixed wall clock. The screen: the
// heart with a plus or a minus, the title, the bpm, the detail with the watch's times, the edge button that closes
// it; the arrival turns the display on (mce), not in Theater; it closes itself a minute after the arrival or the
// last scroll, only while the display is on, never when opened from the card; the stream's card opens it again
// (Desktop.hrAlert); anything that is not an alert is left alone. No sound or vibration here: the notification's
// feedback is lipstick's (tst_eoscategory). Shots in /tmp/m4wo12-shots. MODE=st (the staged tree).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml/system/hralert.js" as HA
import "st/qml/desktop.js" as Desktop

Item {
    id: testRoot
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: modes; property bool theater: false }
    // lipstick's preview presenter: its signal for a full screen category
    QtObject {
        id: presenterDouble
        signal fullScreenRequested(var notification)
    }

    // the wall clock the screen reads (ms), moved by the tests
    property real clockMs: new Date(2026, 10, 25, 10, 5, 0).getTime()

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: loader; anchors.fill: parent; active: false; source: Qt.resolvedUrl("st/qml/system/HrAlert.qml") }

    function alertHints(type, bpm, threshold) {
        return {
            "x-asteroid-category": "health-alert",
            "x-asteroid-health": JSON.stringify({ type: type, bpm: bpm, threshold: threshold,
                                                  start: new Date(2026, 10, 25, 9, 40).getTime(),
                                                  end: new Date(2026, 10, 25, 9, 50).getTime() }),
            "x-asteroid-detail": "sensorlogd's own words",
            "urgency": 2
        }
    }
    Component {
        id: notificationComp
        QtObject {
            property int replacesId: 7
            property string appName: "Health"
            property string summary: "High heart rate"
            property string body: "128 bpm"
            property var hints: ({})
        }
    }

    TestCase {
        name: "HrAlert"
        when: windowShown

        property var hr: null

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
        function note(type, bpm, threshold) {
            return notificationComp.createObject(testRoot, { hints: alertHints(type, bpm, threshold) })
        }
        function init() {
            Backend.reset()
            modes.theater = false
            testRoot.clockMs = new Date(2026, 10, 25, 10, 5, 0).getTime()
            loader.active = true
            hr = loader.item
            verify(hr !== null)
            hr.presenter = presenterDouble
            hr.clock = function () { return testRoot.clockMs }
            hr.displayOn = true
        }
        function cleanup() {
            loader.active = false
            hr = null
            wait(0)
        }
        function shot(name) {
            testRoot.grabToImage(function (r) { r.saveToFile("/tmp/m4wo12-shots/" + name + ".png") })
            wait(80)
        }
        function mceCalls(method) {
            return Backend.calls.filter(function (c) { return c.method === "com.nokia.mce.request." + method })
        }

        function test_01_rules() {
            var a = HA.parse(alertHints("hr-high", 128, 120))
            compare(a.kind, "high")
            compare(a.bpm, 128)
            compare(a.threshold, 120)
            compare(a.start, new Date(2026, 10, 25, 9, 40).getTime())
            compare(HA.parse(alertHints("hr-low", 41, 50)).kind, "low")
            // not an alert: another category, a broken hint, another type
            compare(HA.parse({ "x-asteroid-category": "celebration", "x-asteroid-health": "{\"type\":\"hr-high\"}" }), null)
            compare(HA.parse({ "x-asteroid-category": "health-alert", "x-asteroid-health": "{" }), null)
            compare(HA.parse({ "x-asteroid-category": "health-alert", "x-asteroid-health": "{\"type\":\"reminder-to-move\"}" }), null)
            compare(HA.parse(null), null)
            compare(HA.AUTO_DISMISS_MS, 60000)
            compare(HA.remainingMs(1000, 1000), 60000)
            compare(HA.remainingMs(1000, 61000), 0)
            compare(HA.remainingMs(1000, 31000), 30000)
            compare(HA.remainingMs(5000, 1000), 0)
        }

        function test_02_arrival_high() {
            verify(!hr.shown)
            compare(Desktop.hrAlert, hr)
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            verify(hr.shown)
            tryCompare(hr.dialog, "alpha", 1)
            compare(find(hr, "hrAlertTitle").text, "High heart rate")
            compare(find(hr, "hrAlertBpm").text, "128 bpm")
            compare(find(hr, "hrAlertDetail").text, "Your heart rate rose above 120 bpm while you appeared to be inactive from "
                    + TimeFormat.time(new Date(2026, 10, 25, 9, 40)) + " - " + TimeFormat.time(new Date(2026, 10, 25, 9, 50)) + ".")
            verify(find(hr, "hrAlertPlus").visible)
            verify(find(hr, "hrAlertIcon").visible)
            // the order of stock's list: icon, title, bpm, detail, top to bottom, centred
            var icon = find(hr, "hrAlertIcon"), t = find(hr, "hrAlertTitle"), b = find(hr, "hrAlertBpm"), d = find(hr, "hrAlertDetail")
            verify(icon.mapToItem(hr, 0, 0).y < t.mapToItem(hr, 0, 0).y)
            verify(t.mapToItem(hr, 0, 0).y < b.mapToItem(hr, 0, 0).y)
            verify(b.mapToItem(hr, 0, 0).y < d.mapToItem(hr, 0, 0).y)
            compare(Math.round(icon.mapToItem(hr, icon.width / 2, 0).x), 192)
            // the arrival asks mce for the display, once
            compare(mceCalls("notification_begin_req").length, 1)
            compare(mceCalls("notification_begin_req")[0].args[0], "asteroid-hr-alert")
            shot("hralert-high")
            hr.list.contentY = hr.list.contentHeight - hr.height
            wait(400)
            shot("hralert-high-end")
            // the edge button closes the screen and lets the display go
            var edge = hr.dismissButton
            mouseClick(edge, edge.width / 2, edge.height - 20)
            tryVerify(function () { return !hr.shown })
            tryVerify(function () { return mceCalls("notification_end_req").length === 1 }, 2000, "the display let go")
        }

        function test_03_low() {
            presenterDouble.fullScreenRequested(note("hr-low", 41, 50))
            verify(hr.shown)
            compare(find(hr, "hrAlertTitle").text, "Low heart rate")
            compare(find(hr, "hrAlertBpm").text, "41 bpm")
            verify(find(hr, "hrAlertDetail").text.indexOf("Your heart rate fell below 50 bpm") === 0)
            verify(!find(hr, "hrAlertPlus").visible)
            shot("hralert-low")
            hr.close()
            tryVerify(function () { return !hr.shown })
        }

        function test_04_auto_dismiss() {
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            verify(hr.shown)
            verify(hr.autoDismiss)
            verify(hr.timer.running)
            compare(hr.timer.interval, 60000)
            // a scroll 40 s on: the minute starts again
            testRoot.clockMs += 40000
            hr.touched()
            compare(hr.timer.interval, 60000)
            // the display goes off: no timer; on again 70 s after the scroll: it closes
            hr.displayOn = false
            verify(!hr.timer.running)
            testRoot.clockMs += 70000
            hr.displayOn = true
            tryVerify(function () { return !hr.shown })
            // on again 30 s after the arrival: what is left of the minute
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            hr.displayOn = false
            testRoot.clockMs += 30000
            hr.displayOn = true
            verify(hr.shown)
            compare(hr.timer.interval, 30000)
            // the timer's end
            testRoot.clockMs += 30000
            hr.timer.triggered()
            tryVerify(function () { return !hr.shown })
        }

        function test_05_from_card() {
            // the stream's card: the screen, no display request, no minute
            verify(Desktop.hrAlert.openFromCard(note("hr-high", 128, 120)))
            verify(hr.shown)
            verify(!hr.autoDismiss)
            verify(!hr.timer.running)
            compare(mceCalls("notification_begin_req").length, 0)
            testRoot.clockMs += 600000
            hr.displayOn = false
            hr.displayOn = true
            verify(hr.shown)
            hr.close()
            tryVerify(function () { return !hr.shown })
            wait(300)
            compare(mceCalls("notification_end_req").length, 0)
            // any other card is not its: the stream opens it as before
            var other = notificationComp.createObject(testRoot, { hints: { "x-asteroid-category": "celebration" } })
            verify(!Desktop.hrAlert.openFromCard(other))
            verify(!hr.shown)
            verify(!Desktop.hrAlert.openFromCard(null))
        }

        function test_06_theater() {
            // Theater: the screen is there for the button's wake, the display stays off
            modes.theater = true
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            verify(hr.shown)
            compare(mceCalls("notification_begin_req").length, 0)
            hr.close()
            tryVerify(function () { return !hr.shown })
        }

        function test_07_second_alert() {
            // a new alert while one shows: the screen shows the new one (one card, one screen)
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            testRoot.clockMs += 30000
            presenterDouble.fullScreenRequested(note("hr-low", 44, 50))
            verify(hr.shown)
            compare(find(hr, "hrAlertTitle").text, "Low heart rate")
            compare(find(hr, "hrAlertBpm").text, "44 bpm")
            compare(hr.timer.interval, 60000)
            compare(hr.shows, 2)
            hr.close()
            tryVerify(function () { return !hr.shown })
        }

        function test_08_colours() {
            presenterDouble.fullScreenRequested(note("hr-high", 128, 120))
            compare(String(find(hr, "hrAlertTitle").color), String(Qt.color(HA.ACCENT)))
            compare(String(find(hr, "hrAlertBpm").color), String(Qt.color(HA.ACCENT)))
            compare(String(hr.dismissButton.containerColor), String(Qt.color(HA.ACCENT)))
            compare(hr.dismissButton.iconName, "ms-check")
            compare(HA.ACCENT, "#94D6FF")
            hr.close()
            tryVerify(function () { return !hr.shown })
        }
    }
}
