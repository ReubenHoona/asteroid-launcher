// SPDX-License-Identifier: BSD-3-Clause
//
// M4 WO-10: the Last activity tile (src/qml/tiles/LastActivityTile.qml, tiles-individual-24; stock
// TileLastActivityService: zpj.java:451-505, acbe.java:1567-1650, tile_last_activity_preview.xml) on the repo
// mocks: asteroid-sensorlogd's WorkoutLoader is the double of tests/qml/mocks/org/asteroid/sensorlogd on
// SensorlogdFixture's invented workouts (empty, one, many, a workout still on, a deleted one), the wall clock a
// fixed one (Wednesday 25 November 2026, 15:00 local). The title is the exercise, the card the day ("Today",
// "Yesterday", the weekday in this week from Monday, else the date) over the main number (the distance in km
// with two decimals, else the active time), the edge button "Start" starts that exercise again (the Exercise
// app's start request) or opens the app; nothing reads while the tile is off screen or a picture.
// Shots in /tmp/m4wo10-shots, with the stock preview drawn beside them when STOCK_SVG names it.
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

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: desktop
        property var launched: []
        function openTilesEditor(addList) {}
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }
    // the Exercise app's ongoing activity while a workout runs (the launcher's ongoing registry)
    QtObject {
        id: ongoingRegistry
        property var entries: []
    }

    // the compositor of a watch showing the home screen, awake (TileBase.awake; the repo mock has no homeActive)
    QtObject {
        id: awakeCompositor
        property bool homeActive: true
        property bool displayAmbient: false
        property bool displayDimmed: false
    }

    Rectangle { anchors.fill: parent; color: "black" }

    // Wednesday 25 November 2026, 15:00 local
    readonly property real fixedNow: new Date(2026, 10, 25, 15, 0, 0).getTime()
    function at(d, h, m) { return new Date(2026, 10, d, h, m || 0, 0).getTime() }
    function run(d, h, mins, type, metres, extra) {
        var w = { id: d * 100 + h, startMs: at(d, h), endMs: at(d, h) + mins * 60000, activeS: mins * 60, type: type,
                  distanceM: metres, kcal: mins * 8, azm: mins, ended: true }
        for (var k in extra)
            w[k] = extra[k]
        return w
    }

    // the Exercise app's start request (dconf, the repo double's Backend.conf)
    function startRequest() {
        var v = Backend.confGet("/org/asteroidos/exercise/start-request")
        return v === undefined ? "" : String(v)
    }

    Component {
        id: tileComp
        LastActivityTile { width: 384; height: 384 }
    }
    property var tile: null

    TestCase {
        name: "LastActivity"
        when: windowShown

        function initTestCase() { Lipstick.compositor = awakeCompositor }

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
        function make(workouts) {
            SensorlogdFixture.reset()
            SensorlogdFixture.workouts = workouts
            desktop.launched = []
            Backend.confSet("/org/asteroidos/exercise/start-request", "")
            ongoingRegistry.entries = []
            var now = testRoot.fixedNow
            testRoot.tile = tileComp.createObject(testRoot)
            testRoot.tile.clock = function () { return now }
            tryVerify(function () { return SensorlogdFixture.reads > 0 }, 2000, "the tile read health.db")
            return testRoot.tile
        }
        function cleanup() {
            if (testRoot.tile)
                testRoot.tile.destroy()
            testRoot.tile = null
            wait(0)
        }
        function shot(name) {
            testRoot.tile.grabToImage(function (r) { r.saveToFile("/tmp/m4wo10-shots/" + name + ".png") })
            wait(80)
        }
        function chip() { return testRoot.tile.chip }

        function test_01_empty() {
            var t = make([])
            compare(t.title, "Exercise")
            verify(find(t, "lastActivityEmpty").visible)
            compare(find(t, "lastActivityEmpty").text, "Track an exercise to see your achievements!")
            verify(!find(t, "lastActivityData").visible)
            compare(t.chipText, "Start")
            colorIs(t.chipColor, "#A8C7FA")
            colorIs(t.chipContentColor, "#041E49")
            colorIs(find(t, "lastActivityCard").containerColor, "#29303D")
            shot("lastactivity-empty")
            // stock: the Exercise app's start screen, no exercise asked for
            t.chipClicked()
            compare(desktop.launched, ["asteroid-exercise"])
            compare(testRoot.startRequest(), "")
        }

        function colorIs(c, want) {
            var w = Qt.color(want)
            verify(Math.abs(c.r - w.r) < 0.01 && Math.abs(c.g - w.g) < 0.01 && Math.abs(c.b - w.b) < 0.01, c + " is not " + want)
        }

        function test_02_today_distance() {
            var t = make([run(25, 7, 40, "Run", 5200)])
            compare(t.title, "Run")
            verify(find(t, "lastActivityData").visible)
            verify(!find(t, "lastActivityEmpty").visible)
            compare(find(t, "lastActivityDay").text, "Today")
            compare(find(t, "lastActivityValue").text, "5.20")
            compare(find(t, "lastActivityUnit").text, "km")
            verify(find(t, "lastActivityUnit").visible)
            colorIs(find(t, "lastActivityDay").color, "#C2C6D2")
            colorIs(find(t, "lastActivityUnit").color, "#EBF1FF")
            // stock's three lines: the day, the number, the unit, centred, inside the card
            var card = find(t, "lastActivityCard")
            var v = find(t, "lastActivityValue"), u = find(t, "lastActivityUnit"), d = find(t, "lastActivityDay")
            verify(d.mapToItem(card, 0, d.height).y <= v.mapToItem(card, 0, 0).y + 1)
            verify(v.mapToItem(card, 0, v.height).y <= u.mapToItem(card, 0, 0).y + 1)
            verify(d.mapToItem(card, 0, 0).y >= 0 && u.mapToItem(card, 0, u.height).y <= card.height)
            compare(Math.round(v.mapToItem(card, v.width / 2, 0).x), Math.round(card.width / 2))
            verify(card.height <= 176 && card.height > 120, "a stadium up to 88 dp: " + card.height)
            compare(card.radius, card.height / 2)
            shot("lastactivity-run")
            // "Start": that exercise again (the Exercise app's start request, as Quick start)
            t.chipClicked()
            compare(testRoot.startRequest(), "Run@" + testRoot.fixedNow)
            compare(desktop.launched, ["asteroid-exercise"])
            // a tap on the card opens the app
            mouseClick(card, card.width / 2, card.height / 2)
            compare(desktop.launched, ["asteroid-exercise", "asteroid-exercise"])
        }

        function test_03_days() {
            var cases = [
                [24, "Yesterday"],          // Tuesday
                [23, "Monday"],             // this week's Monday: its name
                [22, "22 Nov 2026"],        // Sunday of the week before: the date
                [2, "2 Nov 2026"]
            ]
            for (var i = 0; i < cases.length; i++) {
                var t = make([run(cases[i][0], 18, 30, "Walk", 2100)])
                compare(find(t, "lastActivityDay").text, cases[i][1], "day " + cases[i][0])
                cleanup()
            }
            // the rule itself, against the clock (a workout that began just after midnight, one before)
            compare(TC.activityDay(at(25, 0, 1), testRoot.fixedNow), "today")
            compare(TC.activityDay(at(24, 23, 59), testRoot.fixedNow), "yesterday")
            compare(TC.activityDay(at(23, 0, 0), testRoot.fixedNow), "weekday")
            compare(TC.activityDay(at(22, 23, 59), testRoot.fixedNow), "date")
            compare(TC.weekStartMs(testRoot.fixedNow), at(23, 0, 0))
        }

        function test_04_time_without_distance() {
            var t = make([run(25, 6, 62, "Yoga", 0, { activeS: 3725 })])
            compare(t.title, "Yoga")
            compare(find(t, "lastActivityValue").text, "1:02:05")
            verify(!find(t, "lastActivityUnit").visible)
            shot("lastactivity-yoga")
            compare(TC.clockText(59), "0:59")
            compare(TC.clockText(600), "10:00")
            compare(TC.clockText(3600), "1:00:00")
            // miles where the locale's measurement system is not metric
            var s = TC.lastActivity(run(25, 7, 40, "Run", 5200), testRoot.fixedNow, true)
            compare(s.unit, "mi")
            verify(Math.abs(s.value - 5200 / 1609.344) < 1e-9)
            compare(TC.lastActivity({}, testRoot.fixedNow, false).valid, false)
            compare(TC.lastActivity(null, testRoot.fixedNow, false).valid, false)
        }

        function test_05_many_and_one_on() {
            // the newest that ended is shown: a workout still on (the newest) is skipped, a deleted one is not there
            var t = make([run(20, 9, 30, "Swim", 1000), run(24, 18, 45, "Bike", 18000),
                          run(25, 14, 0, "Hike", 0, { endMs: 0, activeS: 0, ended: false }),
                          run(25, 12, 20, "Run", 3000, { deleted: true })])
            compare(t.title, "Bike")
            compare(find(t, "lastActivityDay").text, "Yesterday")
            compare(find(t, "lastActivityValue").text, "18.00")
            // while the workout is on, "Start" opens the app on it: no start request
            ongoingRegistry.entries = [{ app: "asteroid-exercise", status: "Hike" }]
            t.chipClicked()
            compare(testRoot.startRequest(), "")
            compare(desktop.launched, ["asteroid-exercise"])
            ongoingRegistry.entries = []
            t.chipClicked()
            compare(testRoot.startRequest(), "Bike@" + testRoot.fixedNow)
        }

        function test_06_follows_health_db() {
            var t = make([])
            compare(t.title, "Exercise")
            // sensorlogd wrote health.db (a workout ended): the tile reads again
            SensorlogdFixture.workouts = [run(25, 13, 25, "Walk", 2400)]
            SensorlogdFixture.changed()
            tryCompare(t, "title", "Walk")
            compare(find(t, "lastActivityValue").text, "2.40")
            // an unknown type: its key as the name, "Start" opens the app only
            SensorlogdFixture.workouts = [run(25, 14, 10, "Unicycle", 0)]
            SensorlogdFixture.changed()
            tryCompare(t, "title", "Unicycle")
            t.chipClicked()
            compare(testRoot.startRequest(), "")
        }

        function test_07_battery() {
            var t = make([run(25, 7, 40, "Run", 5200)])
            compare(SensorlogdFixture.alive, 1)
            // off screen: the reader goes, nothing is read
            t.visible = false
            tryCompare(SensorlogdFixture, "alive", 0)
            var reads = SensorlogdFixture.reads
            SensorlogdFixture.changed()
            wait(50)
            compare(SensorlogdFixture.reads, reads)
            // on screen again: one reader, read once
            t.visible = true
            tryCompare(SensorlogdFixture, "alive", 1)
            tryVerify(function () { return SensorlogdFixture.reads === reads + 1 })
            compare(t.title, "Run")
            cleanup()
            // a picture (the tiles editor's add list) reads nothing
            SensorlogdFixture.reset()
            var now2 = testRoot.fixedNow
            testRoot.tile = tileComp.createObject(testRoot, { preview: true })
            verify(testRoot.tile !== null)
            testRoot.tile.clock = function () { return now2 }
            wait(100)
            compare(SensorlogdFixture.alive, 0)
            compare(SensorlogdFixture.reads, 0)
            compare(testRoot.tile.title, "Exercise")
        }

        // the tile beside the stock preview (tile_last_activity_preview.xml drawn from its vector), for the eye
        function test_08_beside_stock() {
            var t = make([run(24, 18, 30, "Run", 5800)])
            shot("lastactivity-yesterday")
            var svg = Qt.resolvedUrl("file:///tmp/m4wo10-stock/tile_last_activity_preview.svg")
            var img = Qt.createQmlObject('import QtQuick; Image { width: 384; height: 384; sourceSize.width: 384; sourceSize.height: 384 }', testRoot)
            img.source = svg
            tryVerify(function () { return img.status !== Image.Loading }, 3000)
            if (img.status === Image.Ready) {
                img.grabToImage(function (r) { r.saveToFile("/tmp/m4wo10-shots/stock-last-activity.png") })
                wait(80)
            }
            img.destroy()
        }
    }
}
