/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The quick settings panel (W2-launcher-quick-settings) as stock CP3A's: the rules in
 * qs.js (rows of three with the top row count mod 3, the spacers, the edge morph, the
 * battery steps, the status pill, the caption and tap timings), then the real
 * QuickPanel.qml, QuickPanelToggle.qml, ModeDialog.qml and StatusTray.qml on the mocks
 * of tests/qml/mocks: the default tiles and their places, the list opening at its
 * bottom, the crown, the button look and its press morph, the battery button, the
 * Settings long presses, the state captions, the tap debounce, Airplane mode, Mobile,
 * Find My Phone, the status pill and its popups, the remorse regression, the extras
 * that are not in stock's list. Screenshots (384x384, round) go to /tmp/qs-shots. Run
 * by pkg/W2-launcher-quick-settings/run.sh.
 */

import QtQuick
import QtTest
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.utils
import LauncherTest
import LauncherQml
import "LauncherQml/qs.js" as QS

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
    // the panels grid, as far as the panel talks to it
    Item {
        id: grid
        property int currentVerticalPos: 0
        property real topTrayFraction: 0
        property bool trayMode: true
        property bool handingOver: false
        property int rotaryExitEdge: 1
        property var calls: []
        function note(name, args) { var c = calls.slice(); c.push({ name: name, args: args }); calls = c }
        function crownScrolled(d) { note("crownScrolled", [d]); return true }
        function closeTray(reason) { note("closeTray", [reason]); return true }
        function moveTo(x, y) { note("moveTo", [x, y]) }
        function animateTo(x, y) { note("animateTo", [x, y]) }
        function count(name) { var n = 0; for (var i = 0; i < calls.length; i++) if (calls[i].name === name) n++; return n }
    }
    property var volumeControl: volume
    QtObject {
        id: volume
        property int volume: 70
        property int maximumVolume: 100
    }
    property var touchLock: null
    QtObject {
        id: lock
        function lock() { Backend.record("touchlock", "lock", []) }
    }

    // the modes engine's API (modes.h)
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
        name: "QuickSettings"
        when: windowShown

        readonly property string shots: "/tmp/qs-shots"
        readonly property string tilesKey: "/desktop/asteroid/quickpanel/tiles"
        readonly property string reqKey: "/org/asteroidos/settings/ui/open"

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
            if (item.contentItem && item.contentItem !== item) {
                var c = findBy(item.contentItem, pred)
                if (c)
                    return c
            }
            return null
        }
        function find(item, name) { return findBy(item, function (o) { return o.objectName === name }) }
        function panel() { return loader.item }
        function start() {
            loader.active = false
            loader.active = true
            tryCompare(loader, "status", Loader.Ready)
            // a Loader inside a visible item: the panel is shown (the grid shows the one in view)
            wait(150)
        }
        function init() {
            Backend.reset()
            Backend.replies["org.asteroidos.btsyncd.Notifications.FindingPhone"] = false
            Backend.confSet("/desktop/asteroid/pre-mute-level", 0)
            modes.bedtime = false; modes.theater = false; modes.batterySaver = false
            modes.extraDim = false; modes.charging = false; modes.autoSaverOn = false
            volume.volume = 70
            root.touchLock = null
            DeviceSpecs.hasCellular = false
            grid.calls = []
            grid.currentVerticalPos = 0
            grid.topTrayFraction = 0
            grid.rotaryExitEdge = 1
            alwaysOnDisplay.value = true
            start()
            // no tap debounce but where a test is about it
            panel().tapDebounce = 0
        }
        function list() { return find(panel(), "qsList") }
        function slot(id) { return find(panel(), "qsSlot-" + id) }
        function tile(id) {
            var s = slot(id)
            verify(s !== null && s.item !== null, id + " in the panel")
            return s.item
        }
        function has(id) { return slot(id) !== null }
        // the tiles in the list's order (the rows hold each row reversed)
        function ids() { return panel().tileIds.slice() }
        // scroll so the tile is mid-screen, then its centre in the root
        function show(item) {
            var l = list()
            var y = item.mapToItem(l.contentItem, 0, 0).y + item.height / 2
            l.contentY = Math.max(0, Math.min(l.contentHeight - l.height, y - l.height / 2))
            wait(60)
        }
        function centre(item) { return item.mapToItem(root, item.width / 2, item.height / 2) }
        function tap(item) {
            show(item)
            var p = centre(item)
            mouseClick(root, p.x, p.y)
            wait(80)
        }
        function hold(item, ms) {
            show(item)
            var p = centre(item)
            mousePress(root, p.x, p.y)
            wait(ms === undefined ? 520 : ms)
            mouseRelease(root, p.x, p.y)
            wait(80)
        }
        function dialog() { return find(panel(), "modeDialog") }
        function alert() { return dialog().alert }
        function settleDialog() { wait(250) }
        // a long message scrolls (as stock's): the buttons are at the end of the list
        function toEnd(d) {
            var f = d.flickable
            f.contentY = Math.max(-f.topMargin, f.contentHeight + f.bottomMargin - f.height)
            wait(80)
        }
        function pressIn(d, b) { toEnd(d); var p = b.mapToItem(root, b.width / 2, b.height / 2); mouseClick(root, p.x, p.y); wait(250) }
        function yes() { settleDialog(); pressIn(alert(), alert().confirmButton) }
        function no() { settleDialog(); pressIn(alert(), alert().dismissButton) }
        // the caption shows (after the crossfade of a text that follows another)
        function captionIs(text) { tryCompare(find(panel(), "qsCaptionText"), "text", text, 2500) }
        function request() { return Backend.confGet(reqKey) }
        function launched() { var c = Backend.find("launcher", "launchApp"); return c ? c.args[0] : "" }
        function shot(name) {
            wait(200)
            grabImage(screen).save(shots + "/" + name + ".png")
        }
        function rgba(c) { return Qt.rgba(c.r, c.g, c.b, c.a) }
        function colourIs(c, hex, msg) {
            var e = Qt.color(hex)
            verify(Math.abs(c.r - e.r) < 0.01 && Math.abs(c.g - e.g) < 0.01 && Math.abs(c.b - e.b) < 0.01, (msg || "") + " " + c + " != " + hex)
        }
        function near(a, b, tol, msg) { verify(Math.abs(a - b) <= tol, (msg || "") + " " + a + " != " + b) }

        // ---- qs.js ------------------------------------------------------------------

        function test_01_rows_of_three_top_row_count_mod_3() {
            function seq(n) { var a = []; for (var i = 0; i < n; i++) a.push(i); return a }
            // 11 tiles: the top row holds 2, then rows of three; each row reversed
            compare(JSON.stringify(QS.rows(seq(11))), "[[1,0],[4,3,2],[7,6,5],[10,9,8]]")
            compare(JSON.stringify(QS.rows(seq(10))), "[[0],[3,2,1],[6,5,4],[9,8,7]]")
            compare(JSON.stringify(QS.rows(seq(12))), "[[2,1,0],[5,4,3],[8,7,6],[11,10,9]]")
            compare(JSON.stringify(QS.rows(seq(2))), "[[1,0]]")
            compare(JSON.stringify(QS.rows([])), "[]")
            for (var n = 1; n <= 14; n++) {
                var rows = QS.rows(seq(n))
                compare(rows[0].length, n % 3 === 0 ? 3 : n % 3)
                for (var r = 1; r < rows.length; r++)
                    compare(rows[r].length, 3)
            }
        }

        function test_02_spacers_and_padding() {
            // ceil(4.7 % / 7.8 % / 20.8 % of 384) = 19 / 30 / 80
            compare(QS.topSpacer(1, 384), 19)
            compare(QS.topSpacer(2, 384), 30)
            compare(QS.topSpacer(3, 384), 80)
            // rows centred: (384 - n 104 - (n - 1) 8) / 2
            compare(QS.sidePadding(3, 384, 104, 8), 28)
            compare(QS.sidePadding(2, 384, 104, 8), 84)
            compare(QS.sidePadding(1, 384, 104, 8), 140)
            // the status box 21.8 %, its bottom padding 5.2 %
            compare(QS.statusBoxHeight(384), 84)
            compare(QS.statusBottomPadding(384), 20)
        }

        function test_03_edge_morph_numbers() {
            // CubicBezier(0, 0, 0.6, 1)
            compare(QS.bezier(QS.MORPH_EASING, 0), 0)
            compare(QS.bezier(QS.MORPH_EASING, 1), 1)
            near(QS.bezier(QS.MORPH_EASING, 0.5), 0.672, 0.004, "bezier at 0.5")
            var last = -1
            for (var x = 0; x <= 1.0001; x += 0.05) {
                var v = QS.bezier(QS.MORPH_EASING, Math.min(1, x))
                verify(v >= last - 1e-9)
                last = v
            }
            // nothing in the middle
            var mid = QS.morph(140, 104, 384)
            compare(mid.scale, 1); compare(mid.container, 1); compare(mid.content, 1)
            // out of the screen at the top: scale 0.15, container and content alpha 0
            var out = QS.morph(-104, 104, 384)
            compare(out.scale, 0.15); compare(out.container, 0); compare(out.content, 0)
            verify(out.atTop)
            // out at the bottom: scale 0.5, alpha 0.3
            var low = QS.morph(384, 104, 384)
            compare(low.scale, 0.5); near(low.container, 0.3, 1e-9); near(low.content, 0.3, 1e-9)
            verify(!low.atTop)
            // half way in, between the edge value and 1; the alpha rises later than the scale
            var m = QS.morph(0, 104, 384)
            verify(m.scale > 0.15 && m.scale < 1, "scale " + m.scale)
            verify(m.container >= 0 && m.container <= 1)
            verify(m.content >= 0 && m.content <= 1)
            // the alpha reaches 1 (zone 0.05 to 0.5 of the area) before the scale (zone 0 to 1)
            verify(m.container >= (m.scale - 0.15) / 0.85 - 1e-9)
            // the area: element 104 / 384 = 0.2708 high: 0.35 + 0.2 (0.2708 - 0.2) / 0.4 = 0.3854 of the screen
            // the transform ends where the element's inner edge is that far in: top 0 -> x = 0.2708 / 0.3854
            near(QS.bezier(QS.MORPH_EASING, 0.2708 / 0.3854), (m.scale - 0.15) / 0.85, 0.01, "scale at the top row")
            // scale falls as the element goes out
            var prev = 2
            for (var t = 0; t >= -104; t -= 13) {
                var s = QS.morph(t, 104, 384).scale
                verify(s <= prev + 1e-9)
                prev = s
            }
        }

        function test_04_outer_buttons_slide_in() {
            // +-width (1 - scale) in a row of three, half in a row of two, none alone
            compare(QS.slide(0, 3, 104, 0.5), 52)
            compare(QS.slide(1, 3, 104, 0.5), 0)
            compare(QS.slide(2, 3, 104, 0.5), -52)
            compare(QS.slide(0, 2, 104, 0.5), 26)
            compare(QS.slide(1, 2, 104, 0.5), -26)
            compare(QS.slide(0, 1, 104, 0.5), 0)
            compare(QS.slide(0, 3, 104, 1), 0)
        }

        function test_05_status_pill_scale() {
            near(QS.pillScale(0), 0.4, 1e-9)
            near(QS.pillScale(0.2), 0.7, 1e-9)
            near(QS.pillScale(0.4), 1, 1e-9)
            near(QS.pillScale(0.5), 1, 1e-9)
            near(QS.pillScale(0.6), 1, 1e-9)
            near(QS.pillScale(0.8), 0.8, 1e-9)
            near(QS.pillScale(1), 0.6, 1e-9)
        }

        function test_06_battery_steps_and_pill_rules() {
            var cases = [[0, 15], [15, 15], [16, 20], [20, 20], [21, 30], [40, 40], [41, 50], [61, 70], [71, 90], [91, 99], [99, 99], [100, 100]]
            for (var i = 0; i < cases.length; i++)
                compare(QS.batteryStep(cases[i][0]), cases[i][1], "step of " + cases[i][0])
            verify(QS.batteryLow(15)); verify(!QS.batteryLow(16))
            compare(QS.SAVER_CONTAINER, "#FEE170"); compare(QS.SAVER_CONTENT, "#3A3000")
            // icons in stock's order
            compare(JSON.stringify(QS.statusIcons({ phoneConnected: true, btPowered: true, wifiConnected: false, alarmMs: 0 })), '["phone"]')
            compare(JSON.stringify(QS.statusIcons({ phoneConnected: false, btPowered: false, wifiConnected: true, alarmMs: 5 })), '["phoneOff","btOff","wifi","alarm"]')
            // up to four fit; more: three and "+N"
            var s = QS.pillSplit(["a", "b", "c", "d"])
            compare(s.shown.length, 4); compare(s.more, 0)
            s = QS.pillSplit(["a", "b", "c", "d", "e", "f"])
            compare(s.shown.length, 3); compare(s.more, 3)
            // min 50 dp; 5 dp padding, 20 dp icons 4 dp apart
            compare(QS.pillWidthDp(1, 0), 50)
            compare(QS.pillWidthDp(2, 0), 2 * 5 + 2 * 20 + 4)
            compare(QS.pillWidthDp(3, 3), 2 * 5 + 3 * 20 + 22 + 3 * 4)
            // the default list is stock's
            compare(QS.DEFAULT_TILES.join(","), "battery,settingsButton,soundToggle,bedtimeToggle,dndToggle,cinemaToggle,airplaneToggle,flashlightButton,brightnessButton,touchLockToggle,mobileToggle,findPhoneButton")
            compare(QS.TAP_DEBOUNCE_MS, 300); compare(QS.LONG_PRESS_MS, 400); compare(QS.AUTO_CLOSE_MS, 700)
            verify(QS.acceptTap(300, 0, 300)); verify(!QS.acceptTap(299, 0, 300))
        }

        // ---- the panel --------------------------------------------------------------

        function test_10_default_tiles_and_places() {
            // touch lock (not built) and Mobile (no modem) are hidden: ten tiles
            compare(ids().join(","), "battery,settingsButton,soundToggle,bedtimeToggle,dndToggle,cinemaToggle,airplaneToggle,flashlightButton,brightnessButton,findPhoneButton")
            compare(JSON.stringify(panel().rowIds), '[["battery"],["bedtimeToggle","soundToggle","settingsButton"],["airplaneToggle","cinemaToggle","dndToggle"],["findPhoneButton","brightnessButton","flashlightButton"]]')
            // none of the ours-only tiles
            var gone = ["lockButton", "bluetoothToggle", "hapticsToggle", "wifiToggle", "extraDimToggle", "aodToggle", "powerOffToggle", "rebootToggle", "musicButton"]
            for (var i = 0; i < gone.length; i++)
                verify(!has(gone[i]), gone[i] + " is not in stock's list")
            // 104 px buttons, 8 px apart, rows centred, 8 px between rows, row height 104
            var first = slot("battery")
            compare(first.width, 104); compare(first.height, 104)
            var rowH = find(panel(), "qsRow1")
            compare(rowH.height, 104)
            list().contentY = 0
            wait(80)
            compare(slot("bedtimeToggle").x, 28)
            compare(slot("soundToggle").x, 28 + 112)
            compare(slot("settingsButton").x, 28 + 224)
            compare(slot("battery").x, 140)
            compare(find(panel(), "qsRow1").y - find(panel(), "qsRow0").y, 112)
            // 40 px top padding and a spacer of 19 px for a top row of one
            compare(find(panel(), "qsRow0").y, 40 + 19)
            // the status tray is the last item, under the rows
            var st = find(panel(), "statusTray")
            verify(st.parent.y >= find(panel(), "qsRow3").y + 104)
        }

        function test_11_top_row_of_three_and_two_with_more_tiles() {
            root.touchLock = lock
            panel().tapDebounce = 0
            wait(50)
            // 11 tiles: a top row of two
            compare(panel().tileIds.length, 11)
            compare(find(panel(), "qsRow0").y, 40 + 30)
            DeviceSpecs.hasCellular = true
            wait(50)
            // 12 tiles: a top row of three, a spacer of 80
            compare(panel().tileIds.length, 12)
            compare(find(panel(), "qsRow0").y, 40 + 80)
            // Mobile sits after Touch lock and before Find My Phone
            var order = ids()
            compare(order.indexOf("mobileToggle"), order.indexOf("touchLockToggle") + 1)
            compare(order.indexOf("findPhoneButton"), order.indexOf("mobileToggle") + 1)
            DeviceSpecs.hasCellular = false
        }

        function test_12_opens_at_the_bottom_and_follows_the_tray() {
            var l = list()
            verify(l.contentHeight > l.height, "the list scrolls: " + l.contentHeight)
            compare(l.contentY, l.contentHeight - l.height)
            // scrolled up by the user, then the tray opens again: back at the end
            l.contentY = 0
            grid.currentVerticalPos = -1
            compare(l.contentY, l.contentHeight - l.height)
            // while the tray is dragged
            l.contentY = 0
            grid.topTrayFraction = 0.4
            compare(l.contentY, l.contentHeight - l.height)
            // the pill is at the bottom of the screen: 20 px under it
            var st = find(panel(), "statusTray")
            var b = st.parent.mapToItem(root, 0, st.y + st.height).y
            near(b, 384 - 20, 1, "pill bottom")
            near(st.mapToItem(root, st.width / 2, 0).x, 192, 1, "pill centred")
            shot("qs-01-bottom")
            l.contentY = 0
            wait(100)
            shot("qs-02-top")
        }

        function test_13_plain_list_no_dots_crown_exit() {
            var l = list()
            // a plain vertical Flickable: RotaryInput scrolls it freely, no snapping, no page dots
            verify(l.flickableDirection === Flickable.VerticalFlick)
            verify(l.boundsBehavior === Flickable.StopAtBounds)
            verify(findBy(panel(), function (o) { return o.hasOwnProperty("dotNumber") }) === null, "no page dots")
            verify(!l.hasOwnProperty("snapMode"))
            // the panel is the crown's exit receiver: forward past its end closes the tray
            var p = panel()
            compare(p.rotaryExitEdge, 1)
            p.rotaryExit(1)
            compare(grid.count("crownScrolled"), 1)
            compare(grid.calls[0].args[0], 1)
            grid.rotaryExitEdge = 2
            compare(p.rotaryExitEdge, 2)
            grid.rotaryExitEdge = -1
            compare(p.rotaryExitEdge, 2)
            grid.rotaryExitEdge = 0
            compare(p.rotaryExitEdge, 2)
            // the list is what a drag is handed over from
            compare(p.handOverView, l)
        }

        function test_14_edge_morph_on_the_rows() {
            var l = list()
            // at the end: the first row is above the screen, shrunk and gone; the last rows are whole
            var s0 = slot("battery")
            verify(s0.scale < 1, "the top row is morphed: " + s0.scale)
            near(s0.scale, 0.15, 1e-6)
            near(s0.item.containerAlpha, 0, 1e-6)
            near(s0.item.contentAlpha, 0, 1e-6)
            compare(slot("findPhoneButton").scale, 1)
            compare(slot("findPhoneButton").item.containerAlpha, 1)
            // a row half way in: scale, alpha follow the spec's function of the row's place
            l.contentY = l.contentHeight - l.height - 60
            wait(80)
            var row = find(panel(), "qsRow3")
            var m = QS.morph(row.y - l.contentY, row.height, l.height)
            var sl = slot("findPhoneButton")
            near(sl.scale, m.scale, 1e-6)
            near(sl.item.containerAlpha, m.container, 1e-6)
            near(sl.item.contentAlpha, m.content, 1e-6)
            verify(m.scale < 1)
            // the outer buttons of a row of three slide in
            var b = slot("flashlightButton")
            var base = QS.sidePadding(3, 384, 104, 8) + 2 * 112
            near(b.x - base, QS.slide(2, 3, 104, m.scale), 1e-6, "outer button slid")
            compare(slot("brightnessButton").x, QS.sidePadding(3, 384, 104, 8) + 112)
            shot("qs-03-morph")
        }

        // ---- the button -------------------------------------------------------------

        function test_20_button_look() {
            var d = tile("dndToggle")
            show(d)
            // off: surfaceContainer circle, onSurface icon, 52 px icon
            colourIs(d.containerColor, Theme.color.surfaceContainer, "off container")
            colourIs(d.contentColor, Theme.color.onSurface, "off content")
            compare(d.iconSize, 52)
            tryCompare(d, "radius", 52, 1500)
            // on: primaryDim, onPrimary, a 36 px (18 dp) rounded square, springs, colours tween 250 ms
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", true)
            wait(60)
            verify(d.lit)
            var mid = d.shape.color
            verify(mid.toString() !== Qt.color(Theme.color.surfaceContainer).toString() && mid.toString() !== Qt.color(Theme.color.primaryDim).toString(), "the colour is being tweened: " + mid)
            wait(400)
            colourIs(d.shape.color, Theme.color.primaryDim, "on container")
            colourIs(d.contentColor, Theme.color.onPrimary, "on content")
            tryCompare(d, "radius", 36, 1500)
            near(Theme.shape.medium, 36, 1e-9)
            shot("qs-04-dnd-on")
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", false)
        }

        function test_21_press_morph_and_disabled() {
            var s = tile("settingsButton")
            show(s)
            tryCompare(s, "radius", 52, 1500)
            var p = centre(s)
            mousePress(root, p.x, p.y)
            wait(30)
            // pressed: the corners x 0.66, on a stiff spring (1400)
            compare(s.targetRadius, 52 * 0.66)
            tryCompare(s, "radius", 52 * 0.66, 1000)
            mouseRelease(root, p.x, p.y)
            wait(30)
            compare(s.targetRadius, 52)
            tryCompare(s, "radius", 52, 1500)
            // on and pressed: 36 x 0.66
            var d = tile("dndToggle")
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", true)
            wait(100)
            show(d)
            p = centre(d)
            mousePress(root, p.x, p.y)
            wait(20)
            near(d.targetRadius, 36 * 0.66, 1e-6)
            mouseRelease(root, p.x, p.y)
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", false)
            wait(100)
            // disabled: onSurface 12 % container, 38 % icon (Find My Phone with the phone away)
            Backend.replies["org.asteroidos.btsyncd.Phone.Connected"] = false
            start(); panel().tapDebounce = 0
            var f = tile("findPhoneButton")
            verify(!f.enabled)
            near(f.containerColor.a, 0.12, 0.005)
            near(f.contentColor.a, 0.38, 0.005)
            compare(f.iconSize, 64)
        }

        function test_22_icon_sizes() {
            compare(tile("settingsButton").iconSize, 52)
            compare(tile("battery").iconSize, 64)
            compare(tile("findPhoneButton").iconSize, 64)
            compare(tile("flashlightButton").iconSize, 54)
            compare(tile("brightnessButton").iconSize, 52)
        }

        function test_23_tap_debounce_and_long_press() {
            panel().tapDebounce = 300
            wait(50)
            var s = tile("settingsButton")
            tap(s)
            compare(Backend.calls.filter(function (c) { return c.method === "launchApp" }).length, 1)
            // a second tap within 300 ms is ignored
            tap(s)
            compare(Backend.calls.filter(function (c) { return c.method === "launchApp" }).length, 1)
            wait(350)
            tap(s)
            compare(Backend.calls.filter(function (c) { return c.method === "launchApp" }).length, 2)
            // a long press (400 ms) is no tap
            Backend.clearCalls()
            wait(350)
            var b = tile("brightnessButton")
            hold(b, 300)    // not long enough: a press and release
            compare(Backend.calls.filter(function (c) { return c.method === "launchApp" }).length, 1)
            Backend.clearCalls()
            wait(350)
            var sound = tile("soundToggle")
            hold(sound, 520)
            compare(launched(), "asteroid-settings")
            compare(String(request()).split("@")[0], "sound")
            // no mute from the long press
            compare(volume.volume, 70)
        }

        // ---- the battery button -----------------------------------------------------

        function test_30_battery_button_look() {
            Backend.batteryPercent = 85
            start(); panel().tapDebounce = 0
            var b = tile("battery")
            show(b)
            compare(b.iconSize, 64)
            // the glyph filled to the step (90), the percent under it: 30 px digits, 20 px sign
            var fill = find(b, "batteryFill")
            var glyph = find(b, "batteryGlyph")
            compare(glyph.width, 64); compare(glyph.height, 28)
            near(fill.width, (glyph.bodyWidth - 14) * 0.9, 0.5, "fill")
            compare(find(b, "batteryDigits").font.pixelSize, 30)
            compare(find(b, "batteryDigits").text, "85")
            var pct = find(b, "batteryPercent")
            compare(pct.children[1].font.pixelSize, 20)
            // under the glyph
            verify(pct.y >= glyph.y + glyph.height)
            // Settings > Battery > Show percentage off hides the digits
            verify(find(b, "batteryPercent").visible)
            Backend.confSet("/org/asteroidos/quickpanel/show-battery-percent", false)
            wait(60)
            verify(!find(b, "batteryPercent").visible)
            Backend.confSet("/org/asteroidos/quickpanel/show-battery-percent", true)
            wait(60)
            // a11y
            compare(b.label, "Battery 85%. Battery saver off.")
            colourIs(b.contentColor, Theme.color.onSurface, "normal glyph")
            shot("qs-05-battery-85")
            // the level steps
            Backend.batteryPercent = 16
            wait(60)
            near(find(b, "batteryFill").width, (glyph.bodyWidth - 14) * 0.2, 0.5, "step 20")
            // at 15 or less: errorDim
            Backend.batteryPercent = 15
            wait(60)
            colourIs(b.contentColor, Theme.color.errorDim, "low battery")
            near(find(b, "batteryFill").width, (glyph.bodyWidth - 14) * 0.15, 0.5, "step 15")
            Backend.batteryPercent = 16
            wait(60)
            colourIs(b.contentColor, Theme.color.onSurface, "just above the trigger")
        }

        function test_31_battery_saver_asks_and_looks() {
            var b = tile("battery")
            Backend.batteryPercent = 57
            tap(b)
            verify(dialog().shown)
            compare(alert().title, "Turn on Battery Saver mode?")
            compare(alert().text, "Limits background activity and turns off always-on-screen. When needed, GPS will be used from the phone.")
            compare(alert().iconName, "ms-battery_saver")
            shot("qs-06-saver-dialog")
            yes()
            verify(modes.batterySaver)
            wait(450)
            // saver on: container #FEE170, content #3A3000, the glyph in it
            verify(b.checked)
            colourIs(b.shape.color, "#FEE170", "saver container")
            colourIs(b.contentColor, "#3A3000", "saver content")
            compare(b.label, "Battery 57%. Battery saver on.")
            shot("qs-07-saver-on")
            // off at once, no dialog
            tap(b)
            verify(!modes.batterySaver)
            verify(!dialog().shown)
            // with the automatic saver on the message says at what level
            modes.autoSaverOn = true
            tap(b)
            compare(alert().text, "Limits background activity and turns off always-on-screen. When needed, GPS will be used from the phone. Automatically turns on at 15%.")
            no()
            verify(!modes.batterySaver)
        }

        function test_32_battery_on_the_charger() {
            modes.charging = true
            wait(80)
            var b = tile("battery")
            // plugged in: the charging glyph (a bolt), the button greyed out, no saver
            verify(!b.enabled)
            verify(find(b, "batteryBolt").visible)
            verify(!find(b, "batteryFill").visible)
            near(b.containerColor.a, 0.12, 0.005)
            tap(b)
            verify(!dialog().shown)
            verify(!modes.batterySaver)
            compare(b.label, "Battery 57%. Charging.")
            shot("qs-08-battery-charging")
        }

        function test_33_battery_long_press_opens_the_saver_page() {
            var b = tile("battery")
            hold(b, 520)
            compare(launched(), "asteroid-settings")
            compare(String(request()).split("@")[0], "battery_saver")
            var at = Number(String(request()).split("@")[1])
            verify(Math.abs(Date.now() - at) < 5000)
            verify(!dialog().shown)
        }

        // ---- the modes: texts, layout, long presses, captions ------------------------

        function test_40_dialog_texts_and_layout() {
            var t = tile("bedtimeToggle")
            tap(t)
            compare(alert().title, "Turn on Bedtime mode?")
            compare(alert().text, "Wind down for sleep.\n\nOnly selected sources such as alarms will reach you. Turns off watch screen wake gestures, and reduces brightness.")
            // the shared AlertDialog: the tile's icon, dismiss 120 px rounded square, confirm 126 x 108 pill
            compare(alert().iconName, "ios-moon")
            compare(alert().buttons, "confirmDismiss")
            compare(alert().dismissSize, 120); compare(alert().dismissRadius, 36)
            compare(alert().confirmWidth, 126); compare(alert().confirmHeight, 108)
            var cb = find(alert(), "modeDialogDontShow")
            verify(cb.visible, "the Don't show again row")
            compare(cb.text, "Don't show again")
            shot("qs-09-bedtime-dialog")
            yes()
            verify(modes.bedtime)
            compare(Backend.confGet("/org/asteroidos/modes/ask/bedtime"), undefined)
            // off at once
            tap(t)
            verify(!modes.bedtime)
            verify(!dialog().shown)
            // no caption for Bedtime
            verify(find(panel(), "qsCaption").opacity === 0)
            // DND and Theater texts
            var d = tile("dndToggle")
            tap(d)
            compare(alert().title, "Turn on Do Not Disturb?")
            compare(alert().text, "Silences watch to minimize interruptions.\n\nOnly selected people and apps can reach you.")
            no()
            var th = tile("cinemaToggle")
            tap(th)
            compare(alert().title, "Turn on Theater mode?")
            compare(alert().text, "Silences everything including alarms.\n\nTurns off screen and wake gestures completely.")
            no()
            verify(!modes.theater)
        }

        function test_41_dont_show_again() {
            var t = tile("cinemaToggle")
            tap(t)
            settleDialog()
            var cb = find(alert(), "modeDialogDontShow")
            var p = cb.mapToItem(root, cb.width / 2, cb.height / 2)
            // the row may be below the fold of a scrolling dialog: the control is the same
            cb.clicked(null)
            wait(60)
            verify(dialog().dontShowAgain)
            yes()
            verify(modes.theater)
            compare(Backend.confGet("/org/asteroidos/modes/ask/theater"), false)
            tap(t)
            verify(!modes.theater)
            wait(100)
            // not asked again
            tap(t)
            verify(!dialog().shown)
            verify(modes.theater)
        }

        function test_42_long_press_opens_the_page() {
            var pages = { "bedtimeToggle": "bedtime", "dndToggle": "dnd", "cinemaToggle": "theater", "soundToggle": "sound" }
            for (var id in pages) {
                Backend.confSet(reqKey, "")
                Backend.clearCalls()
                wait(350)
                hold(tile(id), 520)
                compare(String(request()).split("@")[0], pages[id], id)
                compare(launched(), "asteroid-settings")
                verify(!dialog().shown, id + ": no question on a long press")
            }
            // Settings and Brightness: no long press
            Backend.confSet(reqKey, "")
            hold(tile("settingsButton"), 520)
            compare(request(), "")
            hold(tile("brightnessButton"), 520)
            compare(request(), "")
        }

        function test_43_brightness_tap_opens_the_page() {
            tap(tile("brightnessButton"))
            compare(String(request()).split("@")[0], "brightness")
            compare(launched(), "asteroid-settings")
            // no scrub: the brightness is not touched
            compare(Backend.brightness, 60)
        }

        function test_44_captions() {
            var cap = find(panel(), "qsCaption")
            var label = find(panel(), "qsCaptionText")
            // DND: asked first, then the caption
            Backend.confSet("/org/asteroidos/modes/ask/do-not-disturb", false)
            tap(tile("dndToggle"))
            compare(label.text, "Do Not Disturb on")
            // geometry: 24 % to 76 % of the width, 6 % of the width above the bottom, 12 sp (24 px)
            near(label.x, 0.24 * 384, 0.5)
            near(label.width, 0.52 * 384, 0.5)
            near(cap.mapToItem(root, 0, cap.height).y - (label.mapToItem(root, 0, label.height).y), 0.06 * 384, 0.5, "bottom margin")
            compare(label.font.pixelSize, 24)
            // fades in 375 ms
            verify(cap.opacity > 0 && cap.opacity <= 1)
            wait(450)
            compare(cap.opacity, 1)
            shot("qs-10-caption")
            // the gradient: black at the bottom, 41 sp (82 px) above the margin and the text
            near(cap.gradientHeight, cap.margin + label.height + 82, 0.5)
            // a new text crosses over
            tap(tile("cinemaToggle"))
            no()
            Backend.confSet("/org/asteroidos/modes/ask/theater", false)
            tap(tile("cinemaToggle"))
            var low = 1
            for (var k = 0; k < 20; k++) {
                low = Math.min(low, label.opacity)
                wait(20)
            }
            verify(low < 0.9, "the old text goes out first: " + low)
            wait(450)
            compare(label.text, "Theater mode on")
            compare(label.opacity, 1)
            // held 3000 ms, then out in 375 ms: gone by 4 s after
            tryCompare(cap, "opacity", 0, 5000)
            verify(!cap.visible)
        }

        function test_45_theater_closes_the_tray_700_ms_later() {
            Backend.confSet("/org/asteroidos/modes/ask/theater", false)
            tap(tile("cinemaToggle"))
            verify(modes.theater)
            compare(grid.count("closeTray"), 0)
            wait(500)
            compare(grid.count("closeTray"), 0)
            wait(400)
            compare(grid.count("closeTray"), 1)
            // asking first: the tray stays open while the question is up
            modes.theater = false
            grid.calls = []
            Backend.confSet("/org/asteroidos/modes/ask/theater", true)
            tap(tile("cinemaToggle"))
            wait(900)
            compare(grid.count("closeTray"), 0)
            no()
        }

        // ---- Notifications and ring --------------------------------------------------

        function test_50_sound_tile() {
            var s = tile("soundToggle")
            verify(s.checked, "not muted")
            tap(s)
            compare(volume.volume, 0)
            verify(!s.checked)
            compare(find(panel(), "qsCaptionText").text, "Ring & notifications off")
            compare(s.label, "Notifications and ring")
            wait(200)
            tap(s)
            compare(volume.volume, 70)
            captionIs("Ring & notifications on")
            // no volume slider, no scrub: a drag does not change the volume
            hold(s, 520)
            compare(volume.volume, 70)
        }

        // ---- Airplane mode -----------------------------------------------------------

        function test_60_airplane_mode() {
            var a = tile("airplaneToggle")
            verify(!a.checked)
            compare(a.label, "Airplane mode")
            tap(a)
            compare(alert().title, "Turn on Airplane mode?")
            compare(alert().text, "When airplane mode is on, Wi-Fi and mobile networks are turned off")
            verify(find(alert(), "modeDialogDontShow").visible)
            shot("qs-11-airplane-dialog")
            no()
            verify(!Backend.offline)
            tap(a)
            // Don't show again, then yes
            var cb = find(alert(), "modeDialogDontShow")
            settleDialog()
            cb.clicked(null)
            wait(60)
            yes()
            verify(Backend.offline, "connman's offline mode")
            verify(a.checked)
            compare(Backend.confGet("/org/asteroidos/modes/ask/airplane"), false)
            captionIs("Airplane mode on")
            // Bluetooth stays on, as stock (the radio is powered back if the offline mode took it)
            Backend.btPowered = false
            tryCompare(Backend, "btPowered", true, 3000)
            // off at once
            wait(100)
            tap(a)
            verify(!Backend.offline)
            verify(!dialog().shown)
            captionIs("Airplane mode off")
            // and no longer asked
            tap(a)
            verify(!dialog().shown)
            verify(Backend.offline)
        }

        function test_61_airplane_long_press_is_an_info_dialog() {
            hold(tile("airplaneToggle"), 520)
            verify(dialog().shown)
            compare(alert().title, "Airplane mode")
            compare(alert().text, "When airplane mode is on, Wi-Fi and mobile networks are turned off")
            compare(alert().buttons, "edge")
            verify(!find(alert(), "modeDialogDontShow").visible)
            verify(!Backend.offline)
            dialog().close()
        }

        // ---- Mobile ------------------------------------------------------------------

        function test_62_mobile_tile() {
            DeviceSpecs.hasCellular = true
            wait(60)
            var m = tile("mobileToggle")
            verify(m.checked, "Mobile auto")
            compare(m.label, "Mobile")
            tap(m)
            // on -> asks, no check box row
            compare(alert().title, "Turn off mobile networks?")
            compare(alert().text, "Calls, messages, and mobile data will not be available when watch is disconnected from phone.")
            verify(!find(alert(), "modeDialogDontShow").visible)
            no()
            verify(m.checked)
            tap(m)
            yes()
            verify(!m.checked)
            compare(Backend.confGet("/org/asteroidos/settings/mobile-enabled"), false)
            captionIs("Mobile off")
            wait(100)
            // off -> on at once
            tap(m)
            verify(!dialog().shown)
            verify(m.checked)
            captionIs("Mobile auto")
            hold(m, 520)
            compare(String(request()).split("@")[0], "connectivity")
            DeviceSpecs.hasCellular = false
        }

        // ---- Touch lock ----------------------------------------------------------------

        function test_63_touch_lock_closes_without_animation() {
            verify(!has("touchLockToggle"), "hidden until it is built")
            root.touchLock = lock
            wait(80)
            var t = tile("touchLockToggle")
            tap(t)
            compare(Backend.calls.filter(function (c) { return c.target === "touchlock" }).length, 1)
            wait(500)
            compare(grid.count("moveTo"), 0)
            wait(400)
            compare(grid.count("moveTo"), 1)
            compare(grid.calls[grid.calls.length - 1].args[0], 0)
            compare(grid.count("closeTray"), 0)
            Backend.confSet(reqKey, "")
            hold(t, 520)
            compare(String(request()).split("@")[0], "touch_lock")
        }

        // ---- Flashlight and Find My Phone ---------------------------------------------

        function test_70_flashlight_info() {
            var f = tile("flashlightButton")
            tap(f)
            compare(launched(), "asteroid-flashlight")
            hold(f, 520)
            compare(alert().title, "Flashlight")
            compare(alert().text, "Lights up your watch screen")
            dialog().close()
            wait(300)
        }

        function test_71_find_my_phone() {
            var f = tile("findPhoneButton")
            verify(f.enabled, "the phone is connected")
            // no red cross, no battery label on the tile
            verify(findBy(f, function (o) { return o.hasOwnProperty("name") && o.name === "ios-close-circle" }) === null)
            verify(findBy(f, function (o) { return o.text !== undefined && String(o.text).indexOf("%") >= 0 }) === null)
            tap(f)
            var c = Backend.find("org.asteroidos.btsyncd", "org.asteroidos.btsyncd.Notifications.FindPhone")
            verify(c !== null && c.args[0] === true)
            wait(100)
            verify(f.checked)
            tap(f)
            c = Backend.find("org.asteroidos.btsyncd", "org.asteroidos.btsyncd.Notifications.FindPhone")
            verify(c.args[0] === false)
            hold(f, 520)
            compare(alert().title, "Find My Phone")
            compare(alert().text, "Rings your phone even when the phone is muted or on vibrate")
            dialog().close()
            wait(300)
            // the phone goes away: greyed out
            Backend.replies["org.asteroidos.btsyncd.Phone.Connected"] = false
            start(); panel().tapDebounce = 0
            verify(!tile("findPhoneButton").enabled)
        }

        // ---- the status pill ---------------------------------------------------------------

        function test_80_status_pill() {
            var st = find(panel(), "statusTray")
            // the phone is connected, Bluetooth on, Wi-Fi connected: phone and Wi-Fi
            compare(JSON.stringify(st.icons), '["phone","wifi"]')
            compare(st.height, 52)
            compare(st.width, Theme.dp(QS.pillWidthDp(2, 0)))
            compare(st.pill.radius, 26)
            colourIs(st.pill.color, Theme.color.surfaceContainerLow, "pill colour")
            // icons 40 px, 8 px apart
            var i0 = find(st, "statusIcon-phone"), i1 = find(st, "statusIcon-wifi")
            compare(i0.width, 40)
            near(i1.mapToItem(st, 0, 0).x - i0.mapToItem(st, 0, 0).x, 48, 0.5)
            // a bare watch: Bluetooth off, the phone away, an alarm set: all four
            Backend.btPowered = false
            Backend.nextAlarmMs = Date.now() + 3600000
            Backend.replies["org.asteroidos.btsyncd.Phone.Connected"] = false
            start(); panel().tapDebounce = 0
            st = find(panel(), "statusTray")
            compare(JSON.stringify(st.icons), '["phoneOff","btOff","wifi","alarm"]')
            compare(st.width, Theme.dp(QS.pillWidthDp(4, 0)))
            shot("qs-12-pill-4")
            // Wi-Fi off: no Wi-Fi icon; nothing at all: no pill
            Backend.wifiConnected = false
            wait(60)
            compare(JSON.stringify(st.icons), '["phoneOff","btOff","alarm"]')
        }

        function test_81_pill_popups() {
            var st = find(panel(), "statusTray")
            show(st)
            Backend.btPowered = false
            Backend.wifiConnected = false
            wait(80)
            compare(JSON.stringify(st.icons), '["phone","btOff"]')
            // several: the list first
            var p = centre(st)
            mouseClick(root, p.x, p.y)
            wait(300)
            verify(st.list.shown)
            var r0 = find(st.list, "statusRow-phone"), r1 = find(st.list, "statusRow-btOff")
            compare(r0.text, "Connected to phone")
            compare(r1.text, "Bluetooth is off")
            shot("qs-13-pill-list")
            var rp = r1.mapToItem(root, r1.width / 2, r1.height / 2)
            mouseClick(root, rp.x, rp.y)
            wait(400)
            verify(st.popup.shown)
            compare(st.popup.title, "Bluetooth is off")
            compare(st.popup.edgeText, "Close")
            compare(st.popup.settingsButton.text, "Bluetooth Settings")
            shot("qs-14-pill-popup")
            // its button opens the Bluetooth page of Settings
            pressIn(st.popup, st.popup.settingsButton)
            compare(String(request()).split("@")[0], "bluetooth")
            compare(launched(), "asteroid-settings")
            verify(!st.popup.shown)
        }

        function test_82_pill_single_icon_popup() {
            Backend.wifiConnected = false
            wait(80)
            var st = find(panel(), "statusTray")
            compare(JSON.stringify(st.icons), '["phone"]')
            compare(st.width, 100)
            show(st)
            var p = centre(st)
            mouseClick(root, p.x, p.y)
            wait(400)
            // one icon: its popup at once
            verify(st.popup.shown && !st.list.shown)
            compare(st.popup.title, "Connected to")
            compare(st.popup.text, "Phone")
            // Close
            pressIn(st.popup, st.popup.edgeButton)
            wait(150)
            verify(!st.popup.shown)
            // the phone away
            Backend.replies["org.asteroidos.btsyncd.Phone.Connected"] = false
            start(); panel().tapDebounce = 0
            Backend.wifiConnected = false
            wait(60)
            st = find(panel(), "statusTray")
            compare(JSON.stringify(st.icons), '["phoneOff"]')
            st.showPopup("phoneOff")
            wait(300)
            compare(st.popup.title, "Disconnected from phone")
            compare(st.popup.text, "Make sure your phone is nearby and Bluetooth is turned on")
            compare(st.popup.settingsButton.text, "Bluetooth Settings")
            st.popup.close()
        }

        function test_83_pill_does_not_poll() {
            // the pill and the battery button follow signals: no timer in the panel runs while it is idle
            var running = []
            findBy(panel(), function (o) {
                if (o.hasOwnProperty("interval") && o.hasOwnProperty("repeat") && o.running)
                    running.push(o.interval)
                return false
            })
            compare(running.length, 0, "running timers: " + running)
        }

        // ---- what is not in stock's list ----------------------------------------------------

        function test_90_power_off_and_restart_ask_once_each() {
            // the old RemorseTimer connected a handler per tap: Restart after a cancelled Power off did both
            Backend.confSet(tilesKey, ["settingsButton", "powerOffToggle", "rebootToggle"])
            start(); panel().tapDebounce = 0
            tap(tile("powerOffToggle"))
            compare(alert().title, "Power off")
            compare(alert().text, "Are you sure?")
            no()
            tap(tile("rebootToggle"))
            compare(alert().title, "Restart device?")
            yes()
            wait(100)
            var login = "org.freedesktop.login1.Manager."
            verify(Backend.find("org.freedesktop.login1", login + "Reboot") !== null, "restarted")
            verify(Backend.find("org.freedesktop.login1", login + "PowerOff") === null, "no power off")
            // and the other way round
            Backend.clearCalls()
            tap(tile("rebootToggle"))
            no()
            tap(tile("powerOffToggle"))
            yes()
            wait(100)
            verify(Backend.find("org.freedesktop.login1", login + "PowerOff") !== null)
            verify(Backend.find("org.freedesktop.login1", login + "Reboot") === null)
        }

        function test_91_a_list_names_the_extras() {
            Backend.confSet(tilesKey, ["aodToggle", "hapticsToggle", "extraDimToggle", "bluetoothToggle", "bogusToggle", "aodToggle"])
            start(); panel().tapDebounce = 0
            compare(ids().join(","), "aodToggle,hapticsToggle,extraDimToggle,bluetoothToggle")
            // Always-on writes only its key: the launcher's applyLowPower() does the rest
            var aod = tile("aodToggle")
            tap(aod)
            compare(alwaysOnDisplay.value, false)
            compare(Backend.find("mce", "use_low_power_mode"), null)
            tap(aod)
            compare(alwaysOnDisplay.value, true)
            // Vibration is the master key and never writes haptics-crown
            tap(tile("hapticsToggle"))
            compare(Backend.confGet("/desktop/asteroid/vibration"), false)
            verify(Backend.confGet("/org/asteroidos/ux/haptics-crown") === undefined)
            for (var i = 0; i < Backend.calls.length; i++)
                verify(String(Backend.calls[i].method).indexOf("haptics-crown") < 0)
        }

        function test_92_the_old_editor_keys_are_not_read() {
            Backend.confSet("/desktop/asteroid/quickpanel/fixed", ["lockButton"])
            Backend.confSet("/desktop/asteroid/quickpanel/slider", ["brightnessToggle"])
            Backend.confSet("/desktop/asteroid/quickpanel/enabled", { "lockButton": true })
            start(); panel().tapDebounce = 0
            compare(ids().length, 10)
            verify(!has("lockButton"))
        }
    }
}
