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
//  - D60-07: when the morph ends (CP3A's onFullViewShown) the full view shows CP3A's header arrow
//    (shy_view_header_arrow: the Lottie held at progress 0.75, turned 180 degrees in a 24 dp view
//    8 dp below the top) and fades it 150 ms later over 300 ms, and (D60-09) the scroll indicator
//    shows on its list for 2 s (RotaryInput.flashIndicator); grown from the bubble, the indicator
//    only (CP3A's heads-up view, ktk.java:139-158, runs no klg);
//  - D60-08: the empty stream's filled trophy (trophy_40px at 28 dp) and its 140 dp text box with
//    7.3 % side padding (kvn.java);
//  - D60-09: the stream's scroll indicator shows for 2 s once the tray is fully open and at rest,
//    not while a page (a reply or a menu) is open over the list.
// Shots go to /tmp/wo02-shots. Run by motion-wt/wo02/run.sh (qmltestrunner under qemu-aarch64 on
// the image rootfs; the controls cross-built from qml-asteroid).
import QtQuick
import QtQuick.Shapes
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

    // a page over the stream's list, as the reply and menu pages are (LayerStack sets these)
    Component {
        id: pageC
        Item {
            property int depth: 0
            property var pop: null
            property int innerDepth: 0
        }
    }

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

        /* ---- D60-07, D60-09: the full view comes in ---------------------- */

        function longBody() {
            return "The 7:42 to the city is cancelled. The next service leaves at 8:12 from platform 2. "
                 + "Replacement buses run every ten minutes between the stations on the line, "
                 + "allow an extra thirty minutes for your trip. We are sorry for the trouble."
        }

        // The header arrow: CP3A's chevron at Lottie progress 0.75 in a 24 dp view 8 dp below the
        // top, turned to point down: ends 7.52 dp each side and 2.95 dp above the view's centre, the
        // point 2.79 dp below it, white, a 2 dp stroke with flat ends and a mitred point
        function test_d60_07_arrow_shape() {
            var n = notif({ replacesId: 71, summary: "Trains", body: longBody() })
            var d = make("notifications/HeadsUpDetail.qml", { width: 384, height: 384, notification: n })
            tryVerify(function () { return d.card !== null }, 3000)
            var a = byName(d, "headerArrow")
            verify(a !== null, "an arrow")
            compare(d.arrowOpacity, 0, "not shown before the view has come in")
            verify(!a.visible)
            var sp = a.data[0]
            compare(String(sp.strokeColor), "#ffffff")
            compare(sp.strokeWidth, 4)
            compare(sp.capStyle, ShapePath.FlatCap)
            compare(sp.joinStyle, ShapePath.MiterJoin)
            compare(String(sp.fillColor), "#00000000")
            var pts = sp.pathElements[0].path
            compare(pts.length, 3)
            fuzzyCompare(pts[0].x, 192 - 15.038, 0.01)
            fuzzyCompare(pts[0].y, 34.103, 0.01)
            fuzzyCompare(pts[1].x, 192 + 0.167, 0.01)
            fuzzyCompare(pts[1].y, 45.570, 0.01)
            fuzzyCompare(pts[2].x, 192 + 15.038, 0.01)
            fuzzyCompare(pts[2].y, 34.103, 0.01)
            // drawn: the arms and the point white, inside the V and beside it black
            d.entered()
            d.arrowAnimation.stop()
            d.arrowOpacity = 1
            wait(100)
            var img = shot(d, "d60-07-arrow")
            compare(px(img, 180, 36), [255, 255, 255], "left arm")
            compare(px(img, 204, 36), [255, 255, 255], "right arm")
            compare(px(img, 192, 45), [255, 255, 255], "the point")
            compare(px(img, 192, 38), [0, 0, 0], "inside the V")
            compare(px(img, 170, 34), [0, 0, 0], "left of the arm's end")
            compare(px(img, 192, 52), [0, 0, 0], "below the point")
        }

        // entered() (CP3A's onFullViewShown, klg.c()): the arrow at 1, held 150 ms, then gone over
        // 300 ms (PathInterpolator 0.3, 0, 1, 1); the scroll indicator shows on the full view's list
        // and hides 2 s later
        function test_d60_07_09_entered() {
            var n = notif({ replacesId: 72, summary: "Trains", body: longBody() })
            var d = make("notifications/HeadsUpDetail.qml", { width: 384, height: 384, notification: n })
            tryVerify(function () { return d.card !== null }, 3000)
            wait(200)
            var an = d.arrowAnimation
            compare(an.animations[0].duration, 150, "held 150 ms")
            compare(an.animations[1].duration, 300, "fades over 300 ms")
            compare(an.animations[1].to, 0)
            compare(an.animations[1].easing.type, Easing.BezierSpline)
            compare(an.animations[1].easing.bezierCurve, [0.3, 0, 1, 1, 1, 1])
            verify(d.scroller !== null)
            verify(d.scroller.contentHeight > d.scroller.height, "a full view that scrolls")
            var shown = d.entered()
            verify(d.shown, "shown")
            compare(d.arrowOpacity, 1, "the arrow at once")
            verify(shown, "flashIndicator took the full view's list")
            var ind = indicator()
            verify(ind !== null, "the shared indicator")
            compare(ind.flickable, d.scroller)
            verify(ind.shown, "the indicator shows")
            tryCompare(d, "arrowOpacity", 0, 3000, "the arrow fades")
            verify(ind.shown, "the indicator outlasts the arrow")
            tryVerify(function () { return !ind.shown }, 4000, "the indicator hides 2 s later")
        }

        // The morph ends, then the view comes in: the arrow and the indicator follow the morph
        // (CP3A: kmp.onAnimationEnd -> klg.c())
        function test_d60_07_09_after_morph() {
            var p = preview()
            var n = notif({ replacesId: 73, summary: "Trains", body: longBody() })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            p.toFull()
            tryVerify(function () { return p.detailItem !== null }, 3000)
            var d = p.detailItem
            verify(!d.shown, "not before the morph ends")
            var at = null
            d.shownChanged.connect(function () { at = { scale: p.detailScale, opacity: p.detailOpacity, glance: p.glanceOpacity } })
            var most = 0
            d.arrowOpacityChanged.connect(function () { most = Math.max(most, d.arrowOpacity) })
            tryVerify(function () { return d.shown }, 4000, "in when the morph ends")
            verify(at !== null)
            compare(at.scale, 1, "the morph was over: scale 1")
            compare(at.opacity, 1, "opacity 1")
            compare(at.glance, 0, "the glanceable gone")
            compare(most, 1, "the header arrow shows after the morph (klg.c())")
            tryVerify(function () { var ind = indicator(); return ind && ind.shown && ind.flickable === d.scroller }, 2000,
                      "the indicator on the full view's list")
        }

        // The bubble grown into the full view over an app: the scroll indicator once it has grown,
        // and no header arrow show and fade: CP3A's heads-up builds its own expanded view
        // (ktk.java:139-158) that no klg runs (klg.c() only at the morph's end, jpb.java:370-371)
        function test_d60_07_09_bubble() {
            var p = preview()
            var n = notif({ replacesId: 74, summary: "Trains", body: longBody() })
            notificationPreviewPresenter.kind = 2
            notificationPreviewPresenter.notification = n
            compare(p.mode, "bubble")
            p.bubbleItem.expand()
            tryVerify(function () { return p.detailItem !== null }, 3000)
            var d = p.detailItem
            verify(!d.shown, "not while it grows")
            var a = byName(d, "headerArrow")
            verify(a !== null, "the arrow item")
            var most = 0
            d.arrowOpacityChanged.connect(function () { most = Math.max(most, d.arrowOpacity) })
            tryCompare(p.bubbleItem, "phase", "expanded", 4000)
            verify(d.shown, "in once grown")
            compare(d.arrowOpacity, 0, "no arrow")
            verify(!a.visible, "the arrow not drawn")
            verify(!d.arrowAnimation.running, "no arrow fade")
            tryVerify(function () { var ind = indicator(); return ind && ind.shown && ind.flickable === d.scroller }, 2000,
                      "the indicator on the full view's list")
            // past the morph's 150 ms hold and 300 ms fade: the arrow never showed
            wait(600)
            compare(most, 0, "the arrow never showed")
            verify(!a.visible)
        }

        /* ---- D60-08: the empty stream ------------------------------------ */

        function stream() {
            var s = make("NotificationStream.qml", { width: 384, height: 384, panelsGrid: gridMock })
            return s
        }

        // Nothing to show: CP3A's filled trophy_40px at 28 dp in onSurface over "You're all caught
        // up" in a 140 dp box with 7.3 % side padding (224 px for the text: two lines), the column
        // centred between 7.1 % and 16 % of the height, 6 dp between them (kvn.java, kwf.java:688-705)
        function test_d60_08_empty() {
            var s = stream()
            tryVerify(function () { return s.modelEmpty }, 3000)
            wait(100)
            var t = byName(s, "emptyTrophy")
            verify(t !== null, "the trophy")
            verify(t.visible)
            compare(t.width, 56)
            compare(t.height, 56)
            var sp = t.data[0]
            compare(String(sp.fillColor), String(Theme.color.onSurface))
            compare(sp.strokeWidth, -1)
            compare(sp.scale.width, 56 / 960)
            compare(sp.scale.height, 56 / 960)
            var path = sp.pathElements[0].path
            compare(path.indexOf("M282.67,433.33L282.67,272L186.67,272"), 0, "trophy_40px's path")
            verify(path.indexOf("L446.67,773.33Z") === path.length - "L446.67,773.33Z".length)
            var l = byName(s, "emptyLabel")
            verify(l !== null, "the label")
            compare(l.width, 280)
            compare(l.leftPadding, 28)
            compare(l.rightPadding, 28)
            compare(l.lineCount, 2, "two lines")
            var tp = t.mapToItem(s, 0, 0)
            var lp = l.mapToItem(s, 0, 0)
            compare(tp.x, 164)
            compare(lp.x, 52)
            fuzzyCompare(lp.y - (tp.y + 56), 12, 0.5)
            // the column centred in 27 .. 323
            fuzzyCompare((tp.y + lp.y + l.height) / 2, (27 + 384 - 61) / 2, 1)
            var img = shot(s, "d60-08-empty")
            // filled: the cup's middle is the glyph's colour (an outline is empty there)
            var mid = px(img, 192, Math.round(tp.y + 56 * 300 / 960))
            var on = Theme.color.onSurface
            compare(mid, [Math.round(on.r * 255), Math.round(on.g * 255), Math.round(on.b * 255)], "the cup is filled")
        }

        /* ---- D60-09: the stream's indicator; the full view's late list ---- */

        // A full view that comes in before its card's column is laid out (the next frame): the
        // indicator is asked again when the list's content height changes, and takes the list
        function test_d60_09_full_view_late_layout() {
            var n = notif({ replacesId: 91, summary: "Trains", body: longBody() })
            var d = make("notifications/HeadsUpDetail.qml", { width: 384, height: 384, notification: n })
            var ind0 = indicator()
            if (ind0)
                ind0.shown = false
            var first = d.entered()
            console.log("D60-09 entered at creation: list " + (d.scroller ? d.scroller.contentHeight : "none") + " flashed " + first)
            tryVerify(function () { var ind = indicator(); return ind && ind.shown && ind.flickable === d.scroller }, 2000,
                      "the indicator on the list once it is laid out")
            verify(d.scroller.contentHeight > d.scroller.height)
        }

        function fill(s, k) {
            var model = Lipstick.notificationModel
            for (var i = 0; i < k; i++)
                model.add(notif({ replacesId: 900 + i, summary: "Sender " + i, body: longBody() }))
            tryVerify(function () { return !s.modelEmpty && s.listView && s.listView.count === k }, 4000)
            wait(200)
        }

        // The stream fully open and at rest: the list's indicator shows for 2 s; not while the
        // tray still moves or a finger holds it, nor for an empty list
        function test_d60_09_stream() {
            var s = stream()
            fill(s, 4)
            var lv = s.listView
            verify(lv.contentHeight + lv.topMargin + lv.bottomMargin > lv.height, "a list that scrolls")
            var ind = indicator()
            if (ind)
                ind.shown = false
            // the tray on its way out
            gridMock.trayAnimation.running = true
            gridMock.currentVerticalPos = 1
            gridMock.normalizedVerOffset = 0.6
            wait(50)
            verify(!s.openAtRest)
            ind = indicator()
            verify(!ind || !ind.shown, "not while the tray moves")
            gridMock.normalizedVerOffset = 1
            wait(50)
            verify(!s.openAtRest, "still on the spring")
            gridMock.trayAnimation.running = false
            verify(s.openAtRest, "open and at rest")
            ind = indicator()
            verify(ind !== null && ind.shown, "the indicator shows")
            compare(ind.flickable, lv)
            tryVerify(function () { return !ind.shown }, 4000, "and hides 2 s later")
            // a finger on the tray: not at rest
            gridMock.trayDragging = true
            verify(!s.openAtRest)
            gridMock.trayDragging = false
            verify(ind.shown, "at rest again")
        }

        // the stream's LayerStack (its reply and menu pages go there)
        function layerStack(s) {
            var r = findAll(s, function (it) {
                return it.layers !== undefined && it.firstPageItem !== undefined && typeof it.push === "function"
            })
            return r.length ? r[0] : null
        }

        // A page open over the list (a reply or a menu): the tray coming to rest shows no
        // indicator and flashIndicator() refuses; once the page is gone the next rest shows it on
        // the list again
        function test_d60_09_stream_layer() {
            var s = stream()
            fill(s, 4)
            var lv = s.listView
            verify(lv.contentHeight + lv.topMargin + lv.bottomMargin > lv.height, "a list that scrolls")
            var st = layerStack(s)
            verify(st !== null, "the stream's LayerStack")
            var page = st.push(pageC, {})
            verify(page !== null, "a page pushed")
            compare(st.layers.length, 1)
            verify(s.handOverView === null, "the list is under a page")
            var ind = indicator()
            if (ind)
                ind.shown = false
            // the tray comes out and its spring stops
            gridMock.trayAnimation.running = true
            gridMock.currentVerticalPos = 1
            gridMock.normalizedVerOffset = 1
            wait(50)
            verify(!s.openAtRest, "still on the spring")
            gridMock.trayAnimation.running = false
            verify(s.openAtRest, "open and at rest")
            ind = indicator()
            verify(!ind || !ind.shown, "no indicator under the page")
            compare(s.flashIndicator(), false, "flashIndicator refuses under a page")
            wait(100)
            ind = indicator()
            verify(!ind || !ind.shown, "still none")
            // the page gone: the next rest shows the list's indicator
            st.pop(page)
            compare(st.layers.length, 0)
            gridMock.trayDragging = true
            verify(!s.openAtRest)
            gridMock.trayDragging = false
            verify(s.openAtRest, "at rest again")
            ind = indicator()
            verify(ind !== null && ind.shown, "the indicator once the page is gone")
            compare(ind.flickable, lv)
        }

        function test_d60_09_stream_empty() {
            var s = stream()
            tryVerify(function () { return s.modelEmpty }, 3000)
            var ind = indicator()
            if (ind)
                ind.shown = false
            gridMock.currentVerticalPos = 1
            gridMock.normalizedVerOffset = 1
            verify(s.openAtRest)
            ind = indicator()
            verify(!ind || !ind.shown, "an empty stream shows no indicator")
        }
    }
}
