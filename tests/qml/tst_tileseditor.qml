// SPDX-License-Identifier: BSD-3-Clause
//
// The tiles editor (src/qml/tiles/TilesEditor.qml) and its add list (TileAddList.qml) in the Wear OS 6
// emulator's look, drawn with the image's controls on the repo mocks over the real Timer, Alarm and Favorites
// tiles. 384 x 384 px = 192 dp, 1 dp = 2 px.
//
// N61-30 (S13-b): the Add pill, a 104 x 64 px primary pill with a 28 px onPrimary plus at x 140-243, y 310-373,
// always in the bottom row's slot (the Edit chip there for a tile with settings); the move arrows are 64 px
// surfaceContainer discs at x 68 and 252, y 284, with the face picker's filled carets in primary, hidden with one
// tile; no "Add new" card at the carousel's end unless no card shows the pill; the tile's name in onSurface.
// N61-31 (S14-d): the add list's header 'Add', no app icon over the previews, the first rings' tops at y 88, the
// names white, their capitals 29 px under the ring.
// N61-35 (S13-b, S15): the cards' centre at rest is y 171 as the face picker's (FP.previewCy): the ring's box
// y 48-294, x 69-315.
//
// Shots go to /tmp/wo06-shots. Run as tst_tiles.qml (the tiles staged as module LauncherQml at their resource
// paths; newlook-wt/l4h/run.sh tiles).
import QtQuick
import QtTest
import org.asteroid.controls
import Nemo.Alarms
import LauncherQml
import "LauncherQml/tiles/tileseditor.js" as TE

Item {
    id: top
    width: 384; height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: desktop
        function openTilesEditor(addList) {}
        function launchByName(name, origin) {}
    }

    Rectangle { anchors.fill: parent; color: "black" }

    Component { id: editorComp; TilesEditor { idleEnabled: false } }

    TestCase {
        name: "TilesEditor"
        when: windowShown

        // three tiles without settings and one with (the Assistant's chips)
        readonly property var registry: ({
            timer: { file: "tiles/TimerTile.qml", name: "Timer", icon: "ios-timer-outline" },
            alarm: { file: "tiles/AlarmTile.qml", name: "Next Alarm", icon: "ios-alarm-outline" },
            favorites: { file: "tiles/FavoritesTile.qml", name: "Favorites", icon: "ms-contacts" },
            quickadd: { file: "tiles/QuickAddTile.qml", name: "Quick Add", icon: "ms-add", configure: true }
        })

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
        // every item under root with this objectName (children, a view's content)
        function findAll(root, name, out) {
            out = out || []
            if (!root)
                return out
            if (root.objectName === name && out.indexOf(root) < 0)
                out.push(root)
            var kids = root.children || []
            for (var i = 0; i < kids.length; i++)
                findAll(kids[i], name, out)
            if (root.contentItem && kids.indexOf(root.contentItem) < 0)
                findAll(root.contentItem, name, out)
            return out
        }
        function tileIds(ed) {
            var out = []
            for (var i = 0; i < ed.carousel.count; i++)
                out.push(ed.carousel.model.get(i).tileId)
            return out
        }
        function openEditor(list, at) {
            var ed = createTemporaryObject(editorComp, top, { registry: registry })
            verify(ed)
            ed.open(list, at)
            tryCompare(ed, "zoom", 1, 3000)
            tryCompare(ed, "namesOpacity", 1, 3000)
            return ed
        }

        // ---- N61-30

        function test_n61_30_one_tile() {
            var ed = openEditor(["timer"], 0)
            // no "Add new" card: the carousel holds the one tile
            compare(tileIds(ed), ["timer"])
            // the Add pill in the slot (S13-b: x 140-243, y 310-373)
            var pill = findChild(ed, "eosTilesAddPill")
            verify(pill)
            tryCompare(pill, "opacity", 1, 3000)
            var p = pill.mapToItem(ed, 0, 0)
            fuzzyCompare(p.x, 140, 0.5)
            fuzzyCompare(p.y, 310, 0.5)
            compare(pill.width, 104)
            compare(pill.height, 64)
            compare(pill.radius, 32)
            compare(String(pill.color), String(Theme.color.primary))
            // its 28 px plus in onPrimary
            var h = findChild(pill, "eosTilesAddPillH"), v = findChild(pill, "eosTilesAddPillV")
            compare(h.width, 28)
            compare(v.height, 28)
            compare(String(h.color), String(Theme.color.onPrimary))
            // no arrows with one tile, no Edit chip
            verify(!findChild(ed, "eosTilesLeft").visible)
            verify(!findChild(ed, "eosTilesRight").visible)
            verify(!findChild(ed, "eosTilesChip").visible)
            // the name in onSurface (S13-b #E8E7EE)
            var names = findAll(ed.carousel, "eosTilesName")
            verify(names.length > 0)
            compare(String(names[0].color), String(Theme.color.onSurface))
            waitForRendering(ed)
            shot(ed, "n61-30-one")
            var img = grabImage(ed)
            near(img, 150, 342, String(Theme.color.primary), 3, "pill")
            near(img, 191, 341, String(Theme.color.onPrimary), 3, "plus")
        }

        function test_n61_30_three_tiles() {
            var ed = openEditor(["timer", "alarm", "favorites"], 1)
            compare(tileIds(ed), ["timer", "alarm", "favorites"])
            var l = findChild(ed, "eosTilesLeft"), r = findChild(ed, "eosTilesRight")
            tryCompare(l, "opacity", 1, 3000)
            tryCompare(r, "opacity", 1, 3000)
            // the arrows beside the slot (S13-b, S15: x 68-131 and 252-315, y 284-347)
            var lp = l.mapToItem(ed, 0, 0), rp = r.mapToItem(ed, 0, 0)
            fuzzyCompare(lp.x, 68, 0.5)
            fuzzyCompare(rp.x, 252, 0.5)
            fuzzyCompare(lp.y, 284, 0.5)
            fuzzyCompare(rp.y, 284, 0.5)
            compare(l.width, 64)
            compare(String(l.color), String(Theme.color.surfaceContainer))
            // the face picker's filled carets in primary (D60-30), not the ios arrows
            var lg = findChild(l, "eosTilesLeftGlyph"), rg = findChild(r, "eosTilesRightGlyph")
            verify(lg && rg)
            compare(lg.data[0].fillColor, Theme.color.primary)
            compare(rg.data[0].fillColor, Theme.color.primary)
            waitForRendering(ed)
            shot(ed, "n61-30-three")
            var img = grabImage(ed)
            // the caret is filled: its middle is primary (24 dp box x2 = 48 px; the left caret's ink x 9-14 of 24)
            near(img, 68 + 32 - 2, 284 + 32, String(Theme.color.primary), 6, "caret")
            near(img, 68 + 8, 284 + 32, String(Theme.color.surfaceContainer), 3, "disc")
            // the pill opens the add list: Quick Add is left to add
            var pill = findChild(ed, "eosTilesAddPill")
            tryCompare(pill, "opacity", 1, 3000)
            mouseClick(pill)
            tryCompare(ed.addList, "visible", true, 3000)
            compare(ed.addList.tiles, ["quickadd"])
        }

        function test_n61_30_full_and_none_dialogs() {
            // every tile in the carousel: the pill says so (CP3A's dialog, as the card did)
            var ed = openEditor(["timer", "alarm", "favorites", "quickadd"], 0)
            var pill = findChild(ed, "eosTilesAddPill")
            tryCompare(pill, "opacity", 1, 3000)
            mouseClick(pill)
            tryCompare(ed.dialog, "shown", true, 3000)
            compare(ed.dialog.title, "All widgets in use")
            verify(!ed.addList.visible)
        }

        function test_n61_30_add_card_rules() {
            // the rule: an "Add new" card only with no tile or with every tile with settings
            compare(TE.needsAddCard([]), true)
            compare(TE.needsAddCard([true]), true)
            compare(TE.needsAddCard([true, false]), false)
            compare(TE.needsAddCard([false]), false)
            // the row is always laid out with the slot: the arrows at y 284 either way
            compare(TE.row(384, 384, true, true).arrowY, 284)
            compare(TE.row(384, 384, true, true).chip.y, 310)

            // a tile with settings in the middle: its Edit chip in the slot, no pill; it is the only tile, so
            // the carousel ends in "Add new"
            var ed = openEditor(["quickadd"], 0)
            compare(tileIds(ed), ["quickadd", ""])
            var chip = findChild(ed, "eosTilesChip"), pill = findChild(ed, "eosTilesAddPill")
            tryCompare(chip, "opacity", 1, 3000)
            compare(pill.opacity, 0)
            // a tile without settings added: the card goes, the pill is under the new tile
            verify(ed.addTile("timer", 192, 192, 160))
            compare(tileIds(ed), ["quickadd", "timer"])
            compare(ed.carousel.currentIndex, 1)
            tryCompare(pill, "opacity", 1, 3000)
            // removed again: the card is back and the middle is a real card
            verify(ed.remove(1))
            compare(tileIds(ed), ["quickadd", ""])
            verify(ed.carousel.currentIndex >= 0 && ed.carousel.currentIndex < 2)
            // the last tile removed: only "Add new" is left
            verify(ed.remove(0))
            compare(tileIds(ed), [""])
            compare(ed.carousel.currentIndex, 0)
        }

        function test_n61_30_remove_the_last_card() {
            // without the "Add new" card, removing the last tile in the middle centres the one before it
            var ed = openEditor(["timer", "alarm"], 1)
            compare(tileIds(ed), ["timer", "alarm"])
            verify(ed.remove(1))
            compare(tileIds(ed), ["timer"])
            compare(ed.carousel.currentIndex, 0)
            compare(ed.centredId, "timer")
        }

        // ---- N61-35

        function test_n61_35_centre() {
            var ed = openEditor(["timer", "alarm"], 0)
            fuzzyCompare(ed.previewCy, 171, 0.001)
            var cards = findAll(ed.carousel, "eosTilesPreview")
            var c = null
            for (var i = 0; i < cards.length; i++)
                if (Math.abs(cards[i].mapToItem(ed, cards[i].width / 2, 0).x - 192) < 1)
                    c = cards[i]
            verify(c, "the middle card")
            var tl = c.mapToItem(ed, 0, 0), br = c.mapToItem(ed, c.width, c.height)
            fuzzyCompare(tl.x, 69, 1)
            fuzzyCompare(br.x, 315, 1)
            fuzzyCompare(tl.y, 48, 1)
            fuzzyCompare(br.y, 294, 1)
        }

        // ---- N61-31

        function test_n61_31_add_list() {
            var ed = openEditor(["timer"], 0)
            ed.addTapped()
            var list = ed.addList
            tryCompare(list, "visible", true, 3000)
            wait(400)
            waitForRendering(ed)
            shot(ed, "n61-31-list")
            // the header 'Add' (S14-d)
            var title = findChild(list, "eosTileListTitle")
            compare(title.text, "Add")
            compare(String(title.color), String(Theme.color.onSurface))
            // no app icon over the previews
            compare(findAll(list.grid, "eosTileListIcon").length, 0)
            compare(TE.LIST_ICON, 0)
            // the first rings' tops at y 88 (S14-d), centred in their columns
            var rings = findAll(list.grid, "eosTileListRing")
            compare(rings.length, 3)
            rings.sort(function (a, b) {
                var pa = a.mapToItem(list, 0, 0), pb = b.mapToItem(list, 0, 0)
                return pa.y - pb.y || pa.x - pb.x
            })
            var p0 = rings[0].mapToItem(list, 0, 0)
            fuzzyCompare(p0.y, 88, 1)
            compare(rings[0].width, 168)
            compare(rings[0].border.width, 4)
            compare(String(rings[0].border.color), String(Qt.color("#404040")))
            fuzzyCompare(rings[1].mapToItem(list, 0, 0).y, 88, 1)
            // the name: white, one line, its box 22 px under the ring (capitals 29 px under it, S14-d y 284)
            var names = findAll(list.grid, "eosTileListName")
            var n0 = null
            for (var i = 0; i < names.length; i++)
                if (Math.abs(names[i].mapToItem(list, 0, 0).x + names[i].width / 2 - (p0.x + rings[0].width / 2)) < 1
                        && names[i].mapToItem(list, 0, 0).y < 300)
                    n0 = names[i]
            verify(n0)
            compare(String(n0.color), String(Theme.color.onBackground))
            compare(n0.maximumLineCount, 1)
            fuzzyCompare(n0.mapToItem(list, 0, 0).y - (p0.y + rings[0].height), 22, 0.5)
            var img = grabImage(ed)
            var first = -1
            for (var y = p0.y + rings[0].height + 4; y < p0.y + rings[0].height + 45 && first < 0; y++)
                for (var x = p0.x + 10; x < p0.x + rings[0].width - 10; x += 2)
                    if (img.pixel(x, y).r > 0.5) {
                        first = y
                        break
                    }
            fuzzyCompare(first - (p0.y + rings[0].height), 29, 2)
        }
    }
}
