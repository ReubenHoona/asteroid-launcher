// SPDX-License-Identifier: BSD-3-Clause
//
// The notification views drawn on the repo mocks with the controls of qml-asteroid (with its
// RotaryInput.flashIndicator): the stream's card (NotificationCard.qml), the heads-up's full view
// (notifications/HeadsUpDetail.qml), the glanceable-to-full-view morph (notifications/
// NotificationPreview.qml) and the stream (NotificationStream.qml), loaded from the launcher tree
// staged as its qrc lays it out (st/qml). 384 x 384 px = 192 dp, 1 dp = 2 px.
//  - D60-05: an open card shows its full layout alone, on its own open progress (openP, spring
//    800 / 0.8), as tall as the full layout (at least 64 dp); a card made open is open from its
//    first frame and takes a new height at once until the user toggles it;
//  - D60-06: CP3A's full_view_scrim, a black full-screen layer under the morph, neither scaled
//    nor faded by it (the face never shows through); the crown's close takes it with the view;
// Shots go to /tmp/wo02-shots. Run by motion-wt/wo02/run.sh (qmltestrunner under qemu-aarch64 on
// the image rootfs; the controls cross-built from qml-asteroid).
import QtQuick
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick

Item {
    id: top
    width: 384
    height: 384

    // the launcher's context objects the views read
    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: initialSize; property int width: 384; property int height: 384 }
    QtObject {
        id: notificationPreviewPresenter
        property QtObject notification: null
        property int kind: 0
        property bool showImmediately: false
        property bool waiting: false
        property bool faceCurrent: false
        property bool surfaceBusy: false
        property bool detailOpen: false
        property int nextCalls: 0
        function showNextNotification() { nextCalls++ }
    }
    // the panels grid as the stream reads it
    QtObject {
        id: gridMock
        property int currentVerticalPos: 0
        property int currentHorizontalPos: 0
        property real normalizedVerOffset: 0
        property bool trayDragging: false
        property QtObject trayAnimation: QtObject { property bool running: false }
        function changeAllowedDirections() { }
    }

    Component {
        id: notifC
        QtObject {
            property string appName: "Messages"
            property int replacesId: 1
            property string appIcon: ""
            property string icon: ""
            property string summary: "Sam"
            property string body: "On my way"
            property var hints: ({})
            property var actions: []
            property var timestamp: new Date()
            property bool userRemovable: true
            property string category: ""
            function removeRequested() { }
            function actionInvoked(name) { }
        }
    }

    // measures a card title (D60-05)
    TextMetrics { id: titleMetrics }

    // the face under the heads-up: white, so anything that lets it through shows
    Rectangle {
        id: face
        anchors.fill: parent
        color: "#ffffff"
    }
    Item {
        id: host
        anchors.fill: parent
    }

    TestCase {
        id: tc
        name: "Notifications"
        when: windowShown

        property var made: []

        function make(file, props) {
            var c = Qt.createComponent(Qt.resolvedUrl("st/qml/" + file))
            if (c.status !== Component.Ready)
                fail(file + ": " + c.errorString())
            var o = c.createObject(host, props || {})
            verify(o !== null, file + " made")
            made.push(o)
            return o
        }
        function notif(props) {
            var n = notifC.createObject(top, props || {})
            made.push(n)
            return n
        }
        function cleanup() {
            for (var i = made.length - 1; i >= 0; i--)
                if (made[i]) made[i].destroy()
            made = []
            notificationPreviewPresenter.notification = null
            gridMock.currentVerticalPos = 0
            gridMock.normalizedVerOffset = 0
            gridMock.trayDragging = false
            gridMock.trayAnimation.running = false
            var ind = indicator()
            if (ind)
                ind.shown = false
            wait(50)
        }

        function findAll(item, pred, out) {
            out = out || []
            if (!item)
                return out
            if (pred(item))
                out.push(item)
            var kids = item.children
            for (var i = 0; kids && i < kids.length; i++)
                findAll(kids[i], pred, out)
            var d = item.data
            for (var j = 0; d && j < d.length; j++)
                if (d[j] && d[j].children === undefined && d[j].objectName !== undefined && pred(d[j]))
                    out.push(d[j])
            return out
        }
        function byName(root, name) {
            var r = findAll(root, function (it) { return it.objectName === name })
            return r.length ? r[0] : null
        }
        // the shared scroll indicator RotaryInput puts on the window (PositionIndicator)
        function indicator() {
            var root = top
            while (root.parent)
                root = root.parent
            var kids = root.children
            for (var i = 0; i < kids.length; i++) {
                var k = kids[i]
                if (k.flickable !== undefined && k.shown !== undefined && typeof k.flash === "function")
                    return k
            }
            return null
        }
        // the card's collapsed layer and full-text loader (by name; the pre-D60-05 card had none)
        function collapsedLayer(card) {
            var l = byName(card, "collapsedLayer")
            if (l)
                return l
            var t = findAll(card, function (it) { return it.compact === true })
            return t.length ? t[0].parent : null
        }
        function fullLoader(card) {
            var l = byName(card, "fullLoader")
            if (l)
                return l
            var f = findAll(card, function (it) { return it.sourceComponent !== undefined && it.objectName !== "actionsLoader" })
            return f.length ? f[0] : null
        }
        function settle(card) {
            tryVerify(function () { return !card.animating }, 8000, "the card's springs at rest")
            wait(30)
        }
        function px(img, x, y) {
            var c = img.pixel(x, y)
            return [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]
        }
        function shot(item, name) {
            var img = grabImage(item)
            img.save("/tmp/wo02-shots/" + name + ".png")
            return img
        }

        /* ---- D60-05: the open card ------------------------------------- */

        // A stream card opened by the user: its own open progress on the 800 / 0.8 spring; open, the
        // full layout alone (collapsed layer gone, full text and actions at 1) at the full layout's
        // height; closed again, the collapsed layout alone
        function test_d60_05_toggle() {
            var n = notif({ replacesId: 51, summary: "Appointment reminder for tomorrow", body: "" })
            var c = make("NotificationCard.qml", { width: 344, notification: n })
            wait(100)
            compare(c.openP, 0, "made closed: openP 0")
            compare(c.openAnimation.stiffness, 800)
            compare(c.openAnimation.dampingRatio, 0.8)
            compare(c.heightAnimation.stiffness, 800)
            compare(c.heightAnimation.dampingRatio, 0.8)
            compare(collapsedLayer(c).opacity, 1)
            verify(!fullLoader(c).active, "no full layer while closed")
            fuzzyCompare(c.shownHeight, c.collapsedHeight, 0.5)
            var collapsedH = c.collapsedHeight

            c.expanded = true
            verify(c.openAnimation.running, "the open progress animates")
            settle(c)
            console.log("D60-05 wide title: collapsed " + collapsedH + " full surface " + c.surfaceFullHeight
                        + " actions " + c.actionsFullHeight + " shown " + c.shownHeight)
            compare(c.openP, 1)
            compare(collapsedLayer(c).opacity, 0, "collapsed layer faded out")
            verify(!collapsedLayer(c).visible, "collapsed layer not drawn")
            verify(fullLoader(c).active && fullLoader(c).visible, "full layer drawn")
            compare(fullLoader(c).opacity, 1)
            var target = Math.max(128, c.surfaceFullHeight + c.actionsFullHeight)
            fuzzyCompare(c.shownHeight, target, 0.5)
            fuzzyCompare(c.surfaceHeight, c.actionsFullHeight > 0 ? c.surfaceFullHeight : c.shownHeight, 0.5)
            shot(c, "d60-05-open")

            c.expanded = false
            settle(c)
            compare(c.openP, 0)
            compare(collapsedLayer(c).opacity, 1)
            verify(!fullLoader(c).active, "full layer gone once closed")
            fuzzyCompare(c.shownHeight, collapsedH, 0.5)
        }

        // A short notification's full layout is no taller than its collapsed one (the S10 card: the
        // image 59 card then kept the collapsed layout, its open progress being 0): open, it shows
        // the full layer alone
        function test_d60_05_full_not_taller() {
            var n = notif({ replacesId: 52, summary: "Sam", body: "On my way" })
            var c = make("NotificationCard.qml", { width: 344, notification: n })
            wait(100)
            var collapsedH = c.collapsedHeight
            c.expanded = true
            settle(c)
            var full = c.surfaceFullHeight + c.actionsFullHeight
            console.log("D60-05 short card: collapsed " + collapsedH + " full " + full + " shown " + c.shownHeight)
            verify(full <= collapsedH + 0.5, "the full layout is no taller")
            compare(c.openP, 1)
            verify(!collapsedLayer(c).visible, "collapsed layer not drawn")
            compare(fullLoader(c).opacity, 1)
            verify(fullLoader(c).visible, "full layer drawn")
            fuzzyCompare(c.shownHeight, Math.max(128, full), 0.5)
        }

        // A title that wraps in the collapsed card's 304 px but fits the open card's 316 px (the
        // open text sits 7 dp from the edge, the collapsed 10 dp): the open card is one title line
        // lower than the collapsed one, and is as tall as that, not held to the collapsed height
        function test_d60_05_full_lower() {
            var probe = notif({ replacesId: 55, summary: "x", body: "On my way" })
            var c0 = make("NotificationCard.qml", { width: 344, notification: probe })
            wait(50)
            var tl = findAll(collapsedLayer(c0), function (it) { return it.text === "x" && it.font !== undefined })[0]
            verify(tl !== undefined, "the collapsed title")
            var tm = titleMetrics
            tm.font = tl.font
            // whole words to under 290 px, then a last word grown a narrow letter at a time
            var words = "Your table for two at the harbour restaurant is ready now so please come to the front desk".split(" ")
            var base = ""
            for (var k = 1; k <= words.length; k++) {
                tm.text = words.slice(0, k).join(" ")
                if (tm.advanceWidth >= 290)
                    break
                base = tm.text
            }
            var title = ""
            for (var j = 1; j < 40 && title === ""; j++) {
                tm.text = base + " " + "sliiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii".substring(0, j)
                if (tm.advanceWidth > 306 && tm.advanceWidth < 314)
                    title = tm.text
            }
            verify(title !== "", "a title between 306 and 314 px")
            console.log("D60-05 title '" + title + "' " + tm.advanceWidth + " px")
            var n = notif({ replacesId: 56, summary: title, body: "On my way" })
            var c = make("NotificationCard.qml", { width: 344, notification: n })
            wait(100)
            var collapsedH = c.collapsedHeight
            c.expanded = true
            settle(c)
            var full = c.surfaceFullHeight + c.actionsFullHeight
            console.log("D60-05 lower: collapsed " + collapsedH + " full " + full + " shown " + c.shownHeight)
            verify(full < collapsedH - 10, "the full layout is a line lower")
            compare(c.openP, 1)
            verify(!collapsedLayer(c).visible, "collapsed layer not drawn")
            compare(fullLoader(c).opacity, 1)
            fuzzyCompare(c.shownHeight, Math.max(128, full), 0.5)
            verify(c.shownHeight < collapsedH - 10, "not held to the collapsed height")
        }

        // A card made open (the heads-up's full view) is open from its first frame, at its full
        // height, nothing moving; a new height is taken at once until the user toggles the card,
        // then it goes on the spring
        function test_d60_05_made_open() {
            var n = notif({ replacesId: 53, summary: "Sam", body: "On my way" })
            var c = make("NotificationCard.qml", { width: 344, notification: n, expanded: true })
            compare(c.openP, 1, "open at once")
            verify(!c.heightAnimation.running, "no opening animation")
            verify(!c.openAnimation.running, "no fade")
            compare(collapsedLayer(c).opacity, 0)
            compare(fullLoader(c).opacity, 1)
            wait(100)
            compare(c.openP, 1)
            verify(!collapsedLayer(c).visible, "only the full layer (S10-b / S10-c)")
            fuzzyCompare(c.shownHeight, Math.max(128, c.surfaceFullHeight + c.actionsFullHeight), 0.5)

            var h0 = c.shownHeight
            n.body = "On my way, the train is running about twenty minutes late tonight, sorry, see you at the station"
            wait(50)
            verify(c.surfaceFullHeight + c.actionsFullHeight > h0 + 10, "the full layout grew")
            verify(!c.heightAnimation.running, "taken at once (not toggled yet)")
            fuzzyCompare(c.shownHeight, Math.max(128, c.surfaceFullHeight + c.actionsFullHeight), 0.5)

            c.expanded = false
            settle(c)
            c.expanded = true
            settle(c)
            var h1 = c.shownHeight
            n.body = "Short"
            wait(20)
            verify(c.heightAnimation.running, "toggled: a new height goes on the spring")
            settle(c)
            verify(c.shownHeight < h1, "shrank")
            fuzzyCompare(c.shownHeight, Math.max(128, c.surfaceFullHeight + c.actionsFullHeight), 0.5)
        }

        // The heads-up's full view: its card shows the full layer alone at once and later
        function test_d60_05_detail_card() {
            var n = notif({ replacesId: 54, summary: "Sam", body: "On my way" })
            var d = make("notifications/HeadsUpDetail.qml", { width: 384, height: 384, notification: n })
            tryVerify(function () { return d.card !== null }, 3000, "the open card")
            compare(d.card.openP, 1)
            verify(!collapsedLayer(d.card).visible)
            wait(1500)
            compare(d.card.openP, 1)
            verify(!collapsedLayer(d.card).visible, "still the full layer only")
            compare(fullLoader(d.card).opacity, 1)
        }

        /* ---- D60-06: the morph's scrim ---------------------------------- */

        function preview() {
            var p = make("notifications/NotificationPreview.qml", {})
            return p
        }
        function scrimOf(p) { return byName(p, "fullViewScrim") }

        // While the glanceable turns into the full view nothing of the face shows: a black layer
        // under both, the screen's size, at 1 and unscaled whatever the morph's scales
        function test_d60_06_scrim() {
            var p = preview()
            var n = notif({ replacesId: 61, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            compare(p.mode, "glance")
            var s = scrimOf(p)
            verify(s !== null, "a scrim")
            verify(s.visible, "under the glanceable")
            compare(s.width, 384)
            compare(s.height, 384)
            compare(String(s.color), "#000000")
            compare(s.opacity, 1)
            compare(s.scale, 1)
            verify(s.z < p.detailHost.z, "under the full view")
            p.toFull()
            tryCompare(p, "mode", "full", 3000)
            compare(s.opacity, 1)
            compare(s.scale, 1)
            verify(s.visible)
            tryVerify(function () { return p.detailScale === 1 && p.detailOpacity === 1 }, 3000, "morph over")
            // the morph's first frames of the full view: 0.85, the glanceable gone
            p.glanceOpacity = 0
            p.detailScale = 0.85
            wait(100)
            var img = shot(top, "d60-06-morph")
            // between the scaled view's disc (radius 163 px) and the screen's edge: black, not the face
            compare(px(img, 192, 12), [0, 0, 0], "top ring")
            compare(px(img, 12, 192), [0, 0, 0], "left ring")
            compare(px(img, 372, 192), [0, 0, 0], "right ring")
            compare(px(img, 192, 372), [0, 0, 0], "bottom ring")
            p.detailScale = 1
        }

        // The crown's close takes the scrim with the view (CP3A animates the whole root, juh.java:647)
        function test_d60_06_crown_close() {
            var p = preview()
            var n = notif({ replacesId: 62, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            p.toFull()
            tryVerify(function () { return p.mode === "full" && p.detailScale === 1 }, 3000)
            var s = scrimOf(p)
            p.closeFromCrown()
            tryVerify(function () { return p.detailOpacity < 0.9 && p.detailOpacity > 0.1 }, 3000, "mid-close")
            fuzzyCompare(s.opacity, p.detailOpacity, 0.0001)
            fuzzyCompare(s.scale, p.detailScale, 0.0001)
            tryCompare(p, "mode", "none", 3000)
            verify(!s.visible)
        }

        // The bubble over an app leaves the app showing: no scrim
        function test_d60_06_bubble_no_scrim() {
            var p = preview()
            var n = notif({ replacesId: 63, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 2
            notificationPreviewPresenter.notification = n
            compare(p.mode, "bubble")
            verify(!scrimOf(p).visible, "no scrim over the app")
        }
    }
}
