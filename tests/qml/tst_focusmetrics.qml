// Copyright (C) 2026 eos
// SPDX-License-Identifier: BSD-3-Clause
//
// R5 E-17 and E-18: the Focus Metrics tile (src/qml/tiles/FocusMetricsTile.qml; stock TileFocusMetricsService:
// xly.java b(), ync.java a(), tpr.java, zaq.java, aahn.java) and the Main goal tile following the main goal's type
// (src/qml/tiles/StepsTile.qml; stock PrimaryGoalType, asteroid-sensorlogd metrics/goals.h), on the repo mocks:
// asteroid-sensorlogd's loaders read SensorlogdFixture's invented days (cardio load, summaries, the last night), dconf
// is Backend.conf. Shots in /tmp/r5fu-shots.
// MODE=tiles (the tree as its qrc lays it out as module LauncherQml, the repo mocks).
import QtQuick
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick
import org.asteroid.sensorlogd
import LauncherTest
import LauncherQml
import "LauncherQml/tiles/tilecontent.js" as TC

Item {
    id: testRoot
    width: 384; height: 384

    QtObject { id: localeManager; property string changesObserver: ""; property int localeRevision: 0 }
    QtObject {
        id: desktop
        property var launched: []
        function openTilesEditor(addList) {}
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }
    QtObject {
        id: awakeCompositor
        property bool homeActive: true
        property bool displayAmbient: false
        property bool displayDimmed: false
    }
    Rectangle { anchors.fill: parent; color: "black" }

    // Wednesday 25 November 2026, 15:00 local
    readonly property real fixedNow: new Date(2026, 10, 25, 15, 0, 0).getTime()
    function today() { return SensorlogdFixture.dayKey(new Date(fixedNow)) }

    Component { id: focusComp; FocusMetricsTile { width: 384; height: 384 } }
    Component { id: stepsComp; StepsTile { width: 384; height: 384 } }
    property var tile: null

    TestCase {
        name: "FocusMetrics"
        when: windowShown

        function initTestCase() { Lipstick.compositor = awakeCompositor }
        function init() {
            Backend.reset()
            SensorlogdFixture.reset()
            desktop.launched = []
        }
        function cleanup() {
            if (testRoot.tile)
                testRoot.tile.destroy()
            testRoot.tile = null
            wait(0)
        }
        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            for (var i = 0; i < item.children.length; i++) {
                var r = find(item.children[i], name)
                if (r)
                    return r
            }
            return null
        }
        function make(comp) {
            var now = testRoot.fixedNow
            testRoot.tile = comp.createObject(testRoot, { clock: function () { return now } })
            wait(50)
            return testRoot.tile
        }
        function shot(name) {
            var t = testRoot.tile
            // the rings' progress animation (a spring, under a second) first
            wait(1200)
            t.grabToImage(function (r) { r.saveToFile("/tmp/r5fu-shots/" + name + ".png") })
            wait(80)
        }
        function cardio(load, high) {
            var c = {}
            c[today()] = { load: load, hasTarget: high > 0, low: Math.round(high * 0.6), high: high, state: "in", week: [] }
            SensorlogdFixture.cardio = c
        }

        // ---- the rules
        function test_01_rules() {
            var c = TC.focusCardio({ load: 45, hasTarget: true, high: 52 })
            compare(c.known, true)
            compare(c.percent, 87)
            compare(c.load, 45)
            fuzzyCompare(c.ratio, 45 / 52, 1e-9)
            compare(TC.focusCardio({ load: 70, hasTarget: true, high: 52 }).ratio, 1, "at most full")
            compare(TC.focusCardio({ load: 70, hasTarget: true, high: 52 }).percent, 135)
            compare(TC.focusCardio({ load: 12, hasTarget: false, high: 0 }).known, false)
            compare(TC.focusCardio(null).known, false)
            compare(TC.sleepWord(95), "excellent")
            compare(TC.sleepWord(90), "excellent")
            compare(TC.sleepWord(83), "good")
            compare(TC.sleepWord(79), "fair")
            compare(TC.sleepWord(60), "fair")
            compare(TC.sleepWord(59), "poor")
            compare(TC.sleepWord(-1), "")
            var s = TC.focusSleep({ valid: true, main: { asleepMin: 420, startMs: 0, endMs: 1 }, goalMin: 480, score: 83 })
            compare(s.valid, true)
            compare(s.score, 83)
            compare(s.word, "good")
            fuzzyCompare(s.ratio, 420 / 480, 1e-9)
            compare(TC.focusSleep({}).valid, false)
            // the main goal's type, target and value
            compare(TC.mainGoalType("floors"), "floors")
            compare(TC.mainGoalType("swimming"), "steps")
            compare(TC.mainGoalType(undefined), "steps")
            compare(TC.mainGoalTarget("calories", 0), 2000)
            compare(TC.mainGoalTarget("distance", -1), 8047)
            compare(TC.mainGoalTarget("azm", 30), 30)
            compare(TC.mainGoalValue("calories", { energyKcal: 1234.6 }, 99), 1234.6)
            compare(TC.mainGoalValue("steps", { steps: 5 }, 99), 99)
            compare(TC.mainGoalNumber("distance", 4023, true, Qt.locale("en_GB")), "2.5")
            compare(TC.mainGoalNumber("distance", 8047, false, Qt.locale("en_GB")), "8.05")
            compare(TC.mainGoalNumber("calories", 1234.6, false, Qt.locale("en_GB")), "1,235")
        }

        // ---- Focus Metrics
        function test_02_cards() {
            cardio(45, 52)
            SensorlogdFixture.night = { valid: true, main: { asleepMin: 420, startMs: testRoot.fixedNow - 9 * 3600000,
                                                              endMs: testRoot.fixedNow - 2 * 3600000 }, goalMin: 480, score: 83 }
            var t = make(focusComp)
            tryVerify(function () { return SensorlogdFixture.reads > 0 })
            compare(t.title, "Focus Metrics")
            compare(t.chipText, "More")
            colorIs(t.chipColor, Theme.color.secondaryContainer)
            compare(find(t, "focusCardioValue").text, "87%")
            compare(find(t, "focusCardioSecond").text, "+45")
            fuzzyCompare(find(t, "focusCardioRing").progress, 45 / 52, 1e-6)
            compare(find(t, "focusStepsValue").text, "0")
            compare(find(t, "focusStepsSecond").text, "Steps")
            compare(find(t, "focusSleepValue").text, "83")
            compare(find(t, "focusSleepSecond").text, "Good")
            fuzzyCompare(find(t, "focusSleepRing").progress, 420 / 480, 1e-6)
            // the three cards side by side inside the body
            var cards = [find(t, "focusCardio"), find(t, "focusSteps"), find(t, "focusSleep")]
            for (var i = 0; i < 3; i++) {
                var p = cards[i].mapToItem(t, 0, 0)
                verify(p.x >= 0 && p.x + cards[i].width <= 384, "card " + i + " inside")
                if (i > 0)
                    verify(p.x >= cards[i - 1].mapToItem(t, 0, 0).x + cards[i - 1].width, "card " + i + " after the one before")
            }
            shot("e17-focus-metrics")
            // health.db changes: read again
            cardio(20, 52)
            SensorlogdFixture.changed()
            tryCompare(find(t, "focusCardioValue"), "text", "38%")
        }

        function test_03_empty() {
            var t = make(focusComp)
            tryVerify(function () { return SensorlogdFixture.reads > 0 })
            compare(find(t, "focusCardioValue").text, "- -")
            compare(find(t, "focusCardioSecond").text, "")
            compare(find(t, "focusSleepValue").text, "- -")
            compare(find(t, "focusSleepSecond").text, "No data")
            compare(find(t, "focusSleepRing").progress, 0)
            shot("e17-focus-metrics-empty")
        }

        function test_04_taps() {
            var t = make(focusComp)
            var pages = [["focusCardio", "cardioload@"], ["focusSteps", "steps@"], ["focusSleep", "sleep@"]]
            for (var i = 0; i < pages.length; i++) {
                desktop.launched = []
                mouseClick(find(t, pages[i][0]))
                compare(desktop.launched, ["asteroid-health"], pages[i][0])
                verify(String(Backend.confGet("/org/asteroidos/health/ui/open")).indexOf(pages[i][1]) === 0, pages[i][0])
            }
            // More: the Health app, no page asked for
            Backend.confSet("/org/asteroidos/health/ui/open", "")
            desktop.launched = []
            t.chipClicked()
            compare(desktop.launched, ["asteroid-health"])
            compare(String(Backend.confGet("/org/asteroidos/health/ui/open")), "")
        }

        function test_05_reads_only_on_screen() {
            var t = make(focusComp)
            tryVerify(function () { return SensorlogdFixture.alive > 0 })
            t.visible = false
            tryCompare(SensorlogdFixture, "alive", 0)
            var r = SensorlogdFixture.reads
            SensorlogdFixture.changed()
            wait(50)
            compare(SensorlogdFixture.reads, r, "nothing read off screen")
            t.visible = true
            tryVerify(function () { return SensorlogdFixture.reads > r })
            cleanup()
            // a preview reads nothing
            var now = testRoot.fixedNow
            testRoot.tile = focusComp.createObject(testRoot, { preview: true, clock: function () { return now } })
            wait(50)
            compare(SensorlogdFixture.alive, 0)
        }

        // ---- Main goal
        function test_06_main_goal_steps_is_as_before() {
            var t = make(stepsComp)
            compare(t.goalType, "steps")
            compare(t.title, "Steps")
            compare(find(t, "goalIcon").name, "ms-directions_walk")
            compare(SensorlogdFixture.alive, 0, "the steps come from the log, no summary read")
        }

        function test_07_main_goal_floors() {
            var s = {}
            s[today()] = { floors: 7, energyKcal: 1500, distanceM: 4023, azm: 12 }
            SensorlogdFixture.summaries = s
            Backend.confSet("/org/asteroidos/health/goals/main", "floors")
            var t = make(stepsComp)
            tryVerify(function () { return find(t, "goalCount").text === "7" })
            compare(t.title, "Floors")
            compare(find(t, "goalPillText").text, "3 left")
            compare(t.bottomValue, "10 floors")
            compare(find(t, "goalIcon").name, "eos-health-floors")
            shot("e18-main-goal-floors")
            desktop.launched = []
            mouseClick(find(t, "goalCard"))
            verify(String(Backend.confGet("/org/asteroidos/health/ui/open")).indexOf("floors@") === 0)
            // the phone changes the type: the tile follows
            Backend.confSet("/org/asteroidos/health/goals/main", "calories")
            Backend.confSet("/org/asteroidos/health/goals/calories", 1200)
            tryCompare(t, "title", "Calories")
            tryCompare(find(t, "goalCount"), "text", Number(1500).toLocaleString(Qt.locale(), "f", 0))
            compare(find(t, "goalPillText").text, Number(300).toLocaleString(Qt.locale(), "f", 0) + " over goal")
            compare(t.bottomValue, Number(1200).toLocaleString(Qt.locale(), "f", 0) + " cal")
            compare(find(t, "goalIcon").name, "eos-health-energy")
        }

        function test_08_main_goal_distance_in_miles() {
            var s = {}
            s[today()] = { distanceM: 4023 }
            SensorlogdFixture.summaries = s
            Backend.confSet("/org/asteroidos/health/goals/main", "distance")
            Backend.confSet("/org/asteroidos/settings/imperial-units", true)
            var t = make(stepsComp)
            tryVerify(function () { return find(t, "goalCount").text === "2.5" })
            compare(t.title, "Distance")
            compare(find(t, "goalPillText").text, "2.5 mi left")
            compare(t.bottomValue, "5 mi")
            Backend.confSet("/org/asteroidos/settings/imperial-units", false)
            tryCompare(find(t, "goalCount"), "text", "4.02")
            compare(t.bottomValue, "8.05 km")
            shot("e18-main-goal-distance")
            // an unknown type is steps
            Backend.confSet("/org/asteroidos/health/goals/main", "swimming")
            tryCompare(t, "goalType", "steps")
            compare(t.title, "Steps")
        }

        function colorIs(c, want) {
            var w = Qt.color(want)
            verify(Math.abs(c.r - w.r) < 0.01 && Math.abs(c.g - w.g) < 0.01 && Math.abs(c.b - w.b) < 0.01, c + " is not " + want)
        }
    }
}
