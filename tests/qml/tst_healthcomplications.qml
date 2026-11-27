// Copyright (C) 2026 eos-mainline contributors
// SPDX-License-Identifier: BSD-3-Clause
//
// M4 WO-10: the face complications Calories, Floors, Active Zone Minutes and Exercise days (ComplicationSources and
// HealthSource.qml, src/qml/complications), as the Fitbit offloadable ones (APK-INDEX complication_services:
// OffloadableCaloriesComplicationDataSourceService, ...Floors..., ...AZM..., ...ExerciseDays...): the day's number
// and a ring towards stock's default goal (2500 Cal, 10 floors, 22 minutes: tuj.java), Exercise days as a ring of
// stock's 3 days (ttd.java:168) with the days done in the tint. The numbers come from the sensorlogd doubles of
// tests/qml/mocks (SensorlogdFixture: invented summaries and workouts) on a fixed clock (Wednesday 25 November
// 2026, 15:00 local). Read only while a slot shows one and the face is awake, again when the data changed or
// the day did, at most once a minute; a tap opens the Health app on the metric's page; the sensor hub's
// always-on screen draws the day's numbers '--'. Shots of the four in round slots in /tmp/m4wo10-shots.
// Staged as tst_ambientsources.qml (MODE=amb), HealthSource.qml beside ComplicationSources.qml.
import QtQuick
import QtTest
import org.asteroid.sensorlogd
import LauncherTest
import LauncherQml
import "LauncherQml/complications/complications.js" as C

Item {
    id: root
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: desktop
        property var launched: []
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }

    readonly property date fixedNow: new Date(2026, 10, 25, 15, 0, 0)
    function at(d, h, m) { return new Date(2026, 10, d, h, m || 0, 0).getTime() }
    function workout(d, h, mins, type, extra) {
        var w = { id: d * 100 + h, startMs: at(d, h), endMs: at(d, h) + mins * 60000, activeS: mins * 60, type: type,
                  distanceM: 0, kcal: mins * 8, azm: mins, ended: true }
        for (var k in extra)
            w[k] = extra[k]
        return w
    }

    ComplicationSources {
        id: sources
        active: true
        now: root.fixedNow
    }

    // what a ComplicationView registers (refreshDemand reads source and slotItem)
    property var shown: []
    function show(id) {
        var v = { source: id, slotItem: null }
        shown.push(v)
        sources.register(v)
        return v
    }

    // four round slots of a face, for the shot
    Rectangle {
        id: face
        width: 384; height: 384
        color: "black"
        visible: false
        Repeater {
            model: ["calories", "floors", "azm", "exercisedays"]
            delegate: Item {
                id: slot
                required property int index
                required property string modelData
                objectName: "eosComplication"
                property string slotId: "s" + index
                property string shape: "bulb"
                property string defaultSource: modelData
                property color tint: "#A8C7FA"
                x: 20 + index * 88
                y: 149
                width: 86
                height: 86
            }
        }
    }

    TestCase {
        name: "HealthComplications"
        when: windowShown

        function init() {
            Backend.reset()
            SensorlogdFixture.reset()
            sources.active = true
            sources.ambient = false
            sources.hubDrawn = false
            sources.now = root.fixedNow
            desktop.launched = []
        }
        function cleanup() {
            for (var i = 0; i < shown.length; i++)
                sources.unregister(shown[i])
            shown = []
            tryVerify(function () { return JSON.stringify(sources.demand) === "{}" }, 1000, "no slot shows anything")
            tryCompare(SensorlogdFixture, "alive", 0)
        }
        function today(summary) {
            var s = {}
            s[SensorlogdFixture.dayKey(root.fixedNow)] = summary
            SensorlogdFixture.summaries = s
        }

        function test_01_sources() {
            var kinds = ["calories", "floors", "azm", "exercisedays"]
            for (var i = 0; i < kinds.length; i++) {
                verify(sources.all.indexOf(kinds[i]) > sources.all.indexOf("distance"), kinds[i])
                verify(sources.isSource(kinds[i]))
            }
            compare(sources.name("calories"), "Calories")
            compare(sources.name("floors"), "Floors")
            compare(sources.name("azm"), "Active Zone Minutes")
            compare(sources.name("exercisedays"), "Exercise days")
            // nothing shown: nothing made, nothing read
            compare(SensorlogdFixture.alive, 0)
            compare(SensorlogdFixture.reads, 0)
        }

        function test_02_day_numbers() {
            today({ energyKcal: 1234.4, floors: 7, azm: 30, steps: 5000 })
            show("calories")
            show("floors")
            show("azm")
            tryVerify(function () { return sources.demand.azm === true && sources.info("azm").text === "30" })
            var d = sources.info("calories")
            var kcal = Number(1234).toLocaleString(Qt.locale(), "f", 0)
            compare(d.type, "ranged")
            compare(d.text, kcal)
            compare(d.short, kcal)
            compare(d.title, "Calories")
            compare(d.icon, "eos-health-energy")
            verify(Math.abs(d.progress - 1234 / 2500) < 1e-9)
            d = sources.info("floors")
            compare(d.text, "7")
            compare(d.icon, "eos-health-floors")
            verify(Math.abs(d.progress - 0.7) < 1e-9)
            d = sources.info("azm")
            compare(d.text, "30")
            compare(d.icon, "eos-health-azm")
            compare(d.progress, 1)
            compare(d.known, true)
            // one read of the day summary for the three
            compare(SensorlogdFixture.alive, 2)
            compare(SensorlogdFixture.reads, 1)
        }

        function test_03_exercise_days() {
            SensorlogdFixture.workouts = [
                workout(23, 7, 30, "Run"),                                    // Monday
                workout(24, 7, 20, "Run"), workout(24, 18, 45, "Bike"),       // Tuesday, twice
                workout(25, 14, 0, "Hike", { endMs: 0, ended: false }),     // still on today
                workout(25, 9, 30, "Swim", { deleted: true }),                // deleted
                workout(22, 10, 60, "Walk")                                   // Sunday of the week before
            ]
            show("exercisedays")
            tryVerify(function () { return sources.demand.exercisedays === true && sources.info("exercisedays").known })
            var d = sources.info("exercisedays")
            compare(d.type, "weighted")
            compare(d.text, "2")
            compare(d.long, "2 of 3 days")
            compare(d.icon, "eos-exercise")
            compare(d.elements.length, 3)
            compare(d.elements.map(function (e) { return e.track }), [false, false, true])
            compare(d.elements[0].color, "")
            // the day summary is not read for it
            compare(SensorlogdFixture.reads, 1)
            // the rules themselves
            compare(C.exerciseDays([]), 0)
            compare(C.exerciseDays(null), 0)
            compare(C.weekStartMs(root.fixedNow.getTime()), at(23, 0))
            compare(C.weekStartMs(at(29, 23, 59)), at(23, 0))
            compare(C.weekStartMs(at(30, 0, 0)), at(30, 0))
            compare(C.exerciseDayElements(5, 3).map(function (e) { return e.track }), [false, false, false])
            compare(C.FIT_GOALS.exercisedays, 3)
            // none yet this week
            SensorlogdFixture.workouts = []
            sources.now = new Date(2026, 10, 30, 8, 0, 0)   // Monday after: a new day reads again
            tryVerify(function () { return sources.info("exercisedays").text === "0" })
            compare(sources.info("exercisedays").elements.map(function (e) { return e.track }), [true, true, true])
        }

        function test_04_reads_once_a_minute() {
            today({ energyKcal: 100, floors: 1, azm: 0 })
            show("calories")
            tryVerify(function () { return sources.info("calories").text === "100" })
            wait(20)
            compare(SensorlogdFixture.reads, 1)
            // the data changed (a step record): not again within the minute
            today({ energyKcal: 150, floors: 1, azm: 0 })
            SensorlogdFixture.changed()
            wait(20)
            compare(SensorlogdFixture.reads, 1)
            compare(sources.info("calories").text, "100")
            // the face's next minute
            sources.now = new Date(root.fixedNow.getTime() + 61000)
            tryCompare(SensorlogdFixture, "reads", 2)
            compare(sources.info("calories").text, "150")
            // no change: the minute reads nothing
            sources.now = new Date(root.fixedNow.getTime() + 125000)
            wait(20)
            compare(SensorlogdFixture.reads, 2)
            // the screen off: a change waits for it; on again, one read
            sources.active = false
            today({ energyKcal: 175, floors: 2, azm: 0 })
            SensorlogdFixture.changed()
            sources.now = new Date(root.fixedNow.getTime() + 300000)
            wait(20)
            compare(SensorlogdFixture.reads, 2)
            compare(sources.info("calories").text, "150", "inactive: the number stays")
            sources.active = true
            tryCompare(SensorlogdFixture, "reads", 3)
            compare(sources.info("calories").text, "175")
            // on again with nothing new: nothing read
            sources.active = false
            sources.active = true
            wait(20)
            compare(SensorlogdFixture.reads, 3)
        }

        function test_05_open() {
            var want = { calories: "energy", floors: "floors", azm: "azm", exercisedays: "exercise" }
            for (var k in want) {
                Backend.confSet("/org/asteroidos/health/ui/open", "")
                sources.open(k, null)
                var request = String(Backend.confGet("/org/asteroidos/health/ui/open"))
                verify(request.indexOf(want[k] + "@") === 0, k + ": " + request)
            }
            compare(desktop.launched, ["asteroid-health", "asteroid-health", "asteroid-health", "asteroid-health"])
        }

        function test_06_always_on() {
            today({ energyKcal: 800, floors: 3, azm: 12 })
            SensorlogdFixture.workouts = [workout(24, 7, 20, "Run")]
            show("calories")
            show("floors")
            show("azm")
            show("exercisedays")
            tryVerify(function () { return sources.info("exercisedays").text === "1" })
            sources.active = false
            sources.ambient = true
            sources.hubDrawn = true
            // the day's numbers change between the hub's pictures: '--' there; the week's days stay until midnight
            compare(sources.info("calories").text, "--")
            compare(sources.info("calories").icon, "")
            compare(sources.info("floors").text, "--")
            compare(sources.info("azm").text, "--")
            compare(sources.info("exercisedays").text, "1")
            // where the AP draws the always-on screen, the numbers as they were
            sources.hubDrawn = false
            compare(sources.info("calories").text, "800")
        }

        function test_07_not_read_yet() {
            // the reader is made with the slot and reads at once: a day without a summary is 0
            show("floors")
            tryVerify(function () { return sources.demand.floors === true && sources.info("floors").known })
            compare(sources.info("floors").type, "ranged")
            compare(sources.info("floors").text, "0")
            compare(C.FIT_GOALS.calories, 2500)
            compare(C.FIT_GOALS.floors, 10)
            compare(C.FIT_GOALS.azm, 22)
        }

        // the four in round slots (the bulb), for the eye
        function test_08_shot() {
            today({ energyKcal: 1234, floors: 7, azm: 30 })
            SensorlogdFixture.workouts = [workout(23, 7, 30, "Run"), workout(24, 18, 45, "Bike")]
            face.visible = true
            sources.attach(face, "file:///tmp/m4wo10.qml")
            tryVerify(function () { return sources.demand.exercisedays === true && sources.demand.calories === true }, 2000)
            wait(200)
            face.grabToImage(function (r) { r.saveToFile("/tmp/m4wo10-shots/complications.png") })
            wait(100)
            var views = sources.slotsOf(face, [], true)
            compare(views.length, 4)
            face.visible = false
            for (var i = 0; i < views.length; i++)
                for (var c = views[i].children.length - 1; c >= 0; c--)
                    if (views[i].children[c].objectName === "eosComplicationView")
                        views[i].children[c].destroy()
            wait(50)
        }
    }
}
