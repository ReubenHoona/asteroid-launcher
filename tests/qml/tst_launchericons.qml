// D60-26 (WO-10, launcher half): the app icons of the list, the grid, Recents and the launch splash take
// the glyph colour and the own-icon mark of the .desktop file (X-Eos-Glyph-Color, X-Eos-Own-Icon through
// AppLauncherBackground; tests/tst_launchericons.cpp reads the keys), and the glyph is about 0.67 of the
// disc as CP3A's adaptive icons draw theirs (alarm 0.69, stopwatch 0.71, timer 0.69, flashlight 0.72,
// phone 0.61 of the visible disc): the Icon box is 0.80 of the disc. The row's disc is 72 px, the grid's
// 96 px. Staged as the qrc lays it out (st/qml, st/applauncher); the icons are the image's.
// Run by motion-wt/wo10/run.sh (qmltestrunner under qemu-aarch64 on the image rootfs).
import QtQuick
import QtTest
import org.asteroid.controls

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    // AppLauncherBackground as the lists call it: per desktop file
    QtObject {
        id: alb
        function centerColor(p) { return p.indexOf("torch") >= 0 ? "#FFFFFF" : "#FFF965" }
        function outerColor(p) { return "#000000" }
        function glyphColor(p) { return p.indexOf("phone") >= 0 ? "#0057CC" : "#202124" }
        function ownIcon(p) { return p.indexOf("torch") >= 0 }
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader { id: rowLoader; x: 0; y: 0; width: 344; height: 104; source: Qt.resolvedUrl("st/applauncher/wear/WearRow.qml") }
    Loader { id: cellLoader; x: 0; y: 120; width: 96; height: 96; source: Qt.resolvedUrl("st/applauncher/wear/WearCell.qml") }
    Loader { id: splashLoader; x: 0; y: 0; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/qml/compositor/LaunchSplash.qml") }
    Loader { id: listLoader; x: 0; y: 0; width: 384; height: 384; active: false; source: Qt.resolvedUrl("st/applauncher/wear/WearRecents.qml") }

    TestCase {
        id: tc
        name: "LauncherIcons"
        when: windowShown

        // a loader's item, untyped (qmllint reads Loader.item as QObject)
        function itemOf(l) { return l.item }
        function findAll(item, pred, out) {
            if (pred(item))
                out.push(item)
            for (var i = 0; i < item.children.length; i++)
                findAll(item.children[i], pred, out)
            return out
        }
        function near(c, hex, tol) {
            var e = Qt.color(hex)
            return Math.abs(c.r - e.r) * 255 <= tol && Math.abs(c.g - e.g) * 255 <= tol && Math.abs(c.b - e.b) * 255 <= tol
        }
        function hexOf(c) {
            function h(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
            return "#" + h(c.r) + h(c.g) + h(c.b)
        }
        // the box of the pixels of colour hex (within 24) inside the disc (x, y, size) of an image
        function glyphBox(img, x, y, size, hex) {
            var x0 = 1e9, y0 = 1e9, x1 = -1, y1 = -1, n = 0
            var r = size / 2 - 2
            for (var j = 0; j < size; j++)
                for (var i = 0; i < size; i++)
                    if ((i + 0.5 - size / 2) * (i + 0.5 - size / 2) + (j + 0.5 - size / 2) * (j + 0.5 - size / 2) <= r * r
                            && near(img.pixel(x + i, y + j), hex, 24)) {
                        n++
                        x0 = Math.min(x0, i); x1 = Math.max(x1, i)
                        y0 = Math.min(y0, j); y1 = Math.max(y1, j)
                    }
            return { w: x1 - x0 + 1, h: y1 - y0 + 1, n: n }
        }

        function initTestCase() {
            tryCompare(rowLoader, "status", Loader.Ready, 30000)
            tryCompare(cellLoader, "status", Loader.Ready, 30000)
        }

        // the row: a #FFF965 disc (72 px) with a #202124 alarm glyph about 48 px (stock 46-50 px)
        function test_01_row_disc_and_glyph() {
            var row = itemOf(rowLoader)
            row.iconId = "ios-alarm-outline"
            row.discColor = "#FFF965"
            row.glyphColor = "#202124"
            row.ownIcon = false
            wait(100)
            var d = row.disc
            compare(d.width, 72, "the disc is 36 dp")
            var img = grabImage(row)
            // the disc's colour just inside its edge, on its horizontal axis
            var dc = img.pixel(d.x + 4, d.y + d.height / 2)
            verify(near(dc, "#FFF965", 4), "disc #FFF965: " + hexOf(dc))
            var b = glyphBox(img, d.x, d.y, d.width, "#202124")
            verify(b.n > 50, "glyph pixels in #202124: " + b.n)
            var big = Math.max(b.w, b.h)
            console.log("D60-26 row: alarm glyph " + b.w + " x " + b.h + " px on the 72 px disc")
            verify(big >= 46 && big <= 52, "the glyph's larger side about 48 px: " + b.w + " x " + b.h)
            fuzzyCompare(big / d.width, 0.67, 0.05)
        }

        // the grid's cell: the same glyph rule on its 96 px disc
        function test_02_cell_disc_and_glyph() {
            var cell = itemOf(cellLoader)
            cell.iconId = "ios-stopwatch-outline"
            cell.discColor = "#FFA082"
            cell.glyphColor = "#202124"
            cell.ownIcon = false
            wait(100)
            compare(cell.disc.width, 96, "the cell is 48 dp")
            // grabImage crops the window at the item's own x, y: grab the loader (at 0, 120 in the window)
            var img = grabImage(cellLoader)
            var dc = img.pixel(4, 48)
            verify(near(dc, "#FFA082", 4), "disc #FFA082: " + hexOf(dc))
            var b = glyphBox(img, 0, 0, 96, "#202124")
            var big = Math.max(b.w, b.h)
            console.log("D60-26 cell: stopwatch glyph " + b.w + " x " + b.h + " px on the 96 px disc")
            fuzzyCompare(big / 96, 0.69, 0.05, "stopwatch glyph " + b.w + " x " + b.h + " of 96")
        }

        // an own icon is drawn as it is: no disc, no tinted glyph
        function test_03_own_icon() {
            var row = itemOf(rowLoader)
            row.iconId = "asteroid-flashlight"
            row.discColor = "#FFFFFF"
            row.ownIcon = true
            wait(50)
            compare(row.disc.visible, false)
            var own = findAll(row, function (it) { return it.objectName === "ownIcon" }, [])
            compare(own.length, 1)
            compare(own[0].visible, true)
            // a white disc with a glyph colour is a disc (CP3A's white discs with blue glyphs)
            row.ownIcon = false
            row.glyphColor = "#0057CC"
            row.iconId = "ios-alarm-outline"
            wait(100)
            compare(row.disc.visible, true)
            compare(own[0].visible, false)
            var img = grabImage(row)
            verify(near(img.pixel(row.disc.x + 3, row.disc.y + 36), "#FFFFFF", 4), "white disc")
            verify(glyphBox(img, row.disc.x, row.disc.y, 72, "#0057CC").n > 50, "blue glyph")
        }

        // the lists hand each row the colours of its desktop file (WearList glyphOf / ownIconOf)
        function test_04_list_rows_take_the_desktop_keys() {
            listLoader.active = true
            tryCompare(listLoader, "status", Loader.Ready, 30000)
            var list = itemOf(listLoader)
            list.entries = [
                { item: { title: "Alarm", iconId: "ios-alarm-outline", filePath: "/usr/share/applications/alarm.desktop" }, status: "" },
                { item: { title: "Phone", iconId: "asteroid-phone", filePath: "/usr/share/applications/phone.desktop" }, status: "" },
                { item: { title: "Torch", iconId: "asteroid-flashlight", filePath: "/usr/share/applications/torch.desktop" }, status: "" }]
            var rows = []
            tryVerify(function () {
                rows = findAll(list, function (it) { return it.glyphColor !== undefined && it.ownIcon !== undefined && it.title !== undefined && it.title !== "" }, [])
                return rows.length === 3
            }, 5000, "three rows")
            var by = {}
            for (var i = 0; i < rows.length; i++)
                by[rows[i].title] = rows[i]
            verify(Qt.colorEqual(by["Alarm"].glyphColor, "#202124"))
            verify(Qt.colorEqual(by["Alarm"].discColor, "#FFF965"))
            compare(by["Alarm"].ownIcon, false)
            verify(Qt.colorEqual(by["Phone"].glyphColor, "#0057CC"))
            compare(by["Torch"].ownIcon, true)
            listLoader.active = false
        }

        // the launch splash: the app's disc, its glyph colour, the glyph 0.80 of the disc; own icons as they are
        function test_05_splash() {
            splashLoader.active = true
            tryCompare(splashLoader, "status", Loader.Ready, 30000)
            var s = itemOf(splashLoader)
            s.start(Qt.rect(0, 0, 0, 0), "#FFF965", "#000000", "ios-alarm-outline", "#202124", false)
            verify(Qt.colorEqual(s.discItem.color, "#FFF965"))
            verify(s.discItem.visible)
            verify(Qt.colorEqual(s.iconItem.color, "#202124"))
            verify(s.iconItem.visible)
            fuzzyCompare(s.iconItem.width / s.glyphItem.width, 0.80, 1e-6)
            s.cancel()
            // CP3A's white disc with a blue glyph
            s.start(Qt.rect(0, 0, 0, 0), "#FFFFFF", "#000000", "asteroid-phone", "#0057CC", false)
            verify(s.iconItem.visible, "a white disc with a glyph colour is a disc")
            verify(Qt.colorEqual(s.iconItem.color, "#0057CC"))
            s.cancel()
            // an own icon
            s.start(Qt.rect(0, 0, 0, 0), "#FFFFFF", "#FFFFFF", "asteroid-flashlight", "#FFFFFF", true)
            compare(s.iconItem.visible, false)
            s.cancel()
            // an older caller with no glyph colour: a white glyph, and a white centre colour is an own icon
            s.start(Qt.rect(0, 0, 0, 0), "#0044A6", "#000000", "ios-settings-outline")
            verify(Qt.colorEqual(s.iconItem.color, "white"))
            verify(s.iconItem.visible)
            s.cancel()
            s.start(Qt.rect(0, 0, 0, 0), "#FFFFFF", "#FFFFFF", "asteroid-flashlight")
            compare(s.iconItem.visible, false)
            s.cancel()
            splashLoader.active = false
        }
    }
}
