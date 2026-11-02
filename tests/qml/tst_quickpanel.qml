/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel's modes (src/qml/quickpanel), as the stock quick
 * settings (STOCK-MODES.md), on the mocks of tests/qml/mocks and a stand-in
 * for the modes engine (modes.h): the tiles in the panel (and in a panel
 * saved before they existed), Bedtime, Theater, Battery saver and the
 * first Do Not Disturb asking first with "Don't show again", off at once,
 * "Bedtime mode off", the always-on and brightness tiles greyed out while a
 * mode holds them, Battery saver greyed out on the charger, and "Starting
 * Bedtime mode…". Screenshots (384x384, round) go to the runner's shots
 * directory as quickpanel-*.png. Run by modes/tools/run-launcher-qml.sh
 * (qemu-aarch64, offscreen, software Qt Quick), which stages the panel's
 * QML as the launcher's qrc lays it out (module LauncherQml).
 */

import QtQuick
import QtTest
import Nemo.Configuration
import LauncherTest
import LauncherQml

Item {
    id: root
    width: 384
    height: 384

    // what MainScreen gives the quick panel
    ConfigurationValue {
        id: alwaysOnDisplay
        key: "/org/asteroidos/settings/always-on-display"
        defaultValue: true
    }
    Item { id: grid; property int currentVerticalPos: 0 }
    property var volumeControl: null

    // the modes engine's API (modes.h), its rules as modescore.h
    QtObject {
        id: modes
        property bool bedtime: false
        property bool theater: false
        property bool batterySaver: false
        property bool extraDim: false
        property bool charging: false
        readonly property bool alwaysOnBlocked: bedtime || theater || batterySaver
        readonly property string alwaysOnHolder: theater ? "theater" : bedtime ? "bedtime" : batterySaver ? "battery-saver" : ""
        readonly property string brightnessHolder: bedtime ? "bedtime" : extraDim ? "extra-dim" : ""
        signal bedtimeStarting()
        function setRestoreValue(setting, value) {}
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Item {
        id: screen
        anchors.fill: parent
        clip: true
        Loader {
            id: loader
            anchors.fill: parent
            active: false
            sourceComponent: Component { QuickPanel { } }
        }
        ModeScreen { id: modeScreen }
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
    }

    TestCase {
        name: "QuickPanelModes"
        when: windowShown

        readonly property string shots: "/tmp/modes-launcher-shots"
        readonly property string sliderKey: "/desktop/asteroid/quickpanel/slider"

        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) {
                var r = find(kids[i], name)
                if (r)
                    return r
            }
            if (item.contentItem && item.contentItem !== item) {
                var c = find(item.contentItem, name)
                if (c)
                    return c
            }
            return null
        }
        function panel() { return loader.item }
        function start() {
            loader.active = false
            loader.active = true
            tryCompare(loader, "status", Loader.Ready)
            wait(200)
        }
        function init() {
            Backend.reset()
            modes.bedtime = false
            modes.theater = false
            modes.batterySaver = false
            modes.extraDim = false
            modes.charging = false
            modeScreen.opacity = 0
            start()
        }
        function findBy(item, pred) {
            if (!item)
                return null
            if (pred(item))
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) {
                var r = findBy(kids[i], pred)
                if (r)
                    return r
            }
            return null
        }
        // the panel's sliding row (pages of three tiles, made as shown)
        function slidingRow() {
            return findBy(panel(), function (o) { return o.hasOwnProperty("rowCount") && o.hasOwnProperty("allToggles") })
        }
        // the row's page with the tile, shown; the tile
        function tile(name) {
            var list = slidingRow()
            verify(list !== null, "the sliding row")
            for (var p = 0; p < list.rowCount; p++) {
                list.positionViewAtIndex(p, ListView.Beginning)
                wait(60)
                var t = findBy(list, function (o) {
                    if (o.objectName !== name)
                        return false
                    var x = o.mapToItem(list, 0, 0).x
                    return x >= -1 && x < list.width
                })
                if (t)
                    return t
            }
            verify(false, name + " in the panel")
            return null
        }
        // where a tile is in the row (its component's place)
        function place(id) {
            return slidingRow().allToggles.indexOf(panel().toggleRegistry[id])
        }
        function tap(item) {
            var p = item.mapToItem(root, item.width / 2, item.height / 2)
            mouseClick(root, p.x, p.y)
            wait(100)
        }
        function dialog() { return find(panel(), "modeDialog") }
        function yes() { tap(find(panel(), "modeDialogYes")); wait(100) }
        function no() { tap(find(panel(), "modeDialogNo")); wait(100) }
        function shot(name) {
            wait(200)
            var img = grabImage(screen)
            img.save(shots + "/" + name + ".png")
        }

        function test_01_tiles_in_the_panel() {
            var ids = ["bedtimeToggle", "dndToggle", "cinemaToggle", "batterySaverToggle", "extraDimToggle", "aodToggle", "brightnessToggle"]
            for (var i = 0; i < ids.length; i++)
                verify(place(ids[i]) >= 0, ids[i] + " in the panel")
            // stock's order: Bedtime, Do Not Disturb, Theater
            verify(place("bedtimeToggle") + 1 === place("dndToggle"))
            verify(place("dndToggle") + 1 === place("cinemaToggle"))
            tile("bedtimeToggle")
            shot("quickpanel-01-modes-off")
            tile("extraDimToggle")
            shot("quickpanel-02-saver-extra-dim-off")
        }

        function test_02_a_panel_saved_before_the_modes() {
            // an older watch's saved row (cinema = Theater now, DND at the end)
            Backend.confSet(sliderKey, ["brightnessToggle", "bluetoothToggle", "hapticsToggle", "wifiToggle", "soundToggle",
                                        "cinemaToggle", "aodToggle", "findPhoneButton", "powerOffToggle", "rebootToggle", "dndToggle"])
            start()
            // Bedtime before Do Not Disturb, Battery saver and Extra dim after Theater
            verify(place("bedtimeToggle") >= 0)
            compare(place("bedtimeToggle") + 1, place("dndToggle"))
            compare(place("cinemaToggle") + 1, place("batterySaverToggle"))
            compare(place("batterySaverToggle") + 1, place("extraDimToggle"))
            compare(place("extraDimToggle") + 1, place("aodToggle"))
        }

        function test_03_bedtime_asks_then_off_at_once() {
            var t = tile("bedtimeToggle")
            verify(!t.checked)
            tap(t)
            verify(dialog().visible)
            compare(dialog().title, "Turn on Bedtime mode?")
            compare(dialog().message, "Watch screen, tilt-to-wake, and touch are turned off. Only alarms and timers will notify you.")
            shot("quickpanel-03-bedtime-dialog")
            yes()
            verify(!dialog().visible)
            verify(modes.bedtime)
            verify(t.checked)
            compare(t.icon, "ios-moon")
            compare(Backend.confGet("/org/asteroidos/modes/ask/bedtime"), undefined)
            // the always-on and brightness tiles: greyed out, always-on shown off
            var aod = tile("aodToggle")
            verify(!aod.enabled && !aod.checked)
            var bright = tile("brightnessToggle")
            verify(!bright.enabled)
            t = tile("bedtimeToggle")
            shot("quickpanel-04-bedtime-on")
            // off: at once, with "Bedtime mode off"
            tap(t)
            verify(!dialog().visible)
            verify(!modes.bedtime)
            var toast = find(panel(), "modeToast")
            verify(toast.visible)
            compare(toast.text, "Bedtime mode off")
            shot("quickpanel-05-bedtime-off-toast")
            verify(tile("aodToggle").enabled && tile("aodToggle").checked)
            verify(tile("brightnessToggle").enabled)
            t = tile("bedtimeToggle")
            // ✕: nothing
            tap(t)
            no()
            verify(!modes.bedtime)
        }

        function test_04_dont_show_again() {
            var t = tile("theaterToggle")
            tap(t)
            compare(dialog().title, "Turn on Theater mode?")
            compare(dialog().message, "Turns off screen and screen wake gestures, silences alerts.")
            tap(find(panel(), "modeDialogDontShow"))
            verify(dialog().dontShowAgain)
            shot("quickpanel-06-theater-dialog-dont-show")
            yes()
            verify(modes.theater)
            compare(t.icon, "ios-film")
            compare(Backend.confGet("/org/asteroidos/modes/ask/theater"), false)
            tap(t)
            verify(!modes.theater)
            // asked no more
            tap(t)
            verify(!dialog().visible)
            verify(modes.theater)
        }

        function test_05_battery_saver_and_the_charger() {
            var t = tile("batterySaverToggle")
            verify(t.enabled)
            tap(t)
            compare(dialog().title, "Turn on Battery Saver mode?")
            compare(dialog().message, "Turns off Always-on-screen and Tilt-to-wake to extend battery life")
            yes()
            verify(modes.batterySaver && t.checked)
            verify(!tile("aodToggle").enabled)
            verify(tile("brightnessToggle").enabled)
            t = tile("batterySaverToggle")
            shot("quickpanel-07-saver-on")
            // on the charger: greyed out (the engine turns it off)
            modes.charging = true
            modes.batterySaver = false
            verify(!t.enabled)
            tap(t)
            verify(!dialog().visible && !modes.batterySaver)
        }

        function test_06_dnd_asks_the_first_time() {
            var t = tile("dndToggle")
            compare(t.icon, "ios-remove-circle-outline")
            tap(t)
            compare(dialog().title, "Turn on Do Not Disturb?")
            compare(dialog().message, "Only alarms and timers will notify you.")
            shot("quickpanel-08-dnd-dialog")
            tap(find(panel(), "modeDialogDontShow"))
            yes()
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), true)
            compare(t.icon, "ios-remove-circle")
            tap(t)
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), false)
            tap(t)
            verify(!dialog().visible)
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), true)
        }

        function test_07_extra_dim_at_once() {
            var t = tile("extraDimToggle")
            tap(t)
            verify(!dialog().visible)
            verify(modes.extraDim && t.checked)
            verify(!tile("brightnessToggle").enabled)
            verify(tile("aodToggle").enabled)
            t = tile("extraDimToggle")
            shot("quickpanel-09-extra-dim-on")
            tap(t)
            verify(!modes.extraDim)
        }

        function test_08_starting_bedtime() {
            modes.bedtimeStarting()
            wait(300)
            verify(modeScreen.visible)
            compare(find(modeScreen, "bedtimeStarting").text, "Starting Bedtime mode…")
            shot("quickpanel-10-starting-bedtime")
            tryCompare(modeScreen, "visible", false, 4000)
        }
    }
}
