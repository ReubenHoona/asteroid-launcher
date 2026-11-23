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
// Shots go to /tmp/wo06-shots. Run by motion-wt/wo06/run.sh (qmltestrunner under qemu-aarch64 on the image
// rootfs; the tiles staged as module LauncherQml at their resource paths).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherQml

Item {
    id: top
    width: 384; height: 384

    // the launcher's context properties (lipstick localemanager.cpp, MainScreen's desktop)
    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: desktop; function openTilesEditor(addList) {} }

    Rectangle { anchors.fill: parent; color: "black" }

    Component { id: baseComp; TileBase { width: 384; height: 384 } }
    Component { id: indicatorComp; TilesIndicator { count: 1; position: 1 } }
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
    }
}
