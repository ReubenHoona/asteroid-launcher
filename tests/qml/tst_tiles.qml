// SPDX-License-Identifier: BSD-3-Clause
//
// The tile frame (src/qml/tiles/TileBase.qml) drawn with the image's controls on the repo mocks.
// 384 x 384 px = 192 dp, 1 dp = 2 px.
//
// D60-21: the bottom text is CP3A's two lines (Fitbit tile_primarygoal/heartrate/sleep_preview.xml, Weather
// sun/uv_tile_preview.webp): the label, then the value (with its icon) under it, each line centred and fitted to
// the slot between the 26 % side margins (x 99.84-284.16; 6 dp, 5.2 % and 26 %: deskclock cno.java:443-447).
// The value stays whole, a label too long for the slot ends in an ellipsis; nothing is drawn outside the slot.
// Label 14 sp (titleSmall), value 16 sp (titleMedium), 5.2 % from the bottom, 6 dp under the content.
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
    Loader { id: stepsLoader; width: 384; height: 384; active: false; source: Qt.resolvedUrl("LauncherQml/tiles/StepsTile.qml") }

    TestCase {
        name: "Tiles"
        when: windowShown

        // the slot between the 26 % side margins
        readonly property real slotLeft: 384 * 0.26
        readonly property real slotRight: 384 - 384 * 0.26
        // the loaded tiles (untyped: the members are the tiles' own)
        readonly property var stepsTile: stepsLoader.item

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
    }
}
