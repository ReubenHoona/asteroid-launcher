/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick panel's modes (src/qml/quickpanel), as the stock quick settings
 * (STOCK-MODES.md), on the mocks of tests/qml/mocks and a stand-in for the modes
 * engine (modes.h): the tiles in stock's order, Bedtime, Theater, Battery saver and
 * the first Do Not Disturb asking first with "Don't show again", off at once, the
 * Always-on and Extra dim tiles (not in stock's list: a list that names them) greyed
 * out while a mode holds them, "Starting Bedtime mode...", and the Flashlight tile
 * opening the Flashlight app. The panel's layout, look, captions, pill and long
 * presses are tst_qspanel.qml's (W2-launcher-quick-settings). Screenshots go to the
 * runner's shots directory as quickpanel-*.png. Run by
 * pkg/W2-launcher-quick-settings/run.sh (qemu-aarch64, offscreen, software Qt Quick),
 * which stages the panel's QML as the launcher's qrc lays it out (module LauncherQml).
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
    Item {
        id: grid
        property int currentVerticalPos: 0
        property real topTrayFraction: 0
        property bool trayMode: true
        property bool handingOver: false
        property int rotaryExitEdge: 1
        function crownScrolled(d) { return true }
        function closeTray(reason) { return true }
        function moveTo(x, y) {}
        function animateTo(x, y) {}
    }
    property var volumeControl: null
    property var touchLock: null

    // the modes engine's API (modes.h), its rules as modescore.h
    QtObject {
        id: modes
        property bool bedtime: false
        property bool theater: false
        property bool batterySaver: false
        property bool extraDim: false
        property bool charging: false
        property bool autoSaverOn: false
        property int autoSaverOnLevel: 15
        readonly property bool alwaysOnBlocked: bedtime || theater || batterySaver
        readonly property string alwaysOnHolder: theater ? "theater" : bedtime ? "bedtime" : batterySaver ? "battery-saver" : ""
        readonly property string brightnessHolder: bedtime ? "bedtime" : extraDim ? "extra-dim" : ""
        signal bedtimeStarting()
        signal bedtimeSkipped()
        signal bedtimeEnding()
        signal transitionCancelled()
        signal theaterStarting()
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
        readonly property string tilesKey: "/desktop/asteroid/quickpanel/tiles"

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
            panel().tapDebounce = 0
        }
        function init() {
            Backend.reset()
            Backend.replies["org.asteroidos.btsyncd.Notifications.FindingPhone"] = false
            Backend.confSet("/desktop/asteroid/pre-mute-level", 0)
            modes.bedtime = false
            modes.theater = false
            modes.batterySaver = false
            modes.extraDim = false
            modes.charging = false
            modeScreen.opacity = 0
            alwaysOnDisplay.value = true
            start()
        }
        function list() { return find(panel(), "qsList") }
        // the tile, scrolled to the middle of the screen
        function tile(name) {
            var s = find(panel(), "qsSlot-" + name)
            verify(s !== null && s.item !== null, name + " in the panel")
            var l = list()
            var y = s.item.mapToItem(l.contentItem, 0, 0).y + s.item.height / 2
            l.contentY = Math.max(0, Math.min(l.contentHeight - l.height, y - l.height / 2))
            wait(60)
            return s.item
        }
        function place(id) { return panel().tileIds.indexOf(id) }
        function tap(item) {
            var p = item.mapToItem(root, item.width / 2, item.height / 2)
            mouseClick(root, p.x, p.y)
            wait(100)
        }
        function dialog() { return find(panel(), "modeDialog") }
        function alert() { return dialog().alert }
        // a long message scrolls: the buttons are at the end of the list
        function press(button) {
            wait(250)
            var f = alert().flickable
            f.contentY = Math.max(-f.topMargin, f.contentHeight + f.bottomMargin - f.height)
            wait(80)
            tap(button)
            wait(250)
        }
        function yes() { press(alert().confirmButton) }
        function no() { press(alert().dismissButton) }
        function shot(name) {
            wait(200)
            var img = grabImage(screen)
            img.save(shots + "/" + name + ".png")
        }

        function test_01_tiles_in_stock_order() {
            // stock's order: Bedtime, Do Not Disturb, Theater, then Airplane mode
            verify(place("bedtimeToggle") >= 0)
            compare(place("bedtimeToggle") + 1, place("dndToggle"))
            compare(place("dndToggle") + 1, place("cinemaToggle"))
            compare(place("cinemaToggle") + 1, place("airplaneToggle"))
            // the Flashlight tile is in the panel by default
            verify(place("flashlightButton") >= 0)
            // Battery saver is the battery button, first: no tile of its own
            compare(place("battery"), 0)
            compare(place("batterySaverToggle"), -1)
            tile("bedtimeToggle")
            shot("quickpanel-01-modes-off")
        }

        function test_02_bedtime_asks_then_off_at_once() {
            // the Always-on tile is not in stock's list: a list that names it
            Backend.confSet(tilesKey, ["bedtimeToggle", "aodToggle", "extraDimToggle"])
            start()
            var t = tile("bedtimeToggle")
            verify(!t.checked)
            tap(t)
            verify(dialog().shown)
            compare(alert().title, "Turn on Bedtime mode?")
            shot("quickpanel-02-bedtime-dialog")
            yes()
            verify(modes.bedtime)
            verify(t.checked)
            compare(t.icon, "ios-moon")
            compare(Backend.confGet("/org/asteroidos/modes/ask/bedtime"), undefined)
            // the always-on tile: greyed out, shown off
            var aod = tile("aodToggle")
            verify(!aod.enabled && !aod.checked)
            t = tile("bedtimeToggle")
            shot("quickpanel-03-bedtime-on")
            // off: at once, no dialog; the exit screen is ModeScreen's (modes-dnd-07), no toast
            tap(t)
            verify(!dialog().shown)
            verify(!modes.bedtime)
            verify(find(panel(), "qsCaption").opacity === 0)
            verify(tile("aodToggle").enabled && tile("aodToggle").checked)
            t = tile("bedtimeToggle")
            // the dismiss button: nothing
            tap(t)
            no()
            verify(!modes.bedtime)
        }

        function test_03_dont_show_again() {
            var t = tile("cinemaToggle")
            tap(t)
            compare(alert().title, "Turn on Theater mode?")
            var cb = find(alert(), "modeDialogDontShow")
            wait(250)
            cb.clicked(null)
            wait(60)
            verify(dialog().dontShowAgain)
            shot("quickpanel-04-theater-dialog-dont-show")
            yes()
            verify(modes.theater)
            compare(t.icon, "ios-film")
            compare(Backend.confGet("/org/asteroidos/modes/ask/theater"), false)
            tap(t)
            verify(!modes.theater)
            wait(150)
            // asked no more
            tap(t)
            verify(!dialog().shown)
            verify(modes.theater)
        }

        function test_04_battery_saver_and_the_charger() {
            var t = tile("battery")
            verify(t.enabled)
            tap(t)
            compare(alert().title, "Turn on Battery Saver mode?")
            yes()
            verify(modes.batterySaver && t.checked)
            verify(modes.alwaysOnBlocked)
            shot("quickpanel-05-saver-on")
            // on the charger: greyed out (the engine turns it off)
            modes.charging = true
            modes.batterySaver = false
            verify(!t.enabled)
            tap(t)
            verify(!dialog().shown && !modes.batterySaver)
        }

        function test_05_dnd_asks_the_first_time() {
            var t = tile("dndToggle")
            compare(t.icon, "ios-remove-circle-outline")
            tap(t)
            compare(alert().title, "Turn on Do Not Disturb?")
            shot("quickpanel-06-dnd-dialog")
            var cb = find(alert(), "modeDialogDontShow")
            wait(250)
            cb.clicked(null)
            yes()
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), true)
            compare(t.icon, "ios-remove-circle")
            wait(150)
            tap(t)
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), false)
            wait(150)
            tap(t)
            verify(!dialog().shown)
            compare(Backend.confGet("/org/asteroidos/notifications/do-not-disturb"), true)
        }

        function test_06_extra_dim_at_once() {
            Backend.confSet(tilesKey, ["extraDimToggle", "aodToggle"])
            start()
            var t = tile("extraDimToggle")
            tap(t)
            verify(!dialog().shown)
            verify(modes.extraDim && t.checked)
            verify(tile("aodToggle").enabled)
            tap(t)
            verify(!modes.extraDim)
        }

        function test_07_starting_bedtime() {
            modes.bedtimeStarting()
            wait(300)
            verify(modeScreen.visible)
            compare(find(modeScreen, "bedtimeStarting").text, "Starting Bedtime mode…")
            shot("quickpanel-07-starting-bedtime")
            // 1000 in, 2000 held, 1000 out, 1000 black (modes-dnd-08)
            tryCompare(modeScreen, "visible", false, 6000)
        }

        // the Flashlight tile, in the panel by default as stock's, opens the Flashlight app
        function test_08_flashlight_tile() {
            var t = tile("flashlightButton")
            compare(t.icon, "gm-flashlight-on")
            verify(!t.checkable)
            shot("quickpanel-08-flashlight-tile")
            tap(t)
            var c = Backend.find("launcher", "launchApp")
            verify(c !== null, "the app started")
            compare(c.args[0], "asteroid-flashlight")
        }
    }
}
