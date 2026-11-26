// WO-61-L5: the app list, Recents and the grid as Wear OS 6 draws them (emulator S04, S04-b, S04-c, S05, S05-b,
// S05-c), WearList with its edge transformation:
//  - N61-32: the list and Recents sit higher: a 20 px spacer and 31 px under the header, which the edge
//    transformation shrinks and packs against the first row: header cap top y 46 +- 3, first row top y 99 +- 2;
//    the grid: a 51 px spacer, header cap top y 72 +- 3, first discs y 130 +- 2, its header on the list's
//    transformation ("Apps" 78 px wide over the grid, 72 over the list, as the emulator); the intro slide is
//    still 0.2 of the height and ends there.
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
    }
}
