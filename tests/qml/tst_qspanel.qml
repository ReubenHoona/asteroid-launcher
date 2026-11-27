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
        // the panel is shown open (1): less is the pull, which moves the content (D60-20)
        property real topTrayFraction: 1
        property bool trayMode: true
        property bool handingOver: false
        property bool trayDragging: false
        property QtObject trayAnimation: QtObject { property bool running: false }
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
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", false)
            modes.bedtime = false; modes.theater = false; modes.batterySaver = false
            modes.extraDim = false; modes.charging = false; modes.autoSaverOn = false
            volume.volume = 70
            root.touchLock = null
            DeviceSpecs.hasCellular = false
            grid.calls = []
            grid.currentVerticalPos = 0
            grid.topTrayFraction = 1
            grid.trayMode = true
            grid.trayDragging = false
            grid.trayAnimation.running = false
            grid.rotaryExitEdge = 1
            // the app style but where a test is about the launcher's (N61-03)
            RotaryInput.systemIndicator = false
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
            // D60-15: read from the bottom up (CP3A kxx.java:422 reverses the list, lah.java:318-344
            // groups it and reverses each row): the list's first three tiles are the bottom row in
            // their order, the top row holds the count mod 3 last ones
            compare(JSON.stringify(QS.rows(seq(11))), "[[9,10],[6,7,8],[3,4,5],[0,1,2]]")
            compare(JSON.stringify(QS.rows(seq(10))), "[[9],[6,7,8],[3,4,5],[0,1,2]]")
            compare(JSON.stringify(QS.rows(seq(12))), "[[9,10,11],[6,7,8],[3,4,5],[0,1,2]]")
            compare(JSON.stringify(QS.rows(seq(2))), "[[0,1]]")
            compare(JSON.stringify(QS.rows([])), "[]")
            // the input is not changed
            var s11 = seq(11)
            QS.rows(s11)
            compare(JSON.stringify(s11), JSON.stringify(seq(11)))
            // stock's eleven on the watch (no Mobile): Touch lock, Find my phone at the top
            compare(JSON.stringify(QS.rows(["battery", "settingsButton", "soundToggle", "bedtimeToggle", "dndToggle", "cinemaToggle",
                                            "airplaneToggle", "flashlightButton", "brightnessButton", "touchLockToggle", "findPhoneButton"])),
                    '[["touchLockToggle","findPhoneButton"],["airplaneToggle","flashlightButton","brightnessButton"],'
                    + '["bedtimeToggle","dndToggle","cinemaToggle"],["battery","settingsButton","soundToggle"]]')
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
            compare(mid.height, 1)
            // out of the screen at the top: scale 0.15, container and content alpha 0, height 0.5
            var out = QS.morph(-104, 104, 384)
            compare(out.scale, 0.15); compare(out.container, 0); compare(out.content, 0); compare(out.height, 0.5)
            verify(out.atTop)
            // out at the bottom: scale 0.5, alpha 0.3, height 0.7
            var low = QS.morph(384, 104, 384)
            compare(low.scale, 0.5); near(low.container, 0.3, 1e-9); near(low.content, 0.3, 1e-9); near(low.height, 0.7, 1e-9)
            verify(!low.atTop)
            // D60-14: the 192 dp spec's transition area is half the screen whatever the height (hqd.java:68-70)
            compare(QS.MIN_AREA, 0.5); compare(QS.MAX_AREA, 0.5)
            compare(JSON.stringify(QS.MORPH_HEIGHT), JSON.stringify({ top: 0.5, bottom: 0.7, enter: 0, exit: 1 }))
            compare(QS.MORPH_CONTENT_MIN, 0.05)
            // the top-edge row of the open panel (top -36, bottom 68: x = 68 / 192 = 0.354): a pill
            // 60 x 46 px (stock S11: 60 x 46 at y 23-68)
            var tr = QS.morph(-36, 104, 384)
            verify(tr.atTop)
            near(tr.scale, 0.578, 0.003, "top row scale")
            near(tr.height, 0.751, 0.003, "top row height")
            near(104 * tr.scale, 60, 1, "top pill width")
            near(104 * tr.scale * tr.height, 45.5, 1.5, "top pill height")
            // CP3A's alpha there (hqf.java with las.java's container spec), not the emulator's
            near(tr.container, 0.844, 0.01, "top row container alpha")
            near(tr.content, 0.575, 0.01, "top row content alpha")
            // a bottom-edge row with its top at 288 (x = 96 / 192 = 0.5): 87 x 79 px (stock S12: 86-88 x 77-79)
            var br = QS.morph(288, 104, 384)
            verify(!br.atTop)
            near(104 * br.scale, 87, 1.5, "bottom pill width")
            near(104 * br.scale * br.height, 78.5, 1.5, "bottom pill height")
            compare(br.container, 1)
            // half way in, between the edge value and 1; the alpha rises later than the scale
            var m = QS.morph(0, 104, 384)
            verify(m.scale > 0.15 && m.scale < 1, "scale " + m.scale)
            verify(m.container >= 0 && m.container <= 1)
            verify(m.content >= 0 && m.content <= 1)
            // the alpha reaches 1 (zone 0.05 to 0.5 of the area) before the scale (zone 0 to 1)
            verify(m.container >= (m.scale - 0.15) / 0.85 - 1e-9)
            // the area is 0.5 of the screen: the transform ends where the element's inner edge is that
            // far in: top 0 -> x = 0.2708 / 0.5
            near(QS.bezier(QS.MORPH_EASING, 0.2708 / 0.5), (m.scale - 0.15) / 0.85, 0.01, "scale at the top row")
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
            // D60-16: CP3A's layer of kxf.java case 16 on the 84 px box
            // at rest (box 300..384): full size, alpha 0.773, 3.8 px up
            var r = QS.statusTransform(300 / 384, 1, 84)
            compare(r.scale, 1)
            near(r.alpha, 1 - 0.5 * (300 / 384 - 0.6) / 0.4, 1e-9)
            near(r.alpha, 0.773, 0.001)
            near(r.dy, -84 * 0.4 * (300 / 384 - 0.6) / 0.4 / 4, 1e-9)
            near(r.dy, -3.81, 0.01)
            // in the middle of the screen: nothing
            r = QS.statusTransform(0.4, 0.6, 84)
            compare(r.scale, 1); compare(r.alpha, 1); compare(r.dy, 0)
            // going down: the top past 0.8 shrinks it to 0.35 at the edge, alpha to 0.5
            r = QS.statusTransform(0.9, 1.1, 84)
            near(r.scale, 1 - 0.65 * 0.5, 1e-9); near(r.alpha, 1 - 0.5 * 0.75, 1e-9)
            near(r.dy, -84 * 0.4 * 0.75 / 4, 1e-9)
            r = QS.statusTransform(1, 1.2, 84)
            near(r.scale, 0.35, 1e-9); near(r.alpha, 0.5, 1e-9); near(r.dy, -84 * 0.4 / 4, 1e-9)
            // coming in at the top: the bottom under 0.2 / 0.4, a shift down
            r = QS.statusTransform(-0.12, 0.1, 84)
            near(r.scale, 0.35 + 0.65 * 0.5, 1e-9); near(r.alpha, 0.5 + 0.5 * 0.25, 1e-9)
            near(r.dy, 84 * (1 - (0.4 + 0.6 * 0.25)) / 4, 1e-9)
            r = QS.statusTransform(-0.3, -0.1, 84)
            near(r.scale, 0.35, 1e-9); near(r.alpha, 0.5, 1e-9); near(r.dy, 84 * 0.6 / 4, 1e-9)
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
            compare(JSON.stringify(panel().rowIds), '[["findPhoneButton"],["airplaneToggle","flashlightButton","brightnessButton"],["bedtimeToggle","dndToggle","cinemaToggle"],["battery","settingsButton","soundToggle"]]')
            // none of the ours-only tiles
            var gone = ["lockButton", "bluetoothToggle", "hapticsToggle", "wifiToggle", "extraDimToggle", "aodToggle", "powerOffToggle", "rebootToggle", "musicButton"]
            for (var i = 0; i < gone.length; i++)
                verify(!has(gone[i]), gone[i] + " is not in stock's list")
            // 104 px buttons, 8 px apart, rows centred, 8 px between rows, row height 104
            var first = slot("battery")
            compare(first.width, 104); compare(first.height, 104)
            var rowH = find(panel(), "qsRow1")
            compare(rowH.height, 104)
            // open (the end of the list): Battery, Settings, Sound the bottom row left to right, over the pill
            compare(slot("battery").x, 28)
            compare(slot("settingsButton").x, 28 + 112)
            compare(slot("soundToggle").x, 28 + 224)
            // the row above starts its edge morph (bottom 180 of a 192 px area: scale 0.995)
            near(slot("bedtimeToggle").x, 28, 1)
            compare(slot("dndToggle").x, 28 + 112)
            near(slot("cinemaToggle").x, 28 + 224, 1)
            verify(slot("battery").mapToItem(root, 0, 0).y > slot("bedtimeToggle").mapToItem(root, 0, 0).y, "Battery under Bedtime")
            list().contentY = 0
            wait(80)
            // the top row: Find my phone alone
            compare(slot("findPhoneButton").x, 140)
            compare(find(panel(), "qsRow1").y - find(panel(), "qsRow0").y, 112)
            // 40 px top padding and a spacer of 19 px for a top row of one
            compare(find(panel(), "qsRow0").y, 40 + 19)
            // the status tray is the last item, under the rows
            var st = find(panel(), "statusTray")
            verify(find(panel(), "statusLayer").parent.y >= find(panel(), "qsRow3").y + 104)
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
            grid.topTrayFraction = 1
            // the pill is at the bottom of the screen: 20 px under it in its box, the box's layer
            // 3.8 px up (kxf.java case 16)
            var st = find(panel(), "statusTray")
            var b = st.parent.mapToItem(root, 0, st.y + st.height).y
            near(b, 384 - 20 - 3.8, 1, "pill bottom")
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
            // the stock stretch overscroll (motion D2): the finger pulls past an end, the content stops
            verify(l.boundsBehavior === Flickable.DragOverBounds)
            verify(l.boundsMovement === Flickable.StopAtBounds)
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
            var s0 = slot("findPhoneButton")
            verify(s0.scale < 1, "the top row is morphed: " + s0.scale)
            near(s0.scale, 0.15, 1e-6)
            near(s0.item.containerAlpha, 0, 1e-6)
            near(s0.item.contentAlpha, 0, 1e-6)
            compare(slot("battery").scale, 1)
            compare(slot("battery").item.containerAlpha, 1)
            // a row half way in: scale, alpha follow the spec's function of the row's place
            l.contentY = l.contentHeight - l.height - 60
            wait(80)
            var row = find(panel(), "qsRow3")
            var m = QS.morph(row.y - l.contentY, row.height, l.height)
            var sl = slot("battery")
            near(sl.scale, m.scale, 1e-6)
            near(sl.item.containerAlpha, m.container, 1e-6)
            near(sl.item.contentAlpha, m.content, 1e-6)
            verify(m.scale < 1)
            // the outer buttons of a row of three slide in
            var b = slot("soundToggle")
            var base = QS.sidePadding(3, 384, 104, 8) + 2 * 112
            near(b.x - base, QS.slide(2, 3, 104, m.scale), 1e-6, "outer button slid")
            compare(slot("settingsButton").x, QS.sidePadding(3, 384, 104, 8) + 112)
            shot("qs-03-morph")
        }

        // the container's box on the screen
        function shapeRect(id) {
            var s = find(tile(id), "qsShape")
            var a = s.mapToItem(root, 0, 0), b = s.mapToItem(root, s.width, s.height)
            return { x0: a.x, y0: a.y, x1: b.x, y1: b.y, w: b.x - a.x, h: b.y - a.y, shape: s }
        }

        function test_14b_edge_rows_squeezed_into_pills() {
            // D60-14: open (the end of the list), the top-edge row (Airplane, Flashlight, Brightness, top -36,
            // bottom 68) is three pills 60 x 46 px at y 23-68, 8 px above the next row (stock S11: x 93-152,
            // 162-221, 231-290, y 23-68)
            var l = list()
            compare(l.contentY, l.contentHeight - l.height)
            var row = find(panel(), "qsRow1")
            compare(row.y - l.contentY, -36)
            var a = shapeRect("airplaneToggle"), f = shapeRect("flashlightButton"), br = shapeRect("brightnessButton")
            near(a.w, 60, 2, "pill width"); near(a.h, 46, 2, "pill height")
            near(a.y1, 68, 1, "pill bottom on the row's bottom")
            near(a.y0, 23, 2, "pill top")
            near(a.x0, 93, 2, "left pill"); near(a.x1, 152, 2, "left pill right")
            near(f.x0, 162, 2, "middle pill"); near(br.x0, 231, 2, "right pill"); near(br.x1, 290, 2, "right pill right")
            near((a.x0 + a.x1) / 2, 123, 1, "left centre"); near((br.x0 + br.x1) / 2, 261, 1, "right centre")
            var next = find(panel(), "qsRow2")
            near(next.y - l.contentY - a.y1, 8, 1, "8 px above the next row")
            // a stadium: the radius is half its height
            near(a.shape.radius, a.shape.height / 2, 1e-6, "stadium")
            near(a.shape.height, 104 * tile("airplaneToggle").morphHeight, 1e-6)
            verify(tile("airplaneToggle").morphAtTop)
            // the icon is on the pill, scaled with it
            var ic = findBy(tile("airplaneToggle"), function (o) { return o.objectName === "" && o.hasOwnProperty("name") && o.name === "ms-airplanemode_active" })
            verify(ic !== null, "airplane icon")
            var c = ic.mapToItem(root, ic.width / 2, ic.height / 2)
            near(c.y, (a.y0 + a.y1) / 2, 1, "icon on the pill")
            // the icon's alpha: container x content (CP3A's layers)
            var tl = tile("airplaneToggle")
            near(find(tl, "qsContent").opacity, tl.containerAlpha * tl.contentAlpha, 1e-6)
            verify(find(tl, "qsContent").visible)
            // the full rows are untouched
            var s = shapeRect("battery")
            compare(s.w, 104); compare(s.h, 104)
            compare(tile("battery").morphHeight, 1)
            shot("qs-04-top-pills")

            // scrolled to the top: the bottom-edge row keeps its top on its place, 8 px under the row above
            l.contentY = 0
            wait(80)
            var r2 = find(panel(), "qsRow2")
            var top = r2.y - l.contentY
            var m = QS.morph(top, 104, 384)
            verify(!m.atTop && m.scale < 1)
            var b = shapeRect("bedtimeToggle")
            near(b.y0, top, 1, "pill top on the row's top")
            near(b.w, 104 * m.scale, 1, "bottom pill width")
            near(b.h, 104 * m.scale * m.height, 1, "bottom pill height")
            verify(!tile("bedtimeToggle").morphAtTop)
            var r1 = find(panel(), "qsRow1")
            near(b.y0 - (r1.y - l.contentY + 104), 8, 1, "8 px under the row above")
            shot("qs-05-bottom-pills")
        }

        function test_15_pull_comes_in_ahead_of_the_finger() {
            // D60-20: CP3A's list during the pull (lah.java, afn.java case 14, eqa.java case 3): offset down
            // by H (1 - p) (the tray's slide cancelled), its end spacer max(1 dp, 1.25 H (1 - p)): on the
            // screen the content is 1.25 H (1 - p) - 2 px higher than at rest
            near(QS.pullGrowth(1, 384, 2), 0, 1e-9)
            near(QS.pullGrowth(0.5, 384, 2), 238, 1e-9)
            near(QS.pullGrowth(0, 384, 2), 478, 1e-9)
            near(QS.pullGrowth(0.999, 384, 2), 0, 1e-9)
            near(QS.pullOffset(0.5, 384), 192, 1e-9)
            compare(QS.PULL_SPACER_FACTOR, 1.25)
            var p = panel(), l = list()
            var pull = l.transform[1]
            compare(pull.objectName, "qsPull")
            var st = find(p, "statusTray"), lay = find(p, "statusLayer")
            // at rest: nothing
            compare(p.pullGrowth, 0); compare(pull.y, 0)
            var rest = st.mapToItem(root, 0, st.height / 2).y
            var restRow = find(p, "qsRow3").mapToItem(root, 0, 0).y
            // half way (the finger 192 px down): the tray box is 192 px up on the watch (this mock grid
            // does not move the panel); the list is drawn 192 - 238 = -46 px in it, so 238 px higher
            // on the screen than at rest
            grid.topTrayFraction = 0.5
            wait(50)
            compare(l.contentY, l.contentHeight - l.height)
            near(p.pullGrowth, 238, 1e-9); near(p.pullOffset, 192, 1e-9)
            near(pull.y, -46, 1e-9)
            near(find(p, "qsRow3").mapToItem(root, 0, 0).y - restRow, -46, 0.01, "content in the tray")
            // the edge morph and the status tray take the screen's places
            var row3 = find(p, "qsRow3")
            var m = QS.morph(row3.y - l.contentY - 238, 104, 384)
            near(slot("battery").scale, m.scale, 1e-6)
            verify(m.scale < 1, "the bottom row is at the top of the screen")
            near(lay.topFraction * 384, 300 - 238, 0.5, "status box on the screen")
            var t = QS.statusTransform(62 / 384, 146 / 384, 84)
            near(lay.scale, t.scale, 1e-6); near(lay.opacity, t.alpha, 1e-6)
            // on the screen (the tray's slide, -192 px, added): the pill's centre is the finger's way less
            // about 105 px (stock M07: 105 +- 15)
            var onScreen = st.mapToItem(root, 0, st.height / 2).y - 192
            near(onScreen - 192, -105, 15, "pill behind the finger")
            near(onScreen, rest - 238 + t.dy - (-3.81), 0.5, "pill on the screen")
            shot("qs-09-pull-half")
            // three quarters, then back to rest: the rest place does not change
            grid.topTrayFraction = 0.75
            wait(50)
            near(p.pullGrowth, 1.25 * 384 * 0.25 - 2, 1e-9)
            grid.topTrayFraction = 1
            wait(50)
            compare(pull.y, 0)
            near(st.mapToItem(root, 0, st.height / 2).y, rest, 1e-6)
            near(find(p, "qsRow3").mapToItem(root, 0, 0).y, restRow, 1e-6)
            // no trays (the AsteroidOS layout): no pull
            grid.trayMode = false
            grid.topTrayFraction = 0
            wait(50)
            compare(p.pullFraction, 1); compare(pull.y, 0)
            grid.trayMode = true
            grid.topTrayFraction = 1
        }

        // the shared scroll indicator RotaryInput puts on the window (PositionIndicator)
        function indicator() {
            var r = root
            while (r.parent)
                r = r.parent
            var kids = r.children
            for (var i = 0; i < kids.length; i++) {
                var k = kids[i]
                if (k.flickable !== undefined && k.shown !== undefined && typeof k.flash === "function")
                    return k
            }
            return null
        }

        function test_16_indicator_when_the_tray_comes_to_rest() {
            // D60-09: CP3A shows quick settings' indicator once the tray is fully open (laj.java:135,
            // lah.java:371-380), as a screen that opens: about 2 s, the thumb at the bottom (the list at
            // its end)
            var p = panel(), l = list()
            verify(l.contentHeight > l.height, "a list that scrolls")
            var ind = indicator()
            if (ind)
                ind.shown = false
            // on its way out: no indicator
            grid.trayAnimation.running = true
            grid.topTrayFraction = 0.6
            grid.currentVerticalPos = -1
            wait(50)
            verify(!p.openAtRest)
            ind = indicator()
            verify(!ind || !ind.shown, "not while the tray moves")
            grid.topTrayFraction = 1
            wait(50)
            verify(!p.openAtRest, "still on the spring")
            ind = indicator()
            verify(!ind || !ind.shown, "not on the spring")
            grid.trayAnimation.running = false
            verify(p.openAtRest, "open and at rest")
            ind = indicator()
            verify(ind !== null && ind.shown, "the indicator shows")
            compare(ind.flickable, l)
            compare(l.contentY, l.contentHeight - l.height)
            verify(l.atYEnd, "the thumb at the bottom: the list at its end")
            // it sits on the right edge (stock S11: x 363-379)
            var o = ind.mapToItem(root, 0, 0)
            verify(o.x + ind.width > 340, "on the right: " + o.x + " " + ind.width)
            shot("qs-10-indicator")
            tryVerify(function () { return !ind.shown }, 4000, "and hides about 2 s later")
            // a finger on the tray: not at rest; let go: shown again
            grid.trayDragging = true
            verify(!p.openAtRest)
            grid.trayDragging = false
            verify(p.openAtRest)
            verify(ind.shown, "at rest again")
            tryVerify(function () { return !ind.shown }, 4000)
            // closed, or without trays: nothing
            grid.currentVerticalPos = 0
            verify(!p.openAtRest)
            grid.trayMode = false
            grid.currentVerticalPos = -1
            verify(!p.openAtRest)
            grid.trayMode = true
            grid.currentVerticalPos = 0
        }

        // the grey level on the indicator's arc (radius 183) at deg degrees (0 = 3 o'clock, + = down)
        function arcAt(img, deg) {
            var a = deg * Math.PI / 180
            return img.pixel(Math.round(192 + 183 * Math.cos(a)), Math.round(192 + 183 * Math.sin(a)))
        }

        function test_16b_system_indicator_as_the_emulator() {
            // N61-03: the launcher sets RotaryInput.systemIndicator (compositor.qml), so quick settings' indicator
            // is the system UI's, as the Wear OS 6 emulator's S11: a white thumb at the bottom end of a #4D4D4D
            // track from -17 to +17 degrees at radius 183 (S11: thumb -6 to +17, the list at its end). Muted,
            // as S11 (the struck bell); then the top of the list, as S12.
            RotaryInput.systemIndicator = true
            volume.volume = 0
            wait(60)
            var p = panel(), l = list()
            var ind = indicator()
            if (ind)
                ind.shown = false
            grid.currentVerticalPos = -1
            wait(50)
            verify(p.openAtRest)
            ind = indicator()
            verify(ind !== null && ind.shown, "the indicator shows")
            compare(ind.flickable, l)
            verify(ind.systemStyle)
            colourIs(ind.thumbColor, "#FFFFFF", "thumb")
            colourIs(ind.trackColor, "#4D4D4D", "track")
            compare(ind.sweepDegrees, 34)
            wait(500)
            var img = grabImage(screen)
            img.save(shots + "/qs-11-s11-system-indicator.png")
            var t = arcAt(img, 14), k = arcAt(img, -14)
            verify(t.r > 0.95 && t.g > 0.95 && t.b > 0.95, "white thumb at the bottom end: " + t)
            near(k.r, 0x4D / 255, 0.03, "the track at the top end")
            for (var d = 20; d <= 40; d += 4) {
                var o = arcAt(img, d), o2 = arcAt(img, -d)
                verify(o.r + o.g + o.b < 0.1 && o2.r + o2.g + o2.b < 0.1, "no ink outside +-17 degrees at " + d)
            }
            // the top of the list (S12): the thumb at the top end
            l.contentY = 0
            ind.flash()
            wait(700)
            img = grabImage(screen)
            img.save(shots + "/qs-12-s12-system-indicator.png")
            t = arcAt(img, -14)
            verify(t.r > 0.95 && t.g > 0.95 && t.b > 0.95, "white thumb at the top end: " + t)
            RotaryInput.systemIndicator = false
            grid.currentVerticalPos = 0
            volume.volume = 70
        }

        // the share of an item's box on the screen that is ink: well above the dark fills (#2E2F35, #1C1D21)
        function inkOf(img, item) {
            var a = item.mapToItem(root, 0, 0), b = item.mapToItem(root, item.width, item.height)
            var ink = 0, n = 0
            for (var y = Math.round(a.y); y < b.y; y += 2)
                for (var x = Math.round(a.x); x < b.x; x += 2) {
                    var q = img.pixel(x, y)
                    n++
                    if (Math.max(q.r, q.g, q.b) > 0.45)
                        ink++
                }
            return n > 0 ? ink / n : 0
        }

        function test_17_top_with_the_watch_state() {
            // The watch (image 63) showed two empty pills at the top of quick settings where the emulator's S12
            // has the Find my phone circle. Its state: Touch lock built (11 tiles: a top row of two, Touch lock
            // and Find my phone, D60-15), the phone connected, Wi-Fi off, no alarm.
            root.touchLock = lock
            Backend.wifiPowered = false
            Backend.wifiConnected = false
            start(); panel().tapDebounce = 0
            var p = panel(), l = list()
            var ids = ["touchLockToggle", "findPhoneButton"]
            compare(JSON.stringify(p.rowIds[0]), JSON.stringify(ids))
            compare(l.contentHeight - l.height, 218, "the list's range")
            compare(l.contentY, 218, "open at the end")
            // the status pill is at the bottom of the list (CP3A's place), with the phone alone, drawn
            var st = find(p, "statusTray")
            compare(JSON.stringify(st.icons), '["phone"]')
            wait(150)
            var img = grabImage(screen)
            var ph = inkOf(img, find(st, "statusIcon-phone"))
            verify(ph > 0.1, "the pill's phone glyph drawn: " + ph)
            // The watch's frame (C-qs-top) was not the top: t62.sh turned the crown 12 counts, 30 ms apart
            // (positive turns back), from the open list, and that stops 90 px up from the end (128 of 218 on the
            // build host, as on the watch, whose indicator thumb is half way down its track).
            for (var w = 0; w < 12; w++) {
                mouseWheel(root, 192, 192, 0, 120)
                wait(30)
            }
            wait(1200)
            verify(l.contentY > 60 && l.contentY < 218, "12 counts stop short of the top: " + l.contentY)
            // There the top row's inner edge is at y 46, 0.24 of the transition area, short of the content zone
            // (0.25 to 0.5): CP3A draws the buttons as 48 x 33 px pills without their glyphs (content alpha 0,
            // lag.java:126) at container alpha 0.6, #2E2F35 showing as #1C1C20 on black. The watch: pills at
            // x 141-188 and 196-243, y 14-46, #1C1C20.
            l.contentY = 218 - 90
            wait(150)
            var row = find(p, "qsRow0")
            var m = QS.morph(row.y - l.contentY, row.height, l.height)
            verify(m.atTop && m.content === 0 && m.container > 0.5 && m.container < 0.7, JSON.stringify(m))
            img = grabImage(screen)
            var lefts = [141, 196]
            for (var i = 0; i < 2; i++) {
                var r = shapeRect(ids[i])
                near(r.x0, lefts[i], 2, ids[i] + " pill left")
                near(r.w, 48, 2, ids[i] + " pill width")
                near(r.h, 33, 2, ids[i] + " pill height")
                near(r.y1, 46, 1.5, ids[i] + " pill bottom")
                compare(tile(ids[i]).contentAlpha, 0)
                var c = img.pixel(Math.round((r.x0 + r.x1) / 2), Math.round((r.y0 + r.y1) / 2))
                verify(Math.abs(c.r * 255 - 0x1C) <= 3 && Math.abs(c.g * 255 - 0x1C) <= 3 && Math.abs(c.b * 255 - 0x20) <= 3,
                       ids[i] + " pill on the screen " + c)
            }
            shot("qs-17a-watch-frame")
            // the crown turned on: the list reaches its top
            for (var k = 0; k < 120 && l.contentY > 0; k++) {
                mouseWheel(root, 192, 192, 0, 120)
                wait(20)
            }
            tryCompare(l, "contentY", 0, 3000)
            wait(400)
            compare(l.contentY, 0, "the crown reaches the top")
            // the top: Touch lock and Find my phone, two whole circles (row top 70: 40 + the two-button
            // spacer 30), their glyphs drawn; S12 has Find my phone alone (the emulator has no Touch lock)
            compare(row.y - l.contentY, 70)
            img = grabImage(screen)
            for (i = 0; i < 2; i++) {
                var s = slot(ids[i]), t = tile(ids[i])
                verify(s.scale > 0.98, ids[i] + " whole: " + s.scale)
                near(t.contentAlpha, 1, 0.01, ids[i] + " content")
                near(t.containerAlpha, 1, 0.01, ids[i] + " container")
                var ink = litShare(img, t, t.iconSize)
                verify(ink > 0.1 && ink < 0.8, ids[i] + " glyph drawn: " + ink)
            }
            verify(tile("findPhoneButton").enabled, "the phone is connected")
            shot("qs-17b-top-watch-state")
            // the pill's other glyphs draw too: Wi-Fi connected and an alarm set (icons of the set), then the
            // phone away and Bluetooth off (the eos-status files)
            Backend.wifiPowered = true
            Backend.wifiConnected = true
            Backend.nextAlarmMs = Date.now() + 3600000
            start(); panel().tapDebounce = 0
            st = find(panel(), "statusTray")
            compare(JSON.stringify(st.icons), '["phone","wifi","alarm"]')
            wait(150)
            img = grabImage(screen)
            for (i = 0; i < st.icons.length; i++) {
                ink = inkOf(img, find(st, "statusIcon-" + st.icons[i]))
                verify(ink > 0.1, st.icons[i] + " drawn: " + ink)
            }
            shot("qs-17c-pill-phone-wifi-alarm")
            Backend.btPowered = false
            Backend.replies["org.asteroidos.btsyncd.Phone.Connected"] = false
            start(); panel().tapDebounce = 0
            st = find(panel(), "statusTray")
            compare(JSON.stringify(st.icons), '["phoneOff","btOff","wifi","alarm"]')
            wait(150)
            img = grabImage(screen)
            for (i = 0; i < st.icons.length; i++) {
                ink = inkOf(img, find(st, "statusIcon-" + st.icons[i]))
                verify(ink > 0.1, st.icons[i] + " drawn: " + ink)
            }
            shot("qs-17d-pill-four")
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

        // the share of a tile's icon box (size px, centred on the button) that is lit
        function litShare(img, t, size) {
            var c = centre(t), lit = 0, n = 0
            for (var y = 0; y < size; y += 2)
                for (var x = 0; x < size; x += 2) {
                    var p = img.pixel(Math.round(c.x - size / 2 + x), Math.round(c.y - size / 2 + y))
                    n++
                    if (p.r > 0.6 && p.g > 0.6 && p.b > 0.6)
                        lit++
                }
            return lit / n
        }

        function test_22b_glyphs_as_the_emulator() {
            // N61-25: the Wear OS 6 emulator's quick settings (S11, S12) draws Material Symbols Rounded FILLED
            // glyphs: Bedtime a crescent moon, Settings a filled gear, Brightness a filled sun with 8 short
            // rays, Airplane an airplane, DND a disc with a bar, Find my phone a phone with waves (icons of
            // the set); Theater a clapperboard, Flashlight a torch struck while off, Notifications and ring
            // a bell struck while muted (path glyphs, qs.js). Sizes unchanged: 26 dp, Flashlight 27, Find
            // my phone 32. (D60-17's bed and its one torch for both states are gone.)
            var cases = [["bedtimeToggle", "icon", "ms-bedtime-fill", 52], ["dndToggle", "icon", "ms-do_not_disturb_on-fill", 52],
                         ["cinemaToggle", "glyph", QS.GLYPH_CLAPPER, 52], ["settingsButton", "icon", "ms-settings-fill", 52],
                         ["soundToggle", "glyph", QS.GLYPH_BELL, 52], ["airplaneToggle", "icon", "ms-airplanemode_active", 52],
                         ["flashlightButton", "glyph", QS.GLYPH_TORCH_OFF, 54], ["brightnessButton", "icon", "ms-sunny-fill", 52],
                         ["findPhoneButton", "icon", "ms-vibration", 64]]
            for (var i = 0; i < cases.length; i++) {
                var t = tile(cases[i][0])
                compare(t[cases[i][1]], cases[i][2], cases[i][0])
                compare(t.iconSize, cases[i][3], cases[i][0] + " size")
                var g = find(t, "qsGlyph")
                compare(g.visible, cases[i][1] === "glyph", cases[i][0] + " path glyph")
                if (cases[i][1] === "glyph") {
                    compare(t.icon, "", cases[i][0] + " no icon")
                    compare(g.width, cases[i][3]); compare(g.height, cases[i][3])
                } else {
                    compare(t.glyph, "", cases[i][0] + " no path glyph")
                }
            }
            // the path data: Material Symbols Rounded fill 1 (movie, flashlight_on, flashlight_off,
            // notifications, notifications_off at google/material-design-icons 10ecc14)
            compare(QS.GLYPH_CLAPPER.indexOf("m160-800"), 0)
            compare(QS.GLYPH_TORCH.indexOf("M240-760"), 0)
            compare(QS.GLYPH_TORCH_OFF.indexOf("M320-160v-368L84-764"), 0)
            compare(QS.GLYPH_BELL.indexOf("M200-200q-17"), 0)
            compare(QS.GLYPH_BELL_OFF.indexOf("M646-200H200"), 0)
            compare(QS.torchGlyph(true), QS.GLYPH_TORCH); compare(QS.torchGlyph(false), QS.GLYPH_TORCH_OFF)
            compare(QS.bellGlyph(false), QS.GLYPH_BELL); compare(QS.bellGlyph(true), QS.GLYPH_BELL_OFF)
            // the Flashlight glyph follows checked: struck while the light is off (S12), the torch while on
            var fl = tile("flashlightButton")
            verify(!fl.checked, "the light is off under quick settings")
            fl.checked = true
            compare(fl.glyph, QS.GLYPH_TORCH)
            fl.checked = false
            compare(fl.glyph, QS.GLYPH_TORCH_OFF)
            // the bell follows the ring mute (R5 B-01): muted by a tap, struck (S11); unmuted, the bell again
            var s = tile("soundToggle")
            verify(s.checked)
            tap(s)
            verify(!s.checked)
            compare(s.glyph, QS.GLYPH_BELL_OFF)
            wait(200)
            tap(s)
            verify(s.checked)
            compare(s.glyph, QS.GLYPH_BELL)
            // Settings' switch (the same key) strikes it too; the media volume does not
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", true)
            wait(60)
            compare(tile("soundToggle").glyph, QS.GLYPH_BELL_OFF)
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", false)
            volume.volume = 0
            wait(60)
            compare(tile("soundToggle").glyph, QS.GLYPH_BELL)
            volume.volume = 70
            wait(60)
            compare(tile("soundToggle").glyph, QS.GLYPH_BELL)
            // the same glyph when on (Bedtime, Theater, DND)
            modes.bedtime = true; modes.theater = true
            wait(60)
            compare(tile("bedtimeToggle").icon, "ms-bedtime-fill")
            compare(tile("cinemaToggle").glyph, QS.GLYPH_CLAPPER)
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", true)
            wait(60)
            verify(tile("dndToggle").checked)
            compare(tile("dndToggle").icon, "ms-do_not_disturb_on-fill")
            modes.bedtime = false; modes.theater = false
            Backend.confSet("/org/asteroidos/notifications/do-not-disturb", false)
            wait(60)
            // drawn: the path glyph's box sits on the button (the Shape's own Translate moves its origin
            // down by its height: the box starts at -height), and each glyph fills a part of its box
            var bl = tile("soundToggle")
            show(bl)
            wait(150)
            var gb = find(bl, "qsGlyph")
            var o = gb.mapToItem(root, 0, -gb.height)
            near(o.x, centre(bl).x - 26, 1, "glyph box x"); near(o.y, centre(bl).y - 26, 1, "glyph box y")
            var img = grabImage(screen)
            var bell = litShare(img, bl, 52), moon = litShare(img, tile("bedtimeToggle"), 52)
            var gear = litShare(img, tile("settingsButton"), 52)
            verify(bell > 0.15 && bell < 0.8, "bell drawn: " + bell)
            verify(moon > 0.15 && moon < 0.8, "moon drawn: " + moon)
            verify(gear > 0.15 && gear < 0.8, "gear drawn: " + gear)
            shot("qs-08-glyphs")
            // the top of the list (S12): the struck torch and the filled sun drawn
            list().contentY = 0
            wait(150)
            img = grabImage(screen)
            var torch = litShare(img, tile("flashlightButton"), 54), sun = litShare(img, tile("brightnessButton"), 52)
            verify(torch > 0.15 && torch < 0.8, "struck torch drawn: " + torch)
            verify(sun > 0.15 && sun < 0.8, "sun drawn: " + sun)
            shot("qs-08b-glyphs-top")
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
            compare(Backend.confGet("/org/asteroidos/sound/mute-ring-notifications"), false)
            compare(volume.volume, 70)
        }

        // ---- the battery button -----------------------------------------------------

        function test_30_battery_button_look() {
            Backend.batteryPercent = 85
            start(); panel().tapDebounce = 0
            var b = tile("battery")
            show(b)
            compare(b.iconSize, 64)
            // D60-18: CP3A's battery_status glyph: the 64 x 28 px drawable 18 px down in the button, a
            // body 44.3 x 24 px (corners 7.4) at (8.5, 2) and a nub 2.8 x 11.1 px at (54.7, 8.5), both
            // at 55 %, the level (step 90: index 7, right edge 22.731 dp) solid
            var fill = find(b, "batteryFill")
            var glyph = find(b, "batteryGlyph")
            var body = find(b, "batteryBody"), nub = find(b, "batteryNub")
            compare(glyph.width, 64); compare(glyph.height, 28)
            compare(glyph.y, 18)
            near(glyph.x, (104 - 64) / 2, 1e-6)
            near(body.x, 8.538, 0.01); near(body.y, 2, 0.01)
            near(body.width, 44.308, 0.01); near(body.height, 24, 0.01); near(body.radius, 7.384, 0.01)
            near(body.opacity, 0.55, 1e-6)
            near(nub.x, 54.692, 0.01); near(nub.y, 8.46, 0.01); near(nub.width, 2.77, 0.01); near(nub.height, 11.078, 0.01)
            near(nub.opacity, 0.55, 1e-6)
            // body to the nub's end 48.9 px (the emulator's older glyph is 43-44)
            near(nub.x + nub.width - body.x, 48.9, 0.1)
            near(fill.width, 2 * (22.731 - 4.269), 0.01, "fill")
            compare(fill.x, body.x); compare(fill.height, body.height)
            verify(fill.visible)
            compare(find(b, "batteryDigits").font.pixelSize, 30)
            compare(find(b, "batteryDigits").font.weight, Font.DemiBold)
            compare(find(b, "batteryDigits").text, "85")
            var pct = find(b, "batteryPercent")
            compare(pct.children[1].font.pixelSize, 20)
            compare(pct.children[1].font.weight, Font.DemiBold)
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
            // the level steps: the right edge of CP3A's drawable per step
            var rights = [[15, 7.041], [20, 8.885], [30, 9.808], [40, 12.555], [50, 15.346], [60, 18.124], [70, 20.885], [90, 22.731], [99, 23.5]]
            for (var i = 0; i < rights.length; i++)
                near(QS.batteryLevelWidth(rights[i][0]), rights[i][1] - 4.269, 1e-9, "step " + rights[i][0])
            Backend.batteryPercent = 16
            wait(60)
            near(find(b, "batteryFill").width, 2 * (8.885 - 4.269), 0.01, "step 20")
            // 100 %: body and nub solid, no separate level
            Backend.batteryPercent = 100
            wait(60)
            compare(body.opacity, 1); compare(nub.opacity, 1)
            verify(!find(b, "batteryFill").visible)
            // at 15 or less: errorDim
            Backend.batteryPercent = 15
            wait(60)
            colourIs(b.contentColor, Theme.color.errorDim, "low battery")
            near(find(b, "batteryFill").width, 2 * (7.041 - 4.269), 0.01, "step 15")
            near(body.opacity, 0.55, 1e-6)
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
            // the shared AlertDialog as qml-asteroid's Q4 has it (Wear OS 6, N61-11 and N61-12): the tile's icon,
            // two round buttons 104 px wide 24 px apart; it fades in rising 10 % of the height in 200 ms and leaves
            // rising 5 % more in 150 ms, with no zoom (the CP3A rounded square, pill and scale springs are gone)
            compare(alert().iconName, "ios-moon")
            compare(alert().buttons, "confirmDismiss")
            compare(alert().twoButtons, true)
            compare(alert().dismissButton.width, 104); compare(alert().confirmButton.width, 104)
            compare(alert().roundButtonGap, 24)
            compare(alert().contentScale, 1)
            compare(alert().enterRise, 0.10); compare(alert().exitRise, -0.05)
            compare(alert().enterDuration, 200); compare(alert().exitDuration, 150)
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

        // ---- FP-L2 (CR-56): the ngfd names of a volume step ----
        function test_49_volume_step_event_names() {
            compare(QS.volumeStepEvent("media", false), "volume_step")
            compare(QS.volumeStepEvent("media", true), "volume_step_max")
            var roles = ["ring", "notification", "alarm", "call"]
            for (var i = 0; i < roles.length; i++) {
                compare(QS.volumeStepEvent(roles[i], false), "volume_step_" + roles[i])
                compare(QS.volumeStepEvent(roles[i], true), "volume_step_max_" + roles[i])
            }
        }

        // ---- Notifications and ring --------------------------------------------------

        // R5 B-01: the tile is stock's ringer mode (CSUI SoundTileUserActionInteractor$handleClick$2:
        // setRingerModeInternal(on ? NORMAL : VIBRATE)), the key of Settings > Sound's "Mute ring &
        // notifications" (/org/asteroidos/sound/mute-ring-notifications, which ngfd reads); the media
        // volume is not touched
        function test_50_sound_tile() {
            var s = tile("soundToggle")
            verify(s.checked, "not muted")
            tap(s)
            compare(Backend.confGet("/org/asteroidos/sound/mute-ring-notifications"), true)
            compare(volume.volume, 70, "the media volume is not the tile's")
            verify(!s.checked)
            compare(find(panel(), "qsCaptionText").text, "Ring & notifications off")
            compare(s.label, "Notifications and ring")
            wait(200)
            tap(s)
            compare(Backend.confGet("/org/asteroidos/sound/mute-ring-notifications"), false)
            compare(volume.volume, 70)
            captionIs("Ring & notifications on")
            // no volume slider, no scrub: a hold opens Settings > Sound and mutes nothing
            hold(s, 520)
            compare(Backend.confGet("/org/asteroidos/sound/mute-ring-notifications"), false)
            compare(volume.volume, 70)
        }

        // stock's handler plays nothing (no ngfd event: neither the old volume step nor a notification)
        function test_50b_toggle_plays_nothing() {
            var s = tile("soundToggle")
            Backend.clearCalls()
            tap(s)
            wait(200)
            tap(s)
            wait(400)
            compare(Backend.find("ngfd", "volume_step"), null)
            compare(Backend.find("ngfd", "volume_step_max"), null)
            compare(Backend.find("ngfd", "notification"), null)
        }

        // the image default (00-eos-defaults mute-ring-notifications=true, stock def_ringer_mode 1 =
        // VIBRATE): the tile shows off, the struck bell, as Settings shows the switch on
        function test_50c_default_is_muted() {
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", true)
            wait(60)
            var s = tile("soundToggle")
            verify(!s.checked)
            compare(s.glyph, QS.GLYPH_BELL_OFF)
            // a muted media volume (the old pre-mute level) no longer decides the tile
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", false)
            Backend.confSet("/desktop/asteroid/pre-mute-level", 60)
            volume.volume = 0
            wait(60)
            verify(tile("soundToggle").checked)
            // a string "true" from dconf counts as muted
            Backend.confSet("/org/asteroidos/sound/mute-ring-notifications", "true")
            wait(60)
            verify(!tile("soundToggle").checked)
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

        // FP-L2 (CR-25): Bluetooth stays on in airplane mode unless the user turned it off there (settings/bluetooth-off-in-airplane)
        function test_60b_bluetooth_off_in_airplane_keeps_bluetooth_off() {
            Backend.confSet("/org/asteroidos/modes/ask/airplane", false)
            Backend.confSet("/org/asteroidos/settings/bluetooth-off-in-airplane", true)
            var a = tile("airplaneToggle")
            tap(a)
            verify(Backend.offline)
            // connman's offline mode took the radio: it is not powered back
            Backend.btPowered = false
            wait(2300)
            compare(Backend.btPowered, false, "the user wants it off")
            tap(a)
            verify(!Backend.offline)
        }
        function test_60c_bluetooth_off_in_airplane_false_powers_it_back() {
            Backend.confSet("/org/asteroidos/modes/ask/airplane", false)
            Backend.confSet("/org/asteroidos/settings/bluetooth-off-in-airplane", false)
            var a = tile("airplaneToggle")
            tap(a)
            verify(Backend.offline)
            Backend.btPowered = false
            tryCompare(Backend, "btPowered", true, 3000)
            tap(a)
            verify(!Backend.offline)
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
            // stock asks first (touch_lock_dialog_title, _message), without "Don't show again"
            tap(t)
            compare(alert().title, "Turn on Touch lock?")
            compare(alert().text, "Turns off touch screen. Press & hold crown for 2 sec. to turn it back on.")
            compare(alert().iconName, "ms-screen_lock_portrait")
            compare(alert().buttons, "confirmDismiss")
            verify(!find(alert(), "modeDialogDontShow").visible)
            no()
            compare(Backend.calls.filter(function (c) { return c.target === "touchlock" }).length, 0, "not locked by No")
            tap(t)
            yes()
            compare(Backend.calls.filter(function (c) { return c.target === "touchlock" }).length, 1)
            // the tray closes 700 ms after the answer, not at once, and without animation
            compare(grid.count("moveTo"), 0)
            tryVerify(function () { return grid.count("moveTo") === 1 }, 2500)
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

        function test_79_status_pill_full_size_at_rest() {
            // D60-16: open and at rest the pill is full size (stock S11: 100 x 52 px), its layer at
            // CP3A's alpha: #24262B shows as #1C1D21 (stock S11: #1C1D21)
            var l = list()
            compare(l.contentY, l.contentHeight - l.height)
            var st = find(panel(), "statusTray")
            var lay = find(panel(), "statusLayer")
            compare(lay.height, 84)
            near(lay.mapToItem(root, 0, 0).y, 300 - 3.8, 0.1, "box top")
            compare(lay.scale, 1)
            compare(st.scale, 1)
            near(lay.opacity, 0.773, 0.001)
            var a = st.mapToItem(root, 0, 0), z = st.mapToItem(root, st.width, st.height)
            near(z.y - a.y, 52, 0.1, "pill height")
            near(z.x - a.x, st.width, 0.1, "pill width")
            verify(st.width >= 100 && st.width <= 2 * (QS.pillWidthDp(4, 0)), "pill width " + st.width)
            near((a.x + z.x) / 2, 192, 0.5, "pill centred")
            colourIs(st.pill.color, Theme.color.surfaceContainerLow, "pill colour")
            colourIs(Theme.color.surfaceContainerLow, "#24262B", "the static palette's surfaceContainerLow")
            // the colour on the screen: a point of the pill's left padding, off its icons
            wait(100)
            var img = grabImage(screen)
            var px = img.pixel(Math.round(a.x + 5), Math.round((a.y + z.y) / 2))
            verify(Math.abs(px.r * 255 - 0x1C) <= 3 && Math.abs(px.g * 255 - 0x1D) <= 3 && Math.abs(px.b * 255 - 0x21) <= 3,
                   "pill on the screen " + px)
            // scrolled so the box goes down the screen: it shrinks and fades by the rule
            l.contentY = l.contentHeight - l.height - 60
            wait(80)
            near(lay.topFraction * l.height, 360, 0.5, "box top")
            var t = QS.statusTransform(360 / 384, 444 / 384, 84)
            near(lay.scale, t.scale, 1e-6); near(lay.opacity, t.alpha, 1e-6)
            verify(t.scale < 1 && t.alpha < 0.773)
            shot("qs-06-pill-scrolled")
            l.contentY = l.contentHeight - l.height
            wait(80)
            shot("qs-07-pill-rest")
        }

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
