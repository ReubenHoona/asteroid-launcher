/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 E-05, E-06, E-18: the full screen celebrations (src/qml/system/GoalCelebration.qml, goals.js), as stock's Fitbit
// CelebrationActivity (trj.java:115-185, GoalAchievedCelebration.java, tsa.java e() and f(), tui.java:505-580) on the
// repo's doubles: the notification server hands over asteroid-sensorlogd's posts (a presenter double with
// fullScreenRequested, as lipstick's for x-asteroid-category celebration), invented values in the hints sensorlogd
// posts (x-asteroid-health: the main goal of each type, the hourly activity, a reminder to move and its goal). The
// screens, the rules (quiet modes, charger, off the wrist, the switch, a covered moment), the arrival turning the
// display on (mce) and the 10 s; anything that is not a celebration is left alone. No sound or vibration here: a
// goal's two confirmations are counted as script calls of the Haptics double. Shots in /tmp/r5hl-shots.
// MODE=st (the staged tree).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml/system/goals.js" as Goals

Item {
    id: testRoot
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: presenterDouble
        signal fullScreenRequested(var notification)
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: loader; anchors.fill: parent; active: false; source: Qt.resolvedUrl("st/qml/system/GoalCelebration.qml") }

    function hints(j, category) {
        return { "x-asteroid-category": category === undefined ? "celebration" : category,
                 "x-asteroid-health": typeof j === "string" ? j : JSON.stringify(j), "transient": true }
    }
    Component {
        id: notificationComp
        QtObject {
            property string appName: "Health"
            property string summary: "Steps"
            property string body: "Goal complete!\n10000"
            property var hints: ({})
        }
    }

    TestCase {
        name: "Celebration"
        when: windowShown

        property var cel: null

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
        function post(j, category) {
            presenterDouble.fullScreenRequested(notificationComp.createObject(testRoot, { hints: hints(j, category) }))
        }
        function init() {
            Backend.reset()
            Backend.confSet("/org/asteroidos/health/celebrations", true)
            Backend.confSet("/org/asteroidos/sensors/off-body", false)
            Backend.confSet("/org/asteroidos/sensors/off-body-available", false)
            loader.active = true
            cel = loader.item
            verify(cel !== null)
            cel.presenter = presenterDouble
            cel.displayOn = true
            cel.blocked = false
            cel.quiet = false
        }
        function cleanup() {
            loader.active = false
            cel = null
            wait(0)
        }
        function shot(name) {
            testRoot.grabToImage(function (r) { r.saveToFile("/tmp/r5hl-shots/" + name + ".png") })
            wait(80)
        }
        function mceCalls(method) {
            return Backend.calls.filter(function (c) { return c.method === "com.nokia.mce.request." + method })
        }
        function closeIt() {
            cel.close()
            tryVerify(function () { return !cel.shown })
        }

        // ---- the rules (goals.js)
        function test_01_parse() {
            compare(Goals.parse(hints({ type: "goal", metric: "steps", value: 10021, goal: 10000 })).kind, "goal")
            compare(Goals.parse(hints({ type: "goal", metric: "azm", value: 22, goal: 22 })).metric, "azm")
            var h = Goals.parse(hints({ type: "hourly-activity", hours: 9 }))
            compare(h.kind, "goal")
            compare(h.metric, "hourly")
            compare(h.value, 9)
            var r = Goals.parse(hints({ type: "reminder-to-move", steps: 100, goal: 250 }))
            compare(r.kind, "rtm")
            compare(r.left, 150)
            compare(Goals.ringProgress(r), 0.4)
            var d = Goals.parse(hints({ type: "reminder-to-move-complete", steps: 251, goal: 250 }))
            compare(d.kind, "rtm-done")
            compare(Goals.ringProgress(d), 1)
            // not one: another category, a broken hint, an unknown type or metric, the heart rate alert's
            compare(Goals.parse(hints({ type: "goal", metric: "steps", value: 1 }, "health-alert")), null)
            compare(Goals.parse(hints("{")), null)
            compare(Goals.parse(hints({ type: "hr-high", bpm: 128 })), null)
            compare(Goals.parse(hints({ type: "goal", metric: "sleep", value: 480 })), null)
            compare(Goals.parse(null), null)
            compare(Goals.SHOW_MS, 10000)
        }
        function test_02_mayShow() {
            var ok = { blocked: false, quiet: false, charging: false, offWrist: false, enabled: true }
            verify(Goals.mayShow(ok))
            for (var k of ["blocked", "quiet", "charging", "offWrist"]) {
                var c = Object.assign({}, ok)
                c[k] = true
                verify(!Goals.mayShow(c), k)
            }
            verify(!Goals.mayShow(Object.assign({}, ok, { enabled: false })))
        }
        function test_03_values() {
            var f = { cal: "%1 cal", floors: "%1 floors", azm: "%1 Zone Mins", hours: "%1 hr", km: "%1 km", mi: "%1 mi" }
            var en = Qt.locale("en_GB")
            compare(Goals.valueText({ metric: "steps", value: 10021 }, en, false, f), "10,021")
            compare(Goals.valueText({ metric: "calories", value: 2004.6 }, en, false, f), "2,005 cal")
            compare(Goals.valueText({ metric: "distance", value: 8050 }, en, false, f), "8.05 km")
            compare(Goals.valueText({ metric: "distance", value: 10000 }, en, false, f), "10 km")
            compare(Goals.valueText({ metric: "distance", value: 8100 }, en, false, f), "8.1 km")
            compare(Goals.valueText({ metric: "distance", value: 8047 }, en, true, f), "5 mi")
            compare(Goals.valueText({ metric: "floors", value: 10 }, en, false, f), "10 floors")
            compare(Goals.valueText({ metric: "azm", value: 22 }, en, false, f), "22 Zone Mins")
            compare(Goals.valueText({ metric: "hourly", value: 9 }, en, false, f), "9 hr")
        }

        // ---- the screens
        function test_04_the_main_goal_of_each_type() {
            var expect = [
                ["steps", 10021, "Steps", Number(10021).toLocaleString(Qt.locale(), "f", 0), "eos-health-steps"],
                ["calories", 2004, "Calories", Number(2004).toLocaleString(Qt.locale(), "f", 0) + " cal", "eos-health-energy"],
                ["distance", 8050, "Distance", cel.imperial ? "5 mi" : "8.05 km", "eos-health-distance"],
                ["floors", 10, "Floors", "10 floors", "eos-health-floors"],
                ["azm", 22, "Active Zone Min", "22 Zone Mins", "eos-health-azm"]
            ]
            for (var i = 0; i < expect.length; i++) {
                var e = expect[i]
                post({ type: "goal", metric: e[0], value: e[1], goal: e[1] })
                verify(cel.shown, e[0])
                compare(cel.kind, "goal")
                verify(find(cel, "celebrationContent").visible)
                verify(!find(cel, "reminderContent").visible)
                compare(find(cel, "celebrationTitle").text, "Goal complete!")
                compare(find(cel, "celebrationName").text, e[2])
                if (e[0] !== "distance")
                    compare(find(cel, "celebrationValue").text, e[3])
                compare(find(cel, "celebrationIcon").name, e[4])
                // a goal's vibration: its own two confirmations (its post has none)
                verify(cel.vibration.running)
                verify(cel.confettiAnimation.running)
                compare(cel.hideTimer.interval, 10000)
                verify(cel.hideTimer.running)
                tryCompare(cel.dialog, "alpha", 1)
                shot("goal-" + e[0])
                closeIt()
            }
            compare(cel.shows, 5)
        }

        function test_05_hourly_activity() {
            post({ type: "hourly-activity", hours: 9 })
            verify(cel.shown)
            compare(find(cel, "celebrationName").text, "Hourly Activity")
            compare(find(cel, "celebrationValue").text, "9 hr")
            compare(find(cel, "celebrationIcon").name, "eos-health-hourly")
            verify(cel.vibration.running)
            tryCompare(cel.dialog, "alpha", 1)
            shot("hourly-activity")
            closeIt()
        }

        function test_06_reminder_to_move() {
            post({ type: "reminder-to-move", steps: 100, goal: 250 })
            verify(cel.shown)
            compare(cel.kind, "rtm")
            verify(find(cel, "reminderContent").visible)
            verify(!find(cel, "celebrationContent").visible)
            verify(!find(cel, "reminderLabel").visible)
            compare(find(cel, "reminderTitle").text, "Reminder to move")
            compare(find(cel, "reminderValue").text, "150 steps left\nthis hour")
            compare(find(cel, "reminderRing").progress, 0.4)
            compare(find(cel, "reminderIcon").name, "eos-health-hourly")
            // its vibration is its post's (lipstick plays it); no confetti for a reminder
            verify(!cel.vibration.running)
            compare(find(cel, "confetti"), null)
            tryCompare(cel.dialog, "alpha", 1)
            // stock's order: the ring, the title, the steps
            var ring = find(cel, "reminderRing"), t = find(cel, "reminderTitle"), v = find(cel, "reminderValue")
            verify(ring.mapToItem(cel, 0, 0).y < t.mapToItem(cel, 0, 0).y)
            verify(t.mapToItem(cel, 0, 0).y < v.mapToItem(cel, 0, 0).y)
            compare(Math.round(ring.mapToItem(cel, ring.width / 2, 0).x), 192)
            shot("rtm-reminder")
            closeIt()
            post({ type: "reminder-to-move", steps: 249, goal: 250 })
            compare(find(cel, "reminderValue").text, "1 step left\nthis hour")
            closeIt()
        }

        function test_07_reminder_goal_reached() {
            post({ type: "reminder-to-move-complete", steps: 251, goal: 250 })
            verify(cel.shown)
            compare(cel.kind, "rtm-done")
            var label = find(cel, "reminderLabel"), ring = find(cel, "reminderRing"), t = find(cel, "reminderTitle"),
                v = find(cel, "reminderValue")
            verify(label.visible)
            compare(label.text, "Reminder to move")
            compare(t.text, "Goal complete!")
            compare(v.text, "250/250")
            compare(ring.progress, 1)
            tryCompare(cel.dialog, "alpha", 1)
            // stock's order (tsa.java e()): the label, the ring, the title, the value
            verify(label.mapToItem(cel, 0, 0).y < ring.mapToItem(cel, 0, 0).y)
            verify(ring.mapToItem(cel, 0, 0).y < t.mapToItem(cel, 0, 0).y)
            verify(t.mapToItem(cel, 0, 0).y < v.mapToItem(cel, 0, 0).y)
            shot("rtm-complete")
            closeIt()
        }

        // ---- the arrival
        function test_08_display_off_turns_it_on() {
            cel.displayOn = false
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(!cel.shown)
            verify(cel.pending !== null)
            compare(mceCalls("notification_begin_req").length, 1)
            compare(mceCalls("notification_begin_req")[0].args[0], "asteroid-celebration")
            cel.displayOn = true
            verify(cel.shown)
            compare(cel.pending, null)
            closeIt()
            tryVerify(function () { return mceCalls("notification_end_req").length === 1 }, 2000, "the display let go")
            // with the display on nothing is asked of mce
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            compare(mceCalls("notification_begin_req").length, 1)
            closeIt()
        }

        function test_09_dropped_when_it_may_not_show() {
            cel.quiet = true
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(!cel.shown)
            cel.quiet = false
            cel.blocked = true
            post({ type: "reminder-to-move", steps: 0, goal: 250 })
            verify(!cel.shown)
            cel.blocked = false
            Backend.chargerType = 1 // on the charger (stock: "Device is charging")
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(!cel.shown)
            Backend.chargerType = 0
            Backend.confSet("/org/asteroidos/sensors/off-body-available", true)
            Backend.confSet("/org/asteroidos/sensors/off-body", true)
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(!cel.shown)
            Backend.confSet("/org/asteroidos/sensors/off-body", false)
            Backend.confSet("/org/asteroidos/health/celebrations", false)
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(!cel.shown)
            Backend.confSet("/org/asteroidos/health/celebrations", true)
            // not a celebration: left alone
            post({ type: "hr-high", bpm: 128, threshold: 120 }, "health-alert")
            verify(!cel.shown)
            compare(cel.shows, 0)
            compare(mceCalls("notification_begin_req").length, 0)
            // and now it may
            post({ type: "goal", metric: "floors", value: 10, goal: 10 })
            verify(cel.shown)
            closeIt()
        }

        function test_10_ten_seconds_and_a_tap() {
            post({ type: "goal", metric: "steps", value: 10000, goal: 10000 })
            verify(cel.shown)
            cel.hideTimer.triggered()
            tryVerify(function () { return !cel.shown })
            post({ type: "reminder-to-move", steps: 0, goal: 250 })
            verify(cel.shown)
            tryCompare(cel.dialog, "alpha", 1)
            mouseClick(cel, cel.width / 2, cel.height / 2)
            tryVerify(function () { return !cel.shown })
            // nothing runs once it is gone (its exit animation over)
            tryVerify(function () { return !cel.hideTimer.running && !cel.vibration.running && !cel.confettiAnimation.running })
        }
    }
}
