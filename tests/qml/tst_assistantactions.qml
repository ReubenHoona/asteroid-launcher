/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// The assistant's actions (src/qml/assistant/AssistantActions.qml) on the repo mocks (Nemo.Alarms with
// AlarmsMock.creatable, Nemo.Configuration over Backend.conf, the HealthLog without data):
//  - alarms-timers-stopwatch-31: one timer at a time, the Timer app's rule. With a running or paused
//    countdown "Set a timer" asks the app's question (DeskClock timer_alert_dialog_message) with Yes and
//    No; Yes deletes every countdown and starts the new one, No leaves the active one; a timer that rang
//    is not active.
//  - health-fitness-21: the heart rate answers with the last reading or "--" and opens Health's heart
//    rate page ("heartrate@<ms>"), never the hidden asteroid-hrm.
// MODE=st (the staged tree).
import QtQuick
import QtTest
import Nemo.Alarms
import LauncherTest
import "st/qml/desktop.js" as Desktop

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: fakeDesktop
        property var launched: []
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }

    Loader { id: al; active: false; source: Qt.resolvedUrl("st/qml/assistant/AssistantActions.qml") }

    TestCase {
        name: "AssistantActions"
        when: windowShown

        property var aa: null
        property var got: null
        readonly property string question: "You already have an active timer. Are you sure you want to replace your current timer with a new one?"

        function initTestCase() {
            Desktop.desktop = fakeDesktop
            al.active = true
            tryCompare(al, "status", Loader.Ready, 30000)
            aa = al.item
        }
        function init() {
            AlarmsMock.alarms = []
            AlarmsMock.creatable = true
            fakeDesktop.launched = []
            got = null
        }
        function cleanup() {
            AlarmsMock.creatable = false
            AlarmsMock.alarms = []
        }

        function ask(intent, slots) {
            got = null
            aa.run(intent, slots, "", function (c) { got = c })
            return got
        }
        function nowS() { return Math.floor(Date.now() / 1000) }
        function countdowns() { return AlarmsMock.alarms.filter(function (a) { return a.countdown === true }) }

        function test_00_no_timer_starts_one() {
            var c = ask("timer.set", { seconds: 300 })
            verify(c !== null)
            compare(countdowns().length, 1)
            compare(countdowns()[0].enabled, true)
            verify(c.text.indexOf("starting now") >= 0, c.text)
            compare(c.chips.length, 1)
        }

        function test_01_running_timer_asks_first() {
            var old = AlarmsMock.make({ countdown: true, minute: 10, enabled: true, triggerTime: nowS() + 300 })
            AlarmsMock.alarms = [old]
            var c = ask("timer.set", { seconds: 120 })
            compare(c.text, question)
            compare(c.chips.length, 2)
            compare(c.chips[0].label, "Yes")
            compare(c.chips[1].label, "No")
            // nothing changed while it asks
            compare(AlarmsMock.alarms, [old])
            // No: the active one stays
            var no = null
            c.chips[1].run(function (x) { no = x })
            verify(no !== null && no.text !== "" && no.text !== question)
            compare(AlarmsMock.alarms, [old])
            // Yes: the old one goes, the new one starts
            var yes = null
            c.chips[0].run(function (x) { yes = x })
            verify(yes !== null && yes.text.indexOf("starting now") >= 0, yes ? yes.text : "")
            compare(countdowns().length, 1)
            verify(countdowns()[0] !== old)
            compare(countdowns()[0].enabled, true)
        }

        function test_02_paused_timer_and_yes_deletes_every_countdown() {
            // paused: not enabled, no trigger time, time left; with it a timer that rang and an alarm
            var paused = AlarmsMock.make({ countdown: true, minute: 5, enabled: false, triggerTime: 0, elapsed: 60 })
            var rung = AlarmsMock.make({ countdown: true, minute: 1, enabled: true, triggerTime: nowS() - 30 })
            var alarm = AlarmsMock.make({ countdown: false, hour: 7, minute: 0, enabled: true })
            AlarmsMock.alarms = [paused, rung, alarm]
            var c = ask("timer.set", { seconds: 60 })
            compare(c.text, question)
            var yes = null
            c.chips[0].run(function (x) { yes = x })
            verify(yes !== null)
            // every countdown went (the paused one and the rung one), the alarm stays
            compare(countdowns().length, 1)
            verify(countdowns()[0] !== paused && countdowns()[0] !== rung)
            verify(AlarmsMock.alarms.indexOf(alarm) >= 0)
        }

        function test_03_a_timer_that_rang_is_not_active() {
            var rung = AlarmsMock.make({ countdown: true, minute: 1, enabled: true, triggerTime: nowS() - 30 })
            AlarmsMock.alarms = [rung]
            var c = ask("timer.set", { seconds: 60 })
            verify(c.text !== question)
            verify(c.text.indexOf("starting now") >= 0, c.text)
            compare(countdowns().length, 2)
        }

        function test_04_the_duration_chips_ask_too() {
            AlarmsMock.alarms = [AlarmsMock.make({ countdown: true, minute: 10, enabled: true, triggerTime: nowS() + 300 })]
            var c = ask("timer.ask", {})
            compare(c.chips.length, 3)
            var d = null
            c.chips[1].run(function (x) { d = x })
            compare(d.text, question)
            compare(countdowns().length, 1)
        }

        function test_05_heart_rate_opens_health() {
            ask("health.heartrate", {})
            // the log is read in a worker: the answer comes with its "changed" or after 1.5 s
            tryVerify(function () { return got !== null }, 4000)
            compare(got.title, "-- bpm")
            compare(got.chips.length, 1)
            compare(got.chips[0].label, "Open Health")
            var r = null
            got.chips[0].run(function (x) { r = x })
            verify(r !== null && r.close === true)
            r.then()
            compare(fakeDesktop.launched, ["asteroid-health"])
            verify(String(Backend.conf["/org/asteroidos/health/ui/open"]).indexOf("heartrate@") === 0)
            // "measure my heart rate": straight to the page, never asteroid-hrm
            fakeDesktop.launched = []
            ask("health.heartrate", { measure: true })
            verify(got !== null && got.close === true)
            got.then()
            compare(fakeDesktop.launched, ["asteroid-health"])
        }
    }
}
