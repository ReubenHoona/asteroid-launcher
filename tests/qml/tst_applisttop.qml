// WO-61-L5: the app list, Recents and the grid as Wear OS 6 draws them (emulator S04, S04-b, S04-c, S05, S05-b,
// S05-c), WearList with its edge transformation:
//  - N61-32: the list and Recents sit higher: a 20 px spacer and 31 px under the header, which the edge
//    transformation shrinks and packs against the first row: header cap top y 46 +- 3, first row top y 99 +- 2;
//    the grid: a 51 px spacer, header cap top y 72 +- 3, first discs y 130 +- 2, its header on the list's
//    transformation ("Apps" 78 px wide over the grid, 72 over the list, as the emulator); the intro slide is
//    still 0.2 of the height and ends there;
//  - N61-33: the "Grid view" / "List view" edge button: the label (ink y 270-291) above the view's glyph (list:
//    three bars, box 36 x 26 from y 312; grid: 3 x 3 dots, box 32 x 32 from y 309), in onPrimary #383F51;
//    "All apps" one centred line with no glyph (cap top y 297, the control's own, 3 px under the emulator's);
//  - N61-15: with the key unset the app list is the grid (Trays.qml's fallback), the list and the grid name the
//    emulator's glyphs.
// Staged as the qrc lays it out (st/qml, st/applauncher). Run by newlook-wt/l5h/run.sh (MODE=st).
import QtQuick
import QtTest
import org.asteroid.controls

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: alb
        function centerColor(p) { return "#3366aa" }
        function outerColor(p) { return "#000000" }
        function glyphColor(p) { return "#ffffff" }
        function ownIcon(p) { return false }
    }
    Rectangle { anchors.fill: parent; color: "black" }

    ListModel { id: rows }
    // the grid's cells as LauncherSortModel gives them: itemCount and get(i)
    QtObject {
        id: cells
        property int itemCount: 0
        property var items: []
        function get(i) { return items[i] }
    }
    Loader { id: ll; anchors.fill: parent; active: false; source: Qt.resolvedUrl("st/applauncher/wear/WearList.qml") }
    Loader { id: rl; anchors.fill: parent; active: false; source: Qt.resolvedUrl("st/applauncher/wear/WearRecents.qml") }

    TestCase {
        id: tc
        name: "AppListTop"
        when: windowShown

        function fill(n) {
            rows.clear()
            var a = []
            for (var i = 0; i < n; i++) {
                var o = { title: "App " + i, iconId: "ios-help", filePath: "/usr/share/applications/app" + i + ".desktop" }
                rows.append({ object: o })
                a.push(o)
            }
            cells.items = a
            cells.itemCount = n
        }

        // a WearList of `columns` with n items (the grid: cells), at rest at the top
        function list(columns, n, edgeText, edgeIcon) {
            rl.active = false
            ll.active = false
            fill(n)
            ll.active = true
            tryCompare(ll, "status", Loader.Ready, 20000)
            var l = ll.item
            l.headerText = "Apps"
            l.edgeText = edgeText
            l.edgeIcon = edgeIcon
            l.columns = columns
            if (columns > 1)
                l.cells = cells
            else
                l.model = rows
            l.resetPosition()
            wait(100)
            return l
        }
        function recents(n) {
            ll.active = false
            rl.active = false
            rl.active = true
            tryCompare(rl, "status", Loader.Ready, 20000)
            var l = rl.item
            var e = []
            for (var i = 0; i < n; i++)
                e.push({ item: { title: "App " + i, iconId: "ios-help", filePath: "/usr/share/applications/app" + i + ".desktop" },
                         key: "app" + i, desktop: "app" + i, front: false, ongoing: false, status: "" })
            l.entries = e
            l.resetPosition()
            wait(100)
            return l
        }

        function lum(c) { return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255 }
        function near(c, hex, tol) {
            var e = Qt.color(hex)
            return Math.abs(c.r - e.r) * 255 <= tol && Math.abs(c.g - e.g) * 255 <= tol && Math.abs(c.b - e.b) * 255 <= tol
        }
        // the first row from y0 down whose pixels x0..x1 have at least n bright (> thr) pixels
        function firstInk(img, x0, x1, y0, y1, thr, n) {
            for (var y = y0; y <= y1; y++) {
                var k = 0
                for (var x = x0; x <= x1; x++)
                    if (lum(img.pixel(x, y)) > thr)
                        k++
                if (k >= n)
                    return y
            }
            return -1
        }
        // the ink of the edge button's content (dark pixels inside the button: x 110-274, y 250-352, clear of
        // its outline and the bottom of its arch): rows grouped into runs
        function edgeInk(img) {
            var runs = [], cur = null
            for (var y = 250; y <= 352; y++) {
                var x0 = 1e9, x1 = -1
                for (var x = 110; x <= 274; x++) {
                    var c = img.pixel(x, y)
                    // darker than the halfway point between the container and the ink, and as blue as the ink
                    if (lum(c) < 150 && lum(c) > 20 && c.b >= c.r) {
                        x0 = Math.min(x0, x); x1 = Math.max(x1, x)
                    }
                }
                if (x1 >= 0) {
                    if (cur && cur.y1 === y - 1) {
                        cur.y1 = y; cur.x0 = Math.min(cur.x0, x0); cur.x1 = Math.max(cur.x1, x1)
                    } else {
                        cur = { y0: y, y1: y, x0: x0, x1: x1 }
                        runs.push(cur)
                    }
                }
            }
            return runs
        }
        // scrolled to the end: the edge button grows to its full height
        // the width of the header's ink (x 100-284) in the rows y0..y1
        function inkWidth(img, y0, y1) {
            var x0 = 1e9, x1 = -1
            for (var y = y0; y <= y1; y++)
                for (var x = 100; x <= 284; x++)
                    if (lum(img.pixel(x, y)) > 110) { x0 = Math.min(x0, x); x1 = Math.max(x1, x) }
            return x1 - x0 + 1
        }
        function toEnd(l) {
            var v = l.view
            v.contentY = v.originY + v.contentHeight + v.bottomMargin - v.height
            tryVerify(function () { return l.edgeButton.shownHeight > l.edgeButton.preferredHeight - 0.5 }, 3000, "the edge button in full")
            wait(100)
        }

        // ---- N61-32 ----

        function test_01_list_sits_higher() {
            var l = list(1, 8, "Grid view", "eos-view-grid")
            compare(l.topSpacer, 20)
            compare(l.headerBottom, 31)
            fuzzyCompare(l.view.topMargin, 99, 0.01)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/applist-top.png")
            // the first row's pill: its top at y 99 (stock S04 99)
            var pill = firstInk(img, 150, 234, 80, 150, 20, 60)
            verify(Math.abs(pill - 99) <= 2, "first row top " + pill)
            // the header's cap top at y 46 (stock 46)
            var cap = firstInk(img, 100, 284, 0, 95, 110, 2)
            verify(Math.abs(cap - 46) <= 3, "header cap top " + cap)
            // "Apps" shrunk to 72 px wide (stock S04-c 72)
            var w = inkWidth(img, cap, cap + 28)
            verify(Math.abs(w - 72) <= 3, "list header width " + w)
        }

        function test_02_recents_sits_higher() {
            var l = recents(3)
            compare(l.topSpacer, 20)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/recents-top.png")
            var pill = firstInk(img, 150, 234, 80, 150, 20, 60)
            verify(Math.abs(pill - 99) <= 2, "first row top " + pill)
            var cap = firstInk(img, 100, 284, 0, 95, 110, 2)
            verify(Math.abs(cap - 46) <= 3, "header cap top " + cap)
        }

        function test_03_grid_sits_lower_than_the_list() {
            var l = list(3, 12, "List view", "eos-view-list")
            compare(l.topSpacer, 51)
            compare(l.headerBottom, 31)
            fuzzyCompare(l.view.topMargin, 130, 0.01)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/grid-top.png")
            // the first discs' top at y 130 (stock S04-b 130)
            // (under the header's descenders)
            var disc = firstInk(img, 170, 214, 106, 170, 20, 8)
            verify(Math.abs(disc - 130) <= 2, "first discs top " + disc)
            var cap = firstInk(img, 100, 284, 0, 110, 110, 2)
            verify(Math.abs(cap - 72) <= 3, "header cap top " + cap)
            // on the list's transformation: "Apps" 78 px wide (stock S04-b 78; over the list 72)
            var w = inkWidth(img, cap, cap + 32)
            verify(Math.abs(w - 78) <= 3, "grid header width " + w)
        }

        function test_04_intro_slides_to_the_new_top() {
            var l = list(1, 8, "Grid view", "eos-view-grid")
            var y0 = l.headerItem.y
            l.intro()
            fuzzyCompare(l.introShift, 0.2 * 384, 1e-6)
            // where the layout draws the first row while the slide starts: 0.2 h lower
            verify(l.layout[1].y > 99 + 0.15 * 384, "the content starts lower: " + l.layout[1].y)
            tryCompare(l, "introShift", 0, 2000)
            fuzzyCompare(l.layout[1].y, 99, 0.01)
            compare(l.headerItem.y, y0)
        }

        // ---- N61-33 ----

        function test_05_list_end_grid_view_label_over_dots() {
            var l = list(1, 8, "Grid view", "eos-view-grid")
            toEnd(l)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/applist-end.png")
            var r = edgeInk(img)
            // the label and the three rows of dots
            verify(r.length === 2 || r.length === 4, "label and glyph: " + JSON.stringify(r))
            // the label: ink y 270-292 (no descenders in "Grid view")
            verify(Math.abs(r[0].y0 - 270) <= 2 && Math.abs(r[0].y1 - 291) <= 2, "label ink " + r[0].y0 + "-" + r[0].y1)
            // the dots: 3 x 3 of 8 px at 12 px, box 32 x 32 (stock S05-c 32 x 32 at x 175-206, y 309-340)
            var g = { x0: 1e9, x1: -1, y0: r[1].y0, y1: r[r.length - 1].y1 }
            for (var i = 1; i < r.length; i++) { g.x0 = Math.min(g.x0, r[i].x0); g.x1 = Math.max(g.x1, r[i].x1) }
            var gw = g.x1 - g.x0 + 1, gh = g.y1 - g.y0 + 1
            verify(Math.abs(gw - 32) <= 2 && Math.abs(gh - 32) <= 2, "grid glyph " + gw + " x " + gh)
            verify(Math.abs(g.y0 - 309) <= 2, "glyph top " + g.y0)
            verify(Math.abs((g.x0 + g.x1) / 2 - 191) <= 1.5, "glyph centred: " + g.x0 + "-" + g.x1)
            // the ink colour at a dot's centre
            var c = img.pixel(g.x0 + 4, g.y0 + 4)
            verify(near(c, "#383F51", 4), "glyph colour " + c)
        }

        function test_06_grid_end_list_view_label_over_bars() {
            var l = list(3, 12, "List view", "eos-view-list")
            toEnd(l)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/grid-end.png")
            var r = edgeInk(img)
            verify(r.length === 2 || r.length === 4, "label and glyph: " + JSON.stringify(r))
            verify(Math.abs(r[0].y0 - 270) <= 2 && Math.abs(r[0].y1 - 291) <= 2, "label ink " + r[0].y0 + "-" + r[0].y1)
            // the bars (one run, or three when a gap row shows between them): box 36 x 26 from y 312 (S05-b)
            var g0 = r[1].y0, g1 = r[r.length - 1].y1, gx0 = 1e9, gx1 = -1
            for (var i = 1; i < r.length; i++) { gx0 = Math.min(gx0, r[i].x0); gx1 = Math.max(gx1, r[i].x1) }
            verify(Math.abs(gx1 - gx0 + 1 - 36) <= 2 && Math.abs(g1 - g0 + 1 - 26) <= 2, "list glyph " + (gx1 - gx0 + 1) + " x " + (g1 - g0 + 1))
            verify(Math.abs(g0 - 312) <= 2, "glyph top " + g0)
            var c = img.pixel(192, g0 + 2)
            verify(near(c, "#383F51", 4), "glyph colour " + c)
        }

        function test_07_all_apps_one_line_no_glyph() {
            var l = recents(3)
            var v = l.view
            v.contentY = Math.max(v.originY - v.topMargin, v.originY + v.contentHeight + v.bottomMargin - v.height)
            wait(300)
            var img = grabImage(top)
            img.save("/tmp/l5h-shots/recents-end.png")
            var r = edgeInk(img)
            verify(r.length >= 1, "a label")
            verify(Math.abs(r[0].y0 - 294) <= 3, "All apps cap top " + r[0].y0)
            verify(Math.abs((r[0].x0 + r[0].x1) / 2 - 191.5) <= 3, "centred: " + r[0].x0 + "-" + r[0].x1)
            compare(r.length, 1, "no glyph under All apps")
        }

        // ---- N61-15 and the glyph names ----

        function test_08_views_and_default() {
            var xhr = new XMLHttpRequest()
            xhr.open("GET", Qt.resolvedUrl("st/qml/home/Trays.qml"), false)
            xhr.send()
            var t = xhr.responseText
            // (staged, the path is the stage's own)
            verify(new RegExp('defaultValue: "file://[^"]*/applauncher/007-wear-grid\\.qml"').test(t),
                   "the app list falls back to the grid")
            verify(t.indexOf("000-default-horizontal.qml") < 0, "not the AsteroidOS launcher")
            var g = new XMLHttpRequest()
            g.open("GET", Qt.resolvedUrl("st/applauncher/006-wear-list.qml"), false)
            g.send()
            verify(g.responseText.indexOf('edgeIcon: "eos-view-grid"') >= 0, "the list's button shows the grid glyph")
            var h = new XMLHttpRequest()
            h.open("GET", Qt.resolvedUrl("st/applauncher/007-wear-grid.qml"), false)
            h.send()
            verify(h.responseText.indexOf('edgeIcon: "eos-view-list"') >= 0, "the grid's button shows the list glyph")
        }
    }
}
