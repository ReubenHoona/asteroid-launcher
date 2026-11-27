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
//  - R5 D-20: pause, resume and reset the timer by voice (Assistant's timer_paused/_resumed/_reset_confirmation),
//    with the Timer app's edits of the countdown alarm, stock's answers when there is nothing to do.
//  - R5 D-21: snooze or stop the ringing alarm (the presenter's "Ringing" notification) through the presenter's
//    snooze / dismiss; nothing ringing (a snoozed alarm, a ringing timer): stock's no_alarms_to_snooze / _stop;
//    a presenter without the methods: the alarm screen comes back.
//  - R5 D-22: "Start the stopwatch" writes the Stopwatch's start request ("<ms>") and opens the app.
//  - R5 D-11: "Start a run" writes the Exercise app's start request ("Run@<ms>", as the Exercise tile) and opens
//    the app; no type or one the app does not have: the app's list, no request.
//  - R5 D-12: "What's on my calendar?" from the calendar (a reader double with invented events): the day's events
//    that have not ended, the next one of the week, a clear day; the card opens the Calendar (on the event it names).
// MODE=st (the staged tree).
import QtQuick
import QtTest
import Nemo.Alarms
import LauncherTest
import org.nemomobile.lipstick
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

    // R5 D-12: the calendar reader (AssistantAgenda.qml's interface) on invented events, read a moment later
    property var agendaEvents: []
    property int agendaReaders: 0
    Component {
        id: fakeAgenda
        QtObject {
            id: fa
            property date startDate
            property date endDate
            signal updated()
            function list() {
                var a = startDate.getTime(), b = endDate.getTime()
                return top.agendaEvents.filter(function (e) { return e.end > a && e.start < b })
            }
            property Timer later: Timer { interval: 20; running: true; onTriggered: fa.updated() }
            Component.onCompleted: top.agendaReaders++
            Component.onDestruction: top.agendaReaders--
        }
    }

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
            aa.agendaReader = fakeAgenda
        }
        function init() {
            AlarmsMock.alarms = []
            AlarmsMock.creatable = true
            fakeDesktop.launched = []
            got = null
            var m = Lipstick.notificationModel
            while (m && m.itemCount > 0)
                m.remove(m.get(0))
            Backend.errors = {}
            Backend.clearCalls()
        }
        // the alarm presenter's notices (asteroid-alarmclock alarmpresenter noticeFor), invented times
        readonly property string presenterService: "org.asteroidos.alarmpresenter"
        function presenterNotice(kind, id, time, alarmKind) {
            var hints = { "category": "x-nemo.alarm", "x-eos-app": "asteroid-alarmclock", "resident": true }
            if (kind === "ringing")
                hints["x-nemo-remote-action-default"] = presenterService + " /org/asteroidos/alarmpresenter " + presenterService + " show"
            else {
                hints["x-nemo-remote-action-default"] = "org.asteroidos.alarmclock /org/asteroidos/alarmclock org.asteroidos.alarmclock show"
                hints["x-nemo-remote-action-stop"] = presenterService + " /org/asteroidos/alarmpresenter " + presenterService + " stop " + id
            }
            if (alarmKind)
                hints["x-eos-alarm-kind"] = alarmKind
            var n = { replacesId: id, summary: "Alarm", body: kind === "ringing" ? time : "Snoozing until " + time,
                      hints: hints, timestamp: new Date() }
            Lipstick.notificationModel.add(n)
            return n
        }
        function presenterCall(method) { return Backend.find(presenterService, presenterService + "." + method) }
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
        // an answer that comes later (a reader, a log)
        function askLater(intent, slots) {
            got = null
            aa.run(intent, slots, "", function (c) { got = c })
            tryVerify(function () { return got !== null }, 4000)
            return got
        }
        // ms of a time of the day `offset` days from today
        function at(offset, h, m) {
            var n = new Date()
            return new Date(n.getFullYear(), n.getMonth(), n.getDate() + offset, h, m).getTime()
        }
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

        // R5 D-20: a running 5 minute timer with 3 minutes left is paused, then resumed, then reset
        function test_d20_pause_resume_reset() {
            var t = AlarmsMock.make({ countdown: true, minute: 5, enabled: true, triggerTime: nowS() + 180 })
            AlarmsMock.alarms = [t]
            var c = ask("timer.pause", {})
            compare(c.text, "I have paused the timer.")
            compare(t.enabled, false)
            compare(t.triggerTime, 0)
            verify(t.elapsed >= 119 && t.elapsed <= 121, "elapsed " + t.elapsed)
            verify(c.title === "3:00" || c.title === "2:59", c.title)
            compare(c.chips.length, 1)
            compare(c.chips[0].label, "Open Timer")
            // paused: pausing again says so and changes nothing
            c = ask("timer.pause", {})
            compare(c.text, "Timer is already paused.")
            compare(t.triggerTime, 0)
            // resume: it ends what was left from now
            c = ask("timer.resume", {})
            compare(c.text, "I have resumed the timer.")
            compare(t.enabled, true)
            var left = t.triggerTime - nowS()
            verify(left >= 178 && left <= 181, "left " + left)
            c = ask("timer.resume", {})
            compare(c.text, "Timer is already running.")
            // reset: the whole length, waiting (the Timer app's Reset), the same alarm
            c = ask("timer.reset", {})
            compare(c.text, "I have reset the timer.")
            compare(c.title, "5:00")
            compare(t.enabled, false)
            compare(t.triggerTime, 0)
            compare(t.elapsed, 0)
            compare(AlarmsMock.alarms, [t])
            // a reset timer is a paused one at its whole length: resume starts it
            c = ask("timer.resume", {})
            compare(c.text, "I have resumed the timer.")
            left = t.triggerTime - nowS()
            verify(left >= 298 && left <= 301, "left " + left)
        }

        // R5 D-21: nothing rings: stock's answers, nothing is asked of the presenter
        function test_d21_nothing_rings() {
            compare(ask("alarm.snooze", {}).text, "I couldn't find any alarms to snooze.")
            compare(ask("alarm.stop", {}).text, "I couldn't find any alarms to stop.")
            // a snoozed alarm is not ringing (stock: only the firing ones), nor is a ringing timer
            presenterNotice("snoozed", 41, "06:50")
            presenterNotice("ringing", 42, "0:00", "timer")
            compare(ask("alarm.stop", {}).text, "I couldn't find any alarms to stop.")
            compare(ask("alarm.snooze", {}).text, "I couldn't find any alarms to snooze.")
            compare(presenterCall("snooze"), null)
            compare(presenterCall("dismiss"), null)
        }

        // R5 D-21: an alarm rings: the presenter snoozes or dismisses it, the card says so with its time
        function test_d21_snooze_and_stop() {
            presenterNotice("ringing", 43, "06:45")
            var c = ask("alarm.snooze", {})
            compare(c.text, "I have snoozed the alarm.")
            compare(c.title, "06:45")
            verify(c.error !== true)
            verify(presenterCall("snooze") !== null)
            compare(presenterCall("dismiss"), null)
            Backend.clearCalls()
            // a presenter of before x-eos-alarm-kind: the ringing notice is an alarm
            c = ask("alarm.stop", {})
            compare(c.text, "I have stopped the alarm.")
            verify(presenterCall("dismiss") !== null)
            compare(presenterCall("snooze"), null)
        }

        // R5 D-21: a presenter without snooze / dismiss (image 72's): the card says where to do it, Show alarm
        // brings the alarm screen back
        function test_d21_presenter_without_the_methods() {
            presenterNotice("ringing", 44, "07:10", "alarm")
            Backend.errors = { "org.asteroidos.alarmpresenter.snooze": "org.freedesktop.DBus.Error.UnknownMethod",
                               "org.asteroidos.alarmpresenter.dismiss": "org.freedesktop.DBus.Error.UnknownMethod" }
            var c = ask("alarm.snooze", {})
            compare(c.error, true)
            compare(c.text, "Snooze it on the alarm screen.")
            compare(c.chips.length, 1)
            compare(c.chips[0].label, "Show alarm")
            var r = null
            c.chips[0].run(function (x) { r = x })
            verify(r !== null && r.close === true)
            r.then()
            verify(presenterCall("show") !== null)
            compare(ask("alarm.stop", {}).text, "Stop it on the alarm screen.")
        }

        // R5 D-22: the overlay goes, the request is written, then the app starts
        function test_d22_start_stopwatch() {
            var before = Date.now()
            var c = ask("stopwatch.start", {})
            verify(c !== null && c.close === true)
            compare(fakeDesktop.launched, [])
            c.then()
            compare(fakeDesktop.launched, ["asteroid-stopwatch"])
            var req = Number(Backend.conf["/org/asteroidos/stopwatch/start-request"])
            verify(req >= before && req <= Date.now() + 1, "request " + req)
        }

        // R5 D-11: a run, then a workout with no type, then a type the app does not know
        function test_d11_start_exercise() {
            var key = "/org/asteroidos/exercise/start-request"
            Backend.confSet(key, "")
            var before = Date.now()
            var c = ask("exercise.start", { type: "Run" })
            verify(c !== null && c.close === true)
            compare(fakeDesktop.launched, [])
            c.then()
            compare(fakeDesktop.launched, ["asteroid-exercise"])
            var req = String(Backend.conf[key])
            compare(req.split("@")[0], "Run")
            var ms = Number(req.split("@")[1])
            verify(ms >= before && ms <= Date.now() + 1, req)
            // "start a workout": the app's list, the request is not written again
            Backend.confSet(key, "")
            fakeDesktop.launched = []
            ask("exercise.start", {}).then()
            compare(fakeDesktop.launched, ["asteroid-exercise"])
            compare(Backend.conf[key], "")
            ask("exercise.start", { type: "Juggling" }).then()
            compare(Backend.conf[key], "")
            // the app's keys as they are: a yoga session
            ask("exercise.start", { type: "Yoga" }).then()
            compare(String(Backend.conf[key]).split("@")[0], "Yoga")
        }

        // R5 D-12: tomorrow's events in order (an all-day one first), the next day's left out; the chip opens the app
        function test_d12_day_list() {
            top.agendaEvents = [
                { start: at(1, 13, 30), end: at(1, 14, 0), title: "Dentist", allDay: false },
                { start: at(1, 9, 0), end: at(1, 10, 0), title: "Design review", allDay: false },
                { start: at(1, 0, 0), end: at(2, 0, 0), title: "Market day", allDay: true },
                { start: at(2, 9, 0), end: at(2, 10, 0), title: "Book club", allDay: false }
            ]
            var c = askLater("calendar.query", { day: 1 })
            compare(c.text, "You have 3 events tomorrow: Market day (all day), Design review at 09:00 and Dentist at 13:30.")
            compare(c.title, "All day")
            compare(c.chips.length, 1)
            compare(c.chips[0].label, "Open Calendar")
            Backend.confSet("/org/asteroidos/calendar/ui/open", "")
            var r = null
            c.chips[0].run(function (x) { r = x })
            verify(r !== null && r.close === true)
            r.then()
            compare(fakeDesktop.launched, ["asteroid-calendar"])
            compare(Backend.conf["/org/asteroidos/calendar/ui/open"], "")
            // the reader is made for the question and dropped after it
            tryCompare(top, "agendaReaders", 0)
            // four events: three named, the rest counted
            top.agendaEvents = top.agendaEvents.concat([{ start: at(1, 18, 0), end: at(1, 19, 0), title: "Choir", allDay: false }])
            compare(askLater("calendar.query", { day: 1 }).text,
                    "You have 4 events tomorrow: Market day (all day), Design review at 09:00 and Dentist at 13:30. And 1 more.")
        }

        // R5 D-12: one event: the card names it and the chip opens the Calendar on it (the agenda tile's request)
        function test_d12_one_event() {
            var start = at(1, 9, 0)
            top.agendaEvents = [{ start: start, end: at(1, 10, 0), title: "Design review", allDay: false }]
            var c = askLater("calendar.query", { day: 1 })
            compare(c.text, "You have 1 event tomorrow: Design review at 09:00.")
            compare(c.title, "09:00")
            var r = null
            c.chips[0].run(function (x) { r = x })
            r.then()
            compare(fakeDesktop.launched, ["asteroid-calendar"])
            var req = String(Backend.conf["/org/asteroidos/calendar/ui/open"])
            compare(req.split("@")[0], "event:" + start)
        }

        // R5 D-12: the next event of the week, one that is on now, none
        function test_d12_next() {
            var start = at(3, 10, 0)
            top.agendaEvents = [{ start: start, end: at(3, 11, 0), title: "Book club", allDay: false }]
            var day = Qt.locale("en_GB").dayName(new Date(start).getDay(), Locale.LongFormat)
            var c = askLater("calendar.query", { day: 0, next: true })
            compare(c.text, "Your next event is Book club, on " + day + " at 10:00.")
            compare(c.title, "10:00")
            // one on now comes first
            var n = Date.now()
            var end = new Date(n + 20 * 60000)
            top.agendaEvents = top.agendaEvents.concat([{ start: n - 10 * 60000, end: end.getTime(), title: "Stand-up", allDay: false }])
            c = askLater("calendar.query", { day: 0, next: true })
            compare(c.text, "Stand-up is on now, until " + Qt.formatTime(end, "HH:mm") + ".")
            // nothing in the coming week (the window ends a week ahead)
            top.agendaEvents = [{ start: at(9, 10, 0), end: at(9, 11, 0), title: "Far away", allDay: false }]
            c = askLater("calendar.query", { day: 0, next: true })
            compare(c.text, "There's nothing on your calendar for the next 7 days.")
            compare(c.title, "")
        }

        // R5 D-12: the real reader (org.nemomobile.calendar of the image) loads, reads its window and gives a list
        function test_d12_real_reader() {
            var comp = Qt.createComponent(Qt.resolvedUrl("st/qml/assistant/AssistantAgenda.qml"))
            compare(comp.status, Component.Ready, comp.errorString())
            var n = new Date()
            var r = comp.createObject(top, { "startDate": new Date(n.getFullYear(), n.getMonth(), n.getDate()),
                                             "endDate": new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1) })
            verify(r !== null)
            var l = r.list()
            verify(Array.isArray(l))
            r.destroy()
        }

        // R5 D-12: a clear day, a day whose events have ended, an empty tomorrow
        function test_d12_clear() {
            top.agendaEvents = []
            compare(askLater("calendar.query", { day: 0 }).text, "Your day is clear.")
            compare(askLater("calendar.query", { day: 1 }).text, "There's nothing on your calendar tomorrow.")
            var n = new Date()
            var earlier = new Date(n.getTime() - 40 * 60000)
            if (earlier.getDate() === n.getDate()) {
                top.agendaEvents = [{ start: earlier.getTime(), end: n.getTime() - 10 * 60000, title: "Breakfast", allDay: false }]
                compare(askLater("calendar.query", { day: 0 }).text, "There's nothing else on your calendar today.")
            }
        }

        // R5 D-20: nothing to pause, resume or reset (stock's no_timers_alarms_running, no_timers_to_reset_message)
        function test_d20_nothing_active() {
            var none = "I couldn't find any timers or alarms that are active right now."
            compare(ask("timer.pause", {}).text, none)
            compare(ask("timer.resume", {}).text, none)
            compare(ask("timer.reset", {}).text, none)
            // a timer that rang: not active, nothing changes
            var rung = AlarmsMock.make({ countdown: true, minute: 1, enabled: true, triggerTime: nowS() - 30 })
            AlarmsMock.alarms = [rung]
            compare(ask("timer.pause", {}).text, none)
            compare(ask("timer.reset", {}).text, "I couldn't find any timers to reset.")
            compare(rung.enabled, true)
            verify(rung.triggerTime > 0)
            // an alarm is never a timer
            AlarmsMock.alarms = [AlarmsMock.make({ countdown: false, hour: 7, minute: 0, enabled: true })]
            compare(ask("timer.pause", {}).text, none)
        }
    }
}
