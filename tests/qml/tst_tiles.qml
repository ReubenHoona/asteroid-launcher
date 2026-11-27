// SPDX-License-Identifier: BSD-3-Clause
//
// The tile frame (src/qml/tiles/TileBase.qml) and the carousel's app icon (src/qml/home/TilesIndicator.qml)
// drawn with the image's controls on the repo mocks. 384 x 384 px = 192 dp, 1 dp = 2 px.
//
// D60-21: the bottom text is CP3A's two lines (Fitbit tile_primarygoal/heartrate/sleep_preview.xml, Weather
// sun/uv_tile_preview.webp): the label, then the value (with its icon) under it, each line centred and fitted to
// the slot between the 26 % side margins (x 99.84-284.16; 6 dp, 5.2 % and 26 %: deskclock cno.java:443-447).
// The value stays whole, a label too long for the slot ends in an ellipsis; nothing is drawn outside the slot.
// Label 14 sp (titleSmall), value 16 sp (titleMedium), 5.2 % from the bottom, 6 dp under the content.
//
// D60-22: the app icon at the top stays on over a tile whose layout is an M3 primary layout (TileBase: CP3A's
// M3_PL root tag, renderer arp.java:19-26 -> auw.java:466-481 -> sysui hxq.java:25-34 -> jme.java:36-49) and
// fades over one that is not (Quick Add: CP3A's AddTileTileService builds its own layout, no tag): alpha 1 when
// the pager stops, 0 after a 500 ms pause and a 150 ms linear tween; back to 1 50 ms after the pager moves
// (100 ms tween).
//
// N61-26: the Wear OS 6 emulator's expressive tile frame (S13, S14, S14-c): TileBase.expressive (no icon slot,
// content from 52 px, a compact pill 104 x 64 px at y 296 for 'New', no edge button, no bottom text, the app
// icon fading: m3Layout false) and CircleGrid (52 dp circles 8 dp apart, two over three), measured on the
// grabbed pixels where the emulator gave a pixel value.
// N61-27: the Timer tile (S13): five #182B2F circles '05' ... '30' and the cyan pill 'New'.
// N61-28: the Alarm tile as the Next Alarm (S14, the S14-d preview): 'No alarms' and the yellow 'Set new'
// stadium; the time to go, the gradient stadium and the day, the minute tick only while awake. The alarms are
// the Nemo.Alarms test double's.
// N61-29: the Favorites tile (S14-c, the S14-d preview): the title, the message on 41 px lines and 'Refresh';
// five photos two over three and 'Contacts'. The contacts are the org.asteroid.contacts link's, with invented
// names, in a preview (nothing is asked of a phone).
//
// Shots go to /tmp/wo06-shots. Run by a qmltestrunner harness under qemu-aarch64 on the image rootfs with the
// tiles staged as module LauncherQml at their resource paths (motion-wt/wo06/run.sh; newlook-wt/l4h/run.sh tiles).
import QtQuick
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick
import Nemo.Alarms
import LauncherTest
import LauncherQml

Item {
    id: top
    width: 384; height: 384

    // the launcher's context properties (lipstick localemanager.cpp, MainScreen's desktop)
    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: desktop
        property var launched: []
        function openTilesEditor(addList) {}
        function launchByName(name, origin) { launched = launched.concat([name]) }
    }
    // the compositor of a watch showing the home screen, awake (TileBase.awake); the repo mock has no homeActive
    QtObject {
        id: awakeCompositor
        property bool homeActive: true
        property bool displayAmbient: false
        property bool displayDimmed: false
    }

    Rectangle { anchors.fill: parent; color: "black" }

    Component { id: baseComp; TileBase { width: 384; height: 384 } }
    Component { id: expressiveComp; TileBase { width: 384; height: 384; expressive: true } }
    Component { id: indicatorComp; TilesIndicator { count: 1; position: 1 } }
    // a CircleGrid in an expressive tile's body (x 20-363, y 52-275)
    Component {
        id: gridComp
        Item {
            id: gridHost
            width: 384; height: 384
            property alias grid: circles
            property int n: 5
            CircleGrid {
                id: circles
                x: 20; y: 52; width: 344; height: 224
                model: gridHost.n
                delegate: TileCard { containerColor: "#182B2F" }
            }
        }
    }
    Component { id: timerComp; TimerTile { width: 384; height: 384 } }
    Component { id: alarmComp; AlarmTile { width: 384; height: 384 } }
    Component { id: favoritesComp; FavoritesTile { width: 384; height: 384 } }
    Loader { id: stepsLoader; width: 384; height: 384; active: false; source: Qt.resolvedUrl("LauncherQml/tiles/StepsTile.qml") }
    Loader { id: quickAddLoader; width: 384; height: 384; active: false; source: Qt.resolvedUrl("LauncherQml/tiles/QuickAddTile.qml") }

    TestCase {
        name: "Tiles"
        when: windowShown

        // the slot between the 26 % side margins
        readonly property real slotLeft: 384 * 0.26
        readonly property real slotRight: 384 - 384 * 0.26
        // the loaded tiles (untyped: the members are the tiles' own)
        readonly property var stepsTile: stepsLoader.item
        readonly property var quickAddTile: quickAddLoader.item

        function shot(item, name) {
            item.grabToImage(function (r) { r.saveToFile("/tmp/wo06-shots/" + name + ".png") })
            wait(50)
        }

        // where a text or icon draws, in the tile's coordinates (an unclipped text wider than its box overflows it)
        function ink(tile, it) {
            var p = it.mapToItem(tile, 0, 0)
            var w = it.width
            if (it.contentWidth !== undefined && !it.clip)
                w = Math.max(w, it.contentWidth)
            return { l: p.x, r: p.x + w, t: p.y, b: p.y + it.height, cy: p.y + it.height / 2 }
        }

        function checkSlot(tile, tag) {
            var items = [tile.bottomIconItem, tile.bottomLabelItem, tile.bottomValueItem]
            for (var i = 0; i < items.length; i++) {
                if (!items[i].visible)
                    continue
                var k = ink(tile, items[i])
                verify(k.l >= slotLeft - 0.5, tag + ": item " + i + " starts at " + k.l + ", left of the slot")
                verify(k.r <= slotRight + 0.5, tag + ": item " + i + " ends at " + k.r + ", right of the slot")
            }
        }

        function cleanup() {
            stepsLoader.active = false
            quickAddLoader.active = false
        }

        // a grabbed pixel against an "#RRGGBB" colour, each channel within tol
        function near(img, x, y, rgb, tol, msg) {
            var c = img.pixel(x, y)
            var want = Qt.color(rgb)
            var ok = Math.abs(c.r - want.r) * 255 <= tol && Math.abs(c.g - want.g) * 255 <= tol && Math.abs(c.b - want.b) * 255 <= tol
            verify(ok, (msg || "") + " pixel " + x + "," + y + " is " + c + ", not " + rgb)
        }
        // the first and last rows in x0..x1 (every 2nd column) and y0..y1 with a pixel brighter than `level` (0..1)
        function inkRows(img, x0, x1, y0, y1, level) {
            var first = -1, last = -1
            for (var y = y0; y <= y1; y++) {
                for (var x = x0; x <= x1; x += 2) {
                    var c = img.pixel(x, y)
                    if (Math.max(c.r, c.g, c.b) > level) {
                        if (first < 0)
                            first = y
                        last = y
                        break
                    }
                }
            }
            return { first: first, last: last }
        }
        // where an item's middle is in the tile
        function centre(tile, it) {
            return it.mapToItem(tile, it.width / 2, it.height / 2)
        }
        // the five circle centres of S13 and the S14-d preview, px
        readonly property var fiveCentres: [[132, 104], [252, 104], [72, 224], [192, 224], [312, 224]]

        // ---- D60-21: the bottom text

        function test_d60_21_steps() {
            stepsLoader.active = true
            var t = stepsTile
            verify(t)
            compare(t.bottomLabel, "Daily Goal")
            // en's grouping (the test runs in the C locale, which has none)
            t.bottomValue = "10,000"
            waitForRendering(t)
            shot(t, "steps")
            // the frame's roles: label 14 sp, value 16 sp
            compare(t.bottomLabelItem.font.pixelSize, Math.round(Theme.type.titleSmall.pixelSize))
            compare(t.bottomValueItem.font.pixelSize, Math.round(Theme.type.titleMedium.pixelSize))
            compare(t.bottomLabelItem.font.pixelSize, 28)
            compare(t.bottomValueItem.font.pixelSize, 32)
            checkSlot(t, "steps")
            compare(t.bottomLabelItem.truncated, false)
            compare(t.bottomValueItem.truncated, false)
            var lab = ink(t, t.bottomLabelItem), val = ink(t, t.bottomValueItem)
            // two lines, the label over the value, each centred
            verify(lab.b <= val.t + 0.5, "label " + lab.t + "-" + lab.b + " over the value " + val.t + "-" + val.b)
            fuzzyCompare((lab.l + lab.r) / 2, 192, 1)
            fuzzyCompare((val.l + val.r) / 2, 192, 1)
            // 5.2 % from the bottom (20 px), the content 6 dp over the label
            fuzzyCompare(val.b, 384 - 20, 0.5)
            fuzzyCompare(t.body.y + t.body.height, lab.t - 12, 0.5)
            compare(t.bottomText.height, t.bottomLabelItem.height + t.bottomValueItem.height)
        }

        // FP-L5 (health-fitness-30, CR-36): the card opens Health on its steps page, as the heart rate
        // tile and the steps complication open theirs
        function test_fp_l5_steps_route() {
            stepsLoader.active = true
            var t = stepsTile
            verify(t)
            desktop.launched = []
            var before = Date.now()
            mouseClick(findChild(t, "goalCard"))
            compare(desktop.launched, ["asteroid-health"])
            var v = String(Backend.conf["/org/asteroidos/health/ui/open"])
            verify(v.indexOf("steps@") === 0, v)
            var ms = Number(v.slice(v.lastIndexOf("@") + 1))
            verify(ms >= before && ms <= Date.now(), v)
            desktop.launched = []
        }

        function test_d60_21_long_label() {
            var t = createTemporaryObject(baseComp, top, { bottomLabel: "Daily step goal for the whole week", bottomValue: "10,000" })
            verify(t)
            waitForRendering(t)
            shot(t, "long-label")
            checkSlot(t, "long label")
            verify(t.bottomLabelItem.truncated, "the label ends in an ellipsis")
            compare(t.bottomValueItem.truncated, false)
            fuzzyCompare(t.bottomLabelItem.width, slotRight - slotLeft, 0.5)
        }

        function test_d60_21_long_value() {
            var t = createTemporaryObject(baseComp, top, { bottomLabel: "Max UV", bottomValue: "1,234,567,890,123,456,789" })
            verify(t)
            waitForRendering(t)
            checkSlot(t, "long value")
            compare(t.bottomLabelItem.truncated, false)
            verify(t.bottomValueItem.truncated, "a value wider than the slot ends in an ellipsis")
        }

        function test_d60_21_icon_line() {
            var t = createTemporaryObject(baseComp, top, { bottomLabel: "Current bpm", bottomValue: "72", bottomIcon: "ms-favorite" })
            verify(t)
            waitForRendering(t)
            shot(t, "icon-line")
            checkSlot(t, "icon")
            verify(t.bottomIconItem.visible)
            compare(t.bottomIconItem.width, 32)
            var lab = ink(t, t.bottomLabelItem), ic = ink(t, t.bottomIconItem), val = ink(t, t.bottomValueItem)
            // the icon is on the value's line (CP3A heart at x 78-91 dp, value 97-115 dp, y 166-179 dp), 4 dp before it
            fuzzyCompare(ic.cy, val.cy, 1)
            fuzzyCompare(ic.r + 8, val.l, 0.5)
            verify(lab.b <= Math.min(ic.t, val.t) + 0.5)
            fuzzyCompare((ic.l + val.r) / 2, 192, 1)
            fuzzyCompare((lab.l + lab.r) / 2, 192, 1)
        }

        function test_d60_21_icon_long_value() {
            var t = createTemporaryObject(baseComp, top, { bottomLabel: "Current bpm", bottomValue: "1,234,567,890,123,456", bottomIcon: "ms-favorite" })
            verify(t)
            waitForRendering(t)
            checkSlot(t, "icon long value")
            verify(t.bottomValueItem.truncated)
            fuzzyCompare(t.bottomValueItem.width, slotRight - slotLeft - 32 - 8, 0.5)
        }

        function test_d60_21_one_line() {
            // a value with no label (and a label with no value) is one line, 20 px from the bottom
            var t = createTemporaryObject(baseComp, top, { bottomValue: "84%" })
            verify(t)
            waitForRendering(t)
            verify(!t.bottomLabelItem.visible)
            compare(t.bottomText.height, t.bottomValueItem.height)
            fuzzyCompare(ink(t, t.bottomValueItem).b, 364, 0.5)
            fuzzyCompare(t.body.y + t.body.height, 364 - t.bottomValueItem.height - 12, 0.5)
            t.bottomValue = ""
            t.bottomLabel = "Sunset"
            waitForRendering(t)
            verify(!t.bottomValueItem.visible)
            compare(t.bottomText.height, t.bottomLabelItem.height)
            fuzzyCompare(ink(t, t.bottomLabelItem).b, 364, 0.5)
            checkSlot(t, "label only")
            // the value comes (back): two lines again, the value 20 px from the bottom
            t.bottomValue = "9:01 PM"
            waitForRendering(t)
            verify(t.bottomValueItem.visible)
            compare(t.bottomText.height, t.bottomLabelItem.height + t.bottomValueItem.height)
            fuzzyCompare(ink(t, t.bottomValueItem).b, 364, 0.5)
            checkSlot(t, "value back")
        }

        function test_d60_21_no_text() {
            var t = createTemporaryObject(baseComp, top, {})
            verify(t)
            verify(!t.bottomText.visible)
            // no bottom text: the content ends 19.6 % above the bottom
            fuzzyCompare(t.body.y + t.body.height, 384 - Math.round(384 * 0.196), 0.5)
            // an edge button takes the bottom: no bottom text
            t.bottomLabel = "Daily Goal"
            t.bottomValue = "10,000"
            verify(t.bottomText.visible)
            t.chipText = "Open"
            verify(!t.bottomText.visible)
        }

        // ---- D60-22: the app icon at the top

        function test_d60_22_m3_layout() {
            var t = createTemporaryObject(baseComp, top, {})
            verify(t)
            // the frame is an M3 primary layout: CP3A's tiles carry the M3_PL tag (deskclock cno.java:374,
            // contacts aha.java:1376), so their icon is permanent
            compare(t.m3Layout, true)
            // writable: a tile that is not one says so
            t.m3Layout = false
            compare(t.m3Layout, false)
            quickAddLoader.active = true
            var q = quickAddTile
            verify(q)
            waitForRendering(q)
            shot(q, "quick-add")
            // CP3A's Add tile (AddTileTileService.java:108-614) has no M3_PL tag
            compare(q.m3Layout, false)
        }

        function test_d60_22_timing() {
            var ind = createTemporaryObject(indicatorComp, top, {})
            verify(ind)
            var show = null, hide = null
            for (var i = 0; i < ind.resources.length; i++) {
                var a = ind.resources[i]
                if (!a || a.animations === undefined || a.animations.length !== 2)
                    continue
                if (a.animations[1].to === 1)
                    show = a
                else if (a.animations[1].to === 0)
                    hide = a
            }
            verify(show && hide, "the two tweens")
            // in: 100 ms linear after 50 ms; out: 150 ms linear after 500 ms (ifp.java:59-72, hjw.java:247-440)
            compare(show.animations[0].duration, 50)
            compare(show.animations[1].duration, 100)
            compare(show.animations[1].easing.type, Easing.Linear)
            compare(hide.animations[0].duration, 500)
            compare(hide.animations[1].duration, 150)
            compare(hide.animations[1].easing.type, Easing.Linear)
        }

        function test_d60_22_fades_when_not_permanent() {
            var ind = createTemporaryObject(indicatorComp, top, { permanent: false })
            verify(ind)
            compare(ind.shownAlpha, 1)
            ind.moving = true
            ind.moving = false
            // the pager stopped: 1, still 1 inside the 500 ms pause, then 0
            compare(ind.shownAlpha, 1)
            wait(150)
            compare(ind.shownAlpha, 1)
            tryCompare(ind, "shownAlpha", 0, 3000)
            // the pager moves again: back to 1
            ind.moving = true
            tryCompare(ind, "shownAlpha", 1, 3000)
            ind.moving = false
            tryCompare(ind, "shownAlpha", 0, 3000)
        }

        function test_d60_22_permanent_stays() {
            var ind = createTemporaryObject(indicatorComp, top, { permanent: true })
            verify(ind)
            ind.moving = true
            ind.moving = false
            wait(1000)
            compare(ind.shownAlpha, 1)
            // the page under the icon becomes one that is not permanent at rest: it fades (jme.java:46-48)
            ind.permanent = false
            compare(ind.shownAlpha, 1)
            tryCompare(ind, "shownAlpha", 0, 3000)
            // and a permanent one sets it to 1 (jme.java:40-45)
            ind.permanent = true
            compare(ind.shownAlpha, 1)
        }

        // ---- N61-26: the expressive frame and CircleGrid

        function test_n61_26_expressive_frame() {
            var t = createTemporaryObject(expressiveComp, top, { pillText: "New", chipText: "Open",
                                                                  bottomLabel: "Daily Goal", bottomValue: "10,000" })
            verify(t)
            waitForRendering(t)
            shot(t, "n61-26-frame")
            // the icon fades (D60-22's permanent icon is the CP3A tiles'), no edge button, no bottom text
            compare(t.m3Layout, false)
            verify(!t.chip.visible)
            verify(!t.bottomText.visible)
            // the pill: 64 px at y 296, 104 px wide for 'New' (52 dp at least), centred; 48 dp touch; 13 sp label
            verify(t.pill.visible)
            var c = t.pill.container.mapToItem(t, 0, 0)
            // Noto Sans' 'New' is 2 px wider than the emulator's Google Sans: 106 px
            fuzzyCompare(c.x, 140, 2)
            fuzzyCompare(c.y, 296, 1)
            fuzzyCompare(t.pill.container.width, 104, 2)
            compare(t.pill.container.height, 64)
            compare(t.pill.height, 96)
            compare(t.pill.label.font.pixelSize, 26)
            compare(t.pill.text, "New")
            // no title: the content from 52 px to 20 px above the pill, 5.2 % sides
            compare(t.titleItem.height, 0)
            compare(t.body.y, 52)
            compare(t.body.y + t.body.height, 276)
            fuzzyCompare(t.body.x, 384 * 0.052, 0.01)
            // the pill's colour (primary by default) where the label is not
            var img = grabImage(t)
            near(img, 148, 327, String(Theme.color.primary), 3, "pill")
            // a longer label widens it: the label plus 12 dp each side
            t.pillText = "Contacts"
            waitForRendering(t)
            fuzzyCompare(t.pill.container.width, t.pill.label.implicitWidth + 48, 1)
            fuzzyCompare(t.pill.container.mapToItem(t, 0, 0).x + t.pill.container.width / 2, 192, 1)
            // without a pill no touch area is left and the content ends 19.6 % above the bottom
            t.pillText = ""
            verify(!t.pill.visible)
            fuzzyCompare(t.body.y + t.body.height, 384 - Math.round(384 * 0.196), 0.5)
            // a tap on the pill is pillClicked
            t.pillText = "New"
            var clicks = 0
            t.pillClicked.connect(function () { clicks++ })
            mouseClick(t, 192, 327)
            compare(clicks, 1)
        }

        function test_n61_26_expressive_title() {
            var t = createTemporaryObject(expressiveComp, top, { title: "Favorites", pillText: "Refresh" })
            verify(t)
            waitForRendering(t)
            // titleMedium 16 sp, white, its ink from 71 px (S14-c: 'Favorites' ink y 71-94)
            compare(t.titleItem.font.pixelSize, 32)
            compare(String(t.titleItem.color), String(Theme.color.onBackground))
            var img = grabImage(t)
            var rows = inkRows(img, 120, 264, 40, 120, 0.5)
            fuzzyCompare(rows.first, 71, 1.5)
            // the content starts under it
            verify(t.body.y >= t.titleItem.y + t.titleItem.height)
        }

        function test_n61_26_circle_grid() {
            var item = createTemporaryObject(gridComp, top, {})
            verify(item)
            var g = item.grid
            waitForRendering(item)
            shot(item, "n61-26-grid5")
            // five: two over three, 104 px, 16 px apart both ways
            compare(g.count, 5)
            for (var i = 0; i < 5; i++) {
                var cell = g.itemAt(i)
                compare(cell.width, 104)
                compare(cell.height, 104)
                // a TileCard: round (its radius half the side)
                compare(cell.radius, 52)
                var p = centre(item, cell)
                fuzzyCompare(p.x, fiveCentres[i][0], 1)
                fuzzyCompare(p.y, fiveCentres[i][1], 1)
            }
            var img = grabImage(item)
            near(img, 132, 104, "#182B2F", 3, "circle 0")
            near(img, 312, 224, "#182B2F", 3, "circle 4")
            // the gap between two circles is black
            near(img, 192, 104, "#000000", 3, "gap")
            // four: two over two
            item.n = 4
            waitForRendering(item)
            var four = [[132, 104], [252, 104], [132, 224], [252, 224]]
            for (var j = 0; j < 4; j++) {
                var q = centre(item, g.itemAt(j))
                fuzzyCompare(q.x, four[j][0], 1)
                fuzzyCompare(q.y, four[j][1], 1)
            }
            // three or fewer: one row in the middle of the body
            item.n = 3
            waitForRendering(item)
            for (var k = 0; k < 3; k++) {
                var r = centre(item, g.itemAt(k))
                fuzzyCompare(r.x, [72, 192, 312][k], 1)
                fuzzyCompare(r.y, 164, 1)
            }
            item.n = 1
            waitForRendering(item)
            fuzzyCompare(centre(item, g.itemAt(0)).x, 192, 1)
            // more than five: the first five, a sixth is not drawn
            item.n = 6
            waitForRendering(item)
            verify(g.itemAt(4).visible)
            verify(!g.itemAt(5).visible)
        }
    }

    TestCase {
        name: "ExpressiveTiles"
        when: windowShown

        function cleanup() {
            AlarmsMock.alarms = []
            AlarmsMock.creatable = false
            Lipstick.compositor = baseCompositor
            Backend.reset()
            desktop.launched = []
        }
        // the repo mock's compositor, put back after a test that sets the awake one
        property QtObject baseCompositor: null
        function initTestCase() {
            baseCompositor = Lipstick.compositor
        }
        function shot(item, name) {
            item.grabToImage(function (r) { r.saveToFile("/tmp/wo06-shots/" + name + ".png") })
            wait(50)
        }
        function near(img, x, y, rgb, tol, msg) {
            var c = img.pixel(x, y)
            var want = Qt.color(rgb)
            var ok = Math.abs(c.r - want.r) * 255 <= tol && Math.abs(c.g - want.g) * 255 <= tol && Math.abs(c.b - want.b) * 255 <= tol
            verify(ok, (msg || "") + " pixel " + x + "," + y + " is " + c + ", not " + rgb)
        }
        // the first and last rows in x0..x1 (every 2nd column) and y0..y1 with a pixel brighter than `level` (0..1)
        function inkRows(img, x0, x1, y0, y1, level) {
            var first = -1, last = -1
            for (var y = y0; y <= y1; y++) {
                for (var x = x0; x <= x1; x += 2) {
                    var c = img.pixel(x, y)
                    if (Math.max(c.r, c.g, c.b) > level) {
                        if (first < 0)
                            first = y
                        last = y
                        break
                    }
                }
            }
            return { first: first, last: last }
        }
        function centre(tile, it) {
            return it.mapToItem(tile, it.width / 2, it.height / 2)
        }
        function col(c) {
            return String(Qt.color(c))
        }
        readonly property var fiveCentres: [[132, 104], [252, 104], [72, 224], [192, 224], [312, 224]]

        // ---- N61-27: the Timer tile

        function test_n61_27_timer_idle() {
            var t = createTemporaryObject(timerComp, top, {})
            verify(t)
            waitForRendering(t)
            shot(t, "n61-27-timer")
            compare(t.mode, "idle")
            compare(t.title, "")
            // its app icon fades (D60-22's permanent icon no longer for the Timer tile)
            compare(t.m3Layout, false)
            verify(!t.chip.visible)
            // the presets out of the box: 5, 10, 15, 20, 30 min, two over three
            var g = findChild(t, "timerGrid")
            compare(g.count, 5)
            var texts = ["05", "10", "15", "20", "30"]
            var img = grabImage(t)
            for (var i = 0; i < 5; i++) {
                var b = g.itemAt(i)
                compare(b.width, 104)
                var p = centre(t, b)
                fuzzyCompare(p.x, fiveCentres[i][0], 1)
                fuzzyCompare(p.y, fiveCentres[i][1], 1)
                compare(col(b.containerColor), col("#182B2F"))
                var num = findChild(b, "timerNumber")
                compare(num.text, texts[i])
                // titleMedium 16 sp, white: S13's 22 px digits
                compare(num.font.pixelSize, 32)
                compare(col(num.color), col("#FFFFFF"))
                // the unit is the screen reader's
                compare(b.accessibleName, String(5 * [1, 2, 3, 4, 6][i]) + " Min")
                // the circle under the number (S13 #182B2F)
                near(img, fiveCentres[i][0], fiveCentres[i][1] + 36, "#182B2F", 3, "circle " + i)
            }
            // the digits of '05' (S13: ink x 117-146, y 92-113)
            var five = findChild(g.itemAt(0), "timerNumber")
            var q = five.mapToItem(t, 0, 0)
            fuzzyCompare(q.y + five.height / 2, 104, 2)
            // the cyan pill 'New' with a dark label (S13: #78D9EC, x 140-243, y 296-359)
            compare(t.pill.text, "New")
            compare(col(t.pillColor), col("#78D9EC"))
            compare(col(t.pillContentColor), col("#202124"))
            var c = t.pill.container.mapToItem(t, 0, 0)
            fuzzyCompare(c.y, 296, 1)
            fuzzyCompare(c.x + t.pill.container.width / 2, 192, 1)
            near(img, 148, 327, "#78D9EC", 3, "pill")
            // the pill asks the Timer app for its picker
            mouseClick(t, 192, 327)
            compare(desktop.launched, ["asteroid-timer"])
            verify(String(Backend.conf["/org/asteroidos/timer/open"]).indexOf("picker@") === 0)
        }

        function test_n61_27_timer_saved_list() {
            // the Timer app's saved list wins over the presets
            Backend.conf["/org/asteroidos/timer/recents"] = ["60", "90", "5400"]
            var t = createTemporaryObject(timerComp, top, {})
            verify(t)
            waitForRendering(t)
            var g = findChild(t, "timerGrid")
            compare(g.count, 3)
            compare(findChild(g.itemAt(0), "timerNumber").text, "01")
            compare(findChild(g.itemAt(1), "timerNumber").text, "1:30")
            compare(findChild(g.itemAt(2), "timerNumber").text, "1:30")
            compare(g.itemAt(2).accessibleName, "1:30 Hr:Min")
            // three in one row in the middle of the body
            fuzzyCompare(centre(t, g.itemAt(1)).y, 164, 1)
        }

        // ---- FP-L5 (alarms-timers-stopwatch-31): one timer at a time, the Timer app's rule

        function test_fp_l5_timer_one_at_a_time() {
            AlarmsMock.creatable = true
            var t = createTemporaryObject(timerComp, top, {})
            verify(t)
            compare(t.mode, "idle")
            // a circle starts the timer of its duration: one countdown, the running card
            mouseClick(findChild(t, "timerGrid").itemAt(0))
            compare(AlarmsMock.alarms.length, 1)
            compare(AlarmsMock.alarms[0].countdown, true)
            compare(AlarmsMock.alarms[0].minute, 5)
            tryCompare(t, "mode", "running")
            verify(!findChild(t, "timerGrid").visible)
            // a second start (a tap the model had not shown the first timer to yet): nothing more
            compare(t.start(600), false)
            compare(AlarmsMock.alarms.length, 1)
            // a paused timer is an active timer too
            var now = Math.floor(Date.now() / 1000)
            AlarmsMock.alarms = [AlarmsMock.make({ countdown: true, minute: 10, enabled: false, triggerTime: 0, elapsed: 120 })]
            compare(t.start(300), false)
            compare(t.mode, "paused")
            compare(AlarmsMock.alarms.length, 1)
            // a timer that rang is not: the next start makes the new one
            AlarmsMock.alarms = [AlarmsMock.make({ countdown: true, minute: 5, enabled: true, triggerTime: now - 10 })]
            verify(t.start(300))
            compare(AlarmsMock.alarms.length, 2)
            tryCompare(t, "mode", "running")
        }

        // ---- N61-28: the Alarm tile as the emulator's Next Alarm

        function test_n61_28_alarm_none() {
            var t = createTemporaryObject(alarmComp, top, {})
            verify(t)
            waitForRendering(t)
            shot(t, "n61-28-none")
            compare(t.mode, "none")
            compare(t.title, "")
            compare(t.m3Layout, false)
            verify(!t.pill.visible)
            verify(!t.chip.visible)
            // 'No alarms' in #BDC1C6, labelMedium, its ink from y 78 (S14: 78-99)
            var none = findChild(t, "alarmNone")
            verify(none.visible)
            compare(none.text, "No alarms")
            compare(col(none.color), col("#BDC1C6"))
            compare(none.font.pixelSize, 30)
            var img = grabImage(t)
            var r = inkRows(img, 110, 274, 50, 125, 0.4)
            fuzzyCompare(r.first, 78, 1.5)
            fuzzyCompare(r.last, 99, 1.5)
            // one stadium 268 x 120 px at y 132 in #FDE293 with 'Set new' in #202124 (S14: x 58-325, y 132-251)
            var card = findChild(t, "alarmNew")
            verify(card.visible)
            var p = card.mapToItem(t, 0, 0)
            fuzzyCompare(p.x, 58, 1)
            fuzzyCompare(p.y, 132, 1)
            compare(card.width, 268)
            compare(card.height, 120)
            compare(card.radius, 60)
            near(img, 80, 191, "#FDE293", 3, "stadium")
            var label = findChild(card, "alarmNewText")
            compare(label.text, "Set new")
            compare(col(label.color), col("#202124"))
            // it opens the alarm clock's picker
            mouseClick(t, 192, 191)
            compare(desktop.launched, ["asteroid-alarmclock"])
            verify(String(Backend.conf["/org/asteroidos/alarmclock/open"]).indexOf("new@") === 0)
        }

        // the tile's clock (TileBase.clock) at a fixed time: on the wall clock the time to go and the day
        // depended on the second the test ran in ('22h 57m' when the tile was made in the next minute)
        function fixedClock(ms) { return function () { return ms } }

        function test_n61_28_alarm_next() {
            // one alarm on, 22 h 58 min ahead (S14-d's preview): at 9:00 on 10 March, the alarm at 7:58
            var now = new Date(2026, 2, 10, 9, 0, 0)
            var at = new Date(now.getTime() + (22 * 60 + 58) * 60000)
            AlarmsMock.alarms = [{ id: 7, hour: at.getHours(), minute: at.getMinutes(), second: 0, daysOfWeek: "",
                                   enabled: true, countdown: false, triggerTime: 0, elapsed: 0 }]
            var t = createTemporaryObject(alarmComp, top, { clock: fixedClock(now.getTime()) })
            verify(t)
            waitForRendering(t)
            shot(t, "n61-28-next")
            compare(t.mode, "next")
            compare(t.m3Layout, false)
            verify(!t.pill.visible)
            verify(!findChild(t, "alarmNone").visible)
            var img = grabImage(t)
            // the time to go at the top, labelSmall, white (S14-d ink y 72-87)
            var until = findChild(t, "alarmUntil")
            compare(until.text, "22h 58m")
            compare(until.font.pixelSize, 26)
            var u = inkRows(img, 120, 264, 50, 110, 0.5)
            fuzzyCompare(u.first, 71, 2)
            // the stadium 268 x 100 px at y 138 with the horizontal gradient #FFF76D -> #FFEBAE
            var card = findChild(t, "alarmCard")
            var p = card.mapToItem(t, 0, 0)
            fuzzyCompare(p.x, 58, 1)
            fuzzyCompare(p.y, 138, 1)
            compare(card.width, 268)
            compare(card.height, 100)
            verify(card.gradient !== null)
            compare(card.gradient.orientation, Gradient.Horizontal)
            near(img, 66, 188, "#FFF76D", 8, "gradient start")
            near(img, 317, 188, "#FFEBAE", 8, "gradient end")
            // the time in #202124, displaySmall, tabular, AM/PM small after it
            var row = findChild(card, "alarmTimeRow")
            compare(col(row.color), col("#202124"))
            compare(row.timeLabel.font.pixelSize, 48)
            fuzzyCompare(centre(t, row).x, 192, 1)
            // the day under it in yellow (S14-d 'Tomorrow' ink y 290-305)
            var day = findChild(t, "alarmDay")
            compare(day.text, "Tomorrow")
            compare(col(day.color), col("#FFFD66"))
            var d = inkRows(img, 120, 264, 280, 320, 0.5)
            fuzzyCompare(d.first, 290, 2)
            // the time to go changes with ONE single shot a minute, only while the tile is awake
            verify(!t.awake)
            verify(!t.minuteTick.running)
            Lipstick.compositor = awakeCompositor
            verify(t.awake)
            verify(t.minuteTick.running)
            verify(t.minuteTick.interval > 0 && t.minuteTick.interval <= 60001, "interval " + t.minuteTick.interval)
            compare(t.minuteTick.repeat, false)
            // behind an app, or in ambient: no tick
            awakeCompositor.homeActive = false
            verify(!t.awake)
            verify(!t.minuteTick.running)
            awakeCompositor.homeActive = true
            verify(t.minuteTick.running)
            awakeCompositor.displayAmbient = true
            verify(!t.minuteTick.running)
            awakeCompositor.displayAmbient = false
            // a tap on the stadium opens the alarm clock
            mouseClick(t, 192, 188)
            compare(desktop.launched, ["asteroid-alarmclock"])
        }

        function test_n61_28_alarm_snoozed() {
            // snoozed: timed rings it again in 9 minutes, not at its own 7:00 (at 7:51 on 10 March)
            var now = new Date(2026, 2, 10, 7, 51, 0).getTime()
            var again = Math.floor(now / 1000) + 9 * 60
            var own = new Date((again - 3600) * 1000)
            AlarmsMock.alarms = [{ id: 3, hour: own.getHours(), minute: own.getMinutes(), second: 0, daysOfWeek: "",
                                   enabled: true, countdown: false, triggerTime: again, elapsed: 0 }]
            var t = createTemporaryObject(alarmComp, top, { clock: fixedClock(now) })
            verify(t)
            waitForRendering(t)
            compare(t.mode, "snoozed")
            var card = findChild(t, "alarmSnoozed")
            verify(card.visible)
            compare(col(card.containerColor), col("#FDE293"))
            // the pill 'Open' in the same yellow, no edge button
            verify(t.pill.visible)
            compare(t.pill.text, "Open")
            compare(col(t.pillColor), col("#FDE293"))
            verify(!t.chip.visible)
            mouseClick(t, 192, 327)
            compare(desktop.launched, ["asteroid-alarmclock"])
            compare(String(Backend.conf["/org/asteroidos/alarmclock/open"]).indexOf("alarm:3@"), 0)
        }

        // ---- N61-29: the Favorites tile

        function test_n61_29_favorites_trouble() {
            // a picture (preview): nothing is asked of a phone
            var t = createTemporaryObject(favoritesComp, top, { preview: true })
            verify(t)
            t.contactsLink.phase = "no-phone"
            waitForRendering(t)
            shot(t, "n61-29-trouble")
            compare(t.mode, "trouble")
            compare(t.m3Layout, false)
            verify(!t.chip.visible)
            // the title (S14-c: 'Favorites' ink y 71-94)
            compare(t.title, "Favorites")
            var img = grabImage(t)
            var r = inkRows(img, 100, 284, 40, 110, 0.5)
            fuzzyCompare(r.first, 71, 1.5)
            fuzzyCompare(r.last, 94, 1.5)
            // the message: white bodyLarge on 41 px lines, 80 % of the width, three lines from y 137
            var m = findChild(t, "favoritesMessage")
            compare(m.font.pixelSize, 32)
            compare(m.lineHeight, 41)
            compare(col(m.color), col("#FFFFFF"))
            fuzzyCompare(m.width, 307, 1)
            compare(m.lineCount, 3)
            var lines = []
            var inLine = false
            for (var y = 120; y < 270; y++) {
                var hit = false
                for (var x = 40; x < 344; x += 2) {
                    if (img.pixel(x, y).r > 0.5) {
                        hit = true
                        break
                    }
                }
                if (hit && !inLine)
                    lines.push(y)
                inLine = hit
            }
            compare(lines.length, 3)
            fuzzyCompare(lines[0], 137, 1.5)
            fuzzyCompare(lines[1] - lines[0], 41, 1.5)
            fuzzyCompare(lines[2] - lines[1], 41, 1.5)
            // the pill 'Refresh' in #AECBFA at y 296-359 (S14-c: 145 x 64 at x 119-263)
            compare(t.pill.text, "Refresh")
            compare(col(t.pillColor), col("#AECBFA"))
            compare(col(t.pillContentColor), col("#202124"))
            var c = t.pill.container.mapToItem(t, 0, 0)
            fuzzyCompare(c.y, 296, 1)
            fuzzyCompare(t.pill.container.width, 145, 5)
            near(img, c.x + 12, 327, "#AECBFA", 3, "pill")
            // the empty list: 'Add'
            t.contactsLink.phase = "ready"
            compare(t.mode, "empty")
            compare(t.pill.text, "Add")
        }

        function test_n61_29_favorites_grid() {
            var t = createTemporaryObject(favoritesComp, top, { preview: true })
            verify(t)
            var names = ["Apple", "Birch", "Cedar", "Dune", "Ember", "Fern"]
            t.contactsLink.contacts = names.map(function (n, i) { return { key: "k" + i, name: n, starred: true, photo: false } })
            t.contactsLink.phase = "ready"
            waitForRendering(t)
            shot(t, "n61-29-grid")
            compare(t.mode, "grid")
            // no title, five photos two over three, the pill 'Contacts'
            compare(t.title, "")
            var g = findChild(t, "favoritesGrid")
            compare(g.count, 5)
            for (var i = 0; i < 5; i++) {
                var cell = g.itemAt(i)
                compare(cell.width, 104)
                var p = centre(t, cell)
                fuzzyCompare(p.x, fiveCentres[i][0], 1)
                fuzzyCompare(p.y, fiveCentres[i][1], 1)
                compare(cell.accessibleName, names[i])
            }
            compare(t.pill.text, "Contacts")
            compare(col(t.pillColor), col("#AECBFA"))
            fuzzyCompare(t.pill.container.mapToItem(t, 0, 0).y, 296, 1)
        }
    }
}
