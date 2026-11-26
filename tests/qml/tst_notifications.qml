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
//    nor faded by it (the face never shows through); the crown's close takes it with the view as
//    CP3A's root (juh.java:647): alpha and scale 1 -> 0 in 300 ms from the root's own 1, also in
//    the middle of the morph, which goes on under it and brings nothing in at its end;
//  - D60-07: when the morph ends (CP3A's onFullViewShown) the full view shows CP3A's header arrow
//    (shy_view_header_arrow: the Lottie held at progress 0.75, turned 180 degrees in a 24 dp view
//    8 dp below the top) and fades it 150 ms later over 300 ms, and (D60-09) the scroll indicator
//    shows on its list for 2 s (RotaryInput.flashIndicator); grown from the bubble, the indicator
//    only (CP3A's heads-up view, ktk.java:139-158, runs no klg);
//  - D60-08: the empty stream's filled trophy (trophy_40px at 28 dp) and its 140 dp text box with
//    7.3 % side padding (kvn.java);
//  - D60-09: the stream's scroll indicator shows for 2 s once the tray is fully open and at rest,
//    not while a page (a reply or a menu) is open over the list;
//  - N61-20: a stream card swipes both ways in the Wear OS 6 emulator's look (S34, S34-b, M10): the
//    #343B4D pill on the side the card leaves, |offset| - 4 px wide; a cleared card's pill stays
//    100 ms under its neighbours and fades in 100 ms while the cards under it move up over 282 ms
//    on LinearOutSlowIn;
//  - N61-21: the heads-up's full view flat on black as the emulator's S10-d (no card surface, a
//    45 px header disc at (44, 84), the text ink from x 37), and the emulator's morph (M09): the
//    glanceable out in 80 ms, the view in over 85 ms growing 0.88 -> 1 on FastOutSlowIn in 540 ms;
//  - N61-22: the glanceable as the emulator's S09: the small icon bare and white, its ink from
//    (38, 84); the notification's title start-aligned, its ink from x 39 and its capitals' top at
//    y 158; the app name along the edge in bold with no tracking;
//  - N61-23: a stream card opened in place scrolls its drawn top to y 45 (0.117 h, S08), its
//    surface #24262B on the open progress (also when it is no taller open), the header and the
//    text 9 dp in (the body's ink from x 38 as the emulator's).
// Shots go to /tmp/wo02-shots. Run by motion-wt/wo02/run.sh (qmltestrunner under qemu-aarch64 on
// the image rootfs; the controls cross-built from qml-asteroid).
import QtQuick
import QtQuick.Shapes
import QtTest
import org.asteroid.controls
import org.nemomobile.lipstick
import "st/qml/notifications/headsup.js" as HU

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

    // a notification the stream clears: removeRequested() takes it out of the model (N61-20)
    Component {
        id: notifRemovableC
        QtObject {
            id: rn
            property string appName: "Shell"
            property int replacesId: 1
            property string appIcon: ""
            property string icon: ""
            property string summary: ""
            property string body: ""
            property var hints: ({})
            property var actions: []
            property var timestamp: new Date()
            property bool userRemovable: true
            property string category: ""
            property int removals: 0
            function removeRequested() {
                removals++
                Lipstick.notificationModel.remove(rn)
            }
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

        // A title that wraps in the collapsed card's 304 px but fits the open card's 308 px (the
        // open text sits 9 dp from the edge since N61-23, the collapsed 10 dp): the open card is one
        // title line lower than the collapsed one, and is as tall as that, not held to the collapsed
        // height
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
            // between the two text widths: over 304 px, under 308 (a narrow window: several fills)
            var title = ""
            var fills = ["sliiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii", "sllllllllllllllllllllllllllllll",
                         "tiiiiiiiiiiiiiiiiiiiiiiiiiiiiii", "fttttttttttttttttttttttttttttt",
                         "rjjjjjjjjjjjjjjjjjjjjjjjjjjjjj", "a.....................", "e::::::::::::::::::::::",
                         "c,,,,,,,,,,,,,,,,,,,,,,", "oiiiiiiiiiiiiiiiiiiiiiiiiiiiii", "nlllllllllllllllllllllllllll"]
            for (var f = 0; f < fills.length && title === ""; f++) {
                for (var j = 1; j < 40 && title === ""; j++) {
                    tm.text = base + " " + fills[f].substring(0, j)
                    if (tm.advanceWidth > 304.5 && tm.advanceWidth < 307.5)
                        title = tm.text
                }
            }
            verify(title !== "", "a title between 304.5 and 307.5 px")
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
            // the morph's first frames of the full view: 0.88 (N61-21), the glanceable gone
            p.glanceOpacity = 0
            p.detailScale = HU.MORPH.detailScaleFrom
            wait(100)
            var img = shot(top, "d60-06-morph")
            // between the scaled view's disc (radius 169 px) and the screen's edge: black, not the face
            compare(px(img, 192, 12), [0, 0, 0], "top ring")
            compare(px(img, 12, 192), [0, 0, 0], "left ring")
            compare(px(img, 372, 192), [0, 0, 0], "right ring")
            compare(px(img, 192, 372), [0, 0, 0], "bottom ring")
            p.detailScale = 1
        }

        // The crown's close takes the scrim with the view: CP3A animates the whole root, this.q
        // .animate() alpha and scale 1 -> 0 in 300 ms on the ViewPropertyAnimator's
        // AccelerateDecelerate (juh.java:647); at its end the root is 1 again and the view gone (jug)
        function test_d60_06_crown_close() {
            var p = preview()
            var n = notif({ replacesId: 62, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            var a = p.closeAnimation.animations
            compare(a.length, 2)
            compare(a[0].property, "rootOpacity"); compare(a[0].to, 0)
            compare(a[1].property, "rootScale"); compare(a[1].to, 0)
            for (var k = 0; k < 2; k++) {
                compare(a[k].duration, 300, "300 ms")
                compare(a[k].easing.type, Easing.InOutSine, "AccelerateDecelerate")
            }
            p.toFull()
            tryVerify(function () { return p.mode === "full" && p.detailScale === 1 }, 3000)
            var s = scrimOf(p)
            var calls = notificationPreviewPresenter.nextCalls
            var t0 = Date.now()
            p.closeFromCrown()
            verify(p.closeAnimation.running)
            compare(p.rootOpacity, 1); compare(p.rootScale, 1)
            tryVerify(function () { return p.rootOpacity < 0.9 && p.rootOpacity > 0.1 }, 3000, "mid-close")
            fuzzyCompare(s.opacity, p.rootOpacity, 0.0001)
            fuzzyCompare(s.scale, p.rootScale, 0.0001)
            // the view's own numbers stay where the morph left them; the root's go
            compare(p.detailOpacity, 1)
            compare(p.detailScale, 1)
            fuzzyCompare(p.detailHost.opacity, p.rootOpacity, 0.0001)
            fuzzyCompare(p.detailHost.scale, p.rootScale, 0.0001)
            tryCompare(p, "mode", "none", 3000)
            verify(Date.now() - t0 >= 290, "over 300 ms: " + (Date.now() - t0))
            verify(!s.visible)
            compare(p.rootOpacity, 1, "the root 1 again (jug)")
            compare(p.rootScale, 1)
            compare(notificationPreviewPresenter.nextCalls, calls + 1, "finished: the next alert asked for")
        }

        // What the crown's close draws at each step while it runs: the root's and the scrim's
        // numbers, the view's and the glanceable's own and what they are drawn at
        function closeSamples(p, s) {
            var out = []
            var take = function () {
                if (!p.closeAnimation.running)
                    return
                out.push({ root: p.rootOpacity, rootScale: p.rootScale, so: s.opacity, ss: s.scale,
                           ds: p.detailScale, dop: p.detailOpacity, host: p.detailHost.opacity,
                           hostScale: p.detailHost.scale, go: p.glanceOpacity, glance: p.glanceItem.opacity })
            }
            // the close sets the root alpha, then its scale: a frame is complete at the scale
            p.rootScaleChanged.connect(take)
            p.detailOpacityChanged.connect(take)
            p.detailScaleChanged.connect(take)
            p.glanceOpacityChanged.connect(take)
            return out
        }
        function checkSamples(out) {
            verify(out.length >= 3, "frames of the close: " + out.length)
            var last = 2
            for (var i = 0; i < out.length; i++) {
                var o = out[i]
                // the scrim is the root's, never the view's numbers
                fuzzyCompare(o.so, o.root, 1e-9)
                fuzzyCompare(o.ss, o.rootScale, 1e-9)
                fuzzyCompare(o.rootScale, o.root, 1e-9)
                verify(o.root <= last + 1e-9, "the root only goes down")
                last = o.root
                // the view and the glanceable under the root: never more than it
                fuzzyCompare(o.host, o.dop * o.root, 1e-9)
                fuzzyCompare(o.hostScale, o.ds * o.root, 1e-9)
                fuzzyCompare(o.glance, o.go * o.root, 1e-9)
                verify(o.host <= o.root + 1e-9, "the view no more than the root: " + o.host + " > " + o.root)
            }
            fuzzyCompare(out[out.length - 1].root, 0, 1e-9, "the root ends at 0")
        }

        // The crown in the middle of the morph (the view at about 0.9): CP3A's close is the root's,
        // from its own 1, and cancels nothing (juh.java:647 r()). The scrim stays at 1 and unscaled
        // on the first frame (no face ring; before, it took the view's 0.9 at once), then goes 1 -> 0
        // with the root over 300 ms while the view's own scale goes on growing under it
        function test_d60_06_crown_close_mid_morph() {
            var p = preview()
            var n = notif({ replacesId: 64, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            p.toFull()
            tryVerify(function () { return p.mode === "full" && p.detailScale >= 0.88 }, 3000, "in the morph")
            var at = p.detailScale
            verify(at < 0.97, "the middle of the morph: " + at)
            var s = scrimOf(p)
            var out = closeSamples(p, s)
            var t0 = Date.now()
            p.closeFromCrown()
            // the close's first frame: the root and the scrim at 1, not the view's numbers
            compare(p.rootOpacity, 1)
            compare(p.rootScale, 1)
            compare(s.opacity, 1)
            compare(s.scale, 1)
            verify(s.visible)
            var img = shot(top, "d60-06-crown-mid-morph")
            // outside the view's disc (radius 192 x 0.88-0.97, at most 186 px): black, not the face
            compare(px(img, 192, 4), [0, 0, 0], "top ring")
            compare(px(img, 4, 192), [0, 0, 0], "left ring")
            compare(px(img, 379, 192), [0, 0, 0], "right ring")
            compare(px(img, 192, 379), [0, 0, 0], "bottom ring")
            compare(px(img, 3, 3), [0, 0, 0], "corner")
            tryCompare(p, "mode", "none", 3000)
            verify(Date.now() - t0 >= 290, "over 300 ms: " + (Date.now() - t0))
            checkSamples(out)
            var most = at
            for (var i = 0; i < out.length; i++)
                most = Math.max(most, out[i].ds)
            verify(most > at, "the morph went on under the close: " + at + " -> " + most)
            compare(p.rootOpacity, 1)
            compare(p.rootScale, 1)
        }

        // The crown while the glanceable still fades (the morph's first 100 ms): the root closes,
        // the morph goes on under it (the full view comes in at most at the root's alpha, never
        // over a faded scrim) and the close's end ends both
        function test_d60_06_crown_close_glance_part() {
            var p = preview()
            var n = notif({ replacesId: 65, summary: "Sam", body: "On my way" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            p.toFull()
            compare(p.mode, "glance", "the glanceable's part of the morph")
            var s = scrimOf(p)
            var out = closeSamples(p, s)
            p.closeFromCrown()
            compare(s.opacity, 1)
            compare(s.scale, 1)
            tryCompare(p, "mode", "none", 3000)
            checkSamples(out)
            compare(p.rootOpacity, 1)
            compare(p.glanceOpacity, 1)
        }

        // The morph ends under the close (the crown late in it): the view is leaving and nothing
        // comes in: no header arrow, no scroll indicator over the face (eos's is the window's)
        function test_d60_06_crown_close_morph_ends() {
            var p = preview()
            var n = notif({ replacesId: 66, summary: "Trains", body: longBody() })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            // the crown at the first frame the view's scale is 0.985 or more: on N61-21's FastOutSlowIn
            // about 230 ms of the 540 are left, less than the close's 300 (at 0.95 it was 365: a poll
            // for it could press too early to see the morph end)
            var d = null, most = 0, ends = 0, pressed = false, at = 0
            p.detailScaleChanged.connect(function () {
                if (!pressed && p.mode === "full" && p.detailScale >= 0.985 && p.detailScale < 1) {
                    pressed = true
                    at = p.detailScale
                    d = p.detailItem
                    d.arrowOpacityChanged.connect(function () { most = Math.max(most, d.arrowOpacity) })
                    p.closeFromCrown()
                }
                if (pressed && p.detailScale === 1 && p.closeAnimation.running)
                    ends++
            })
            p.toFull()
            tryVerify(function () { return pressed }, 3000, "late in the morph")
            verify(d !== null)
            tryCompare(p, "mode", "none", 3000)
            compare(ends, 1, "the morph ended under the close (the crown at " + at + ")")
            compare(most, 0, "no header arrow")
            var ind = indicator()
            verify(!ind || !ind.shown, "no scroll indicator")
            wait(200)
            verify(!ind || !ind.shown, "no scroll indicator later")
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

        /* ---- N61-20: the stream card's swipe both ways ------------------- */

        function removable(props) {
            var n = notifRemovableC.createObject(top, props || {})
            made.push(n)
            return n
        }
        // the emulator's three test notifications, newest first (S07; invented text)
        function fillThree(s) {
            var model = Lipstick.notificationModel
            model.add(removable({ replacesId: 2001, summary: "Retest one", body: "First test notification body" }))
            model.add(removable({ replacesId: 2002, summary: "Retest two",
                                  body: "Second body, long enough to wrap to two lines on the card" }))
            model.add(removable({ replacesId: 2003, summary: "Retest three", body: "Third" }))
            tryVerify(function () { return !s.modelEmpty && s.listView && s.listView.count === 3 }, 4000)
            wait(300)
        }
        function swipeOf(row) {
            var r = findAll(row, function (it) { return it._isSwipeToReveal === true })
            return r.length ? r[0] : null
        }
        // a finger pressed at x0 and moved to x1 (px of the screen) at height y in 12 steps 16 ms apart
        // (about 200 ms: the emulator's M10 swipe), still down
        function dragTo(x0, x1, y) {
            mousePress(top, x0, y)
            for (var i = 1; i <= 12; i++) {
                mouseMove(top, x0 + (x1 - x0) * i / 12, y)
                wait(16)
            }
        }
        function near(c, rgb, tol) {
            return Math.abs(c[0] - rgb[0]) <= tol && Math.abs(c[1] - rgb[1]) <= tol && Math.abs(c[2] - rgb[2]) <= tol
        }

        // The card follows the finger both ways (S34: held about 160 px to the right, S34-b: to the
        // left), from 29 dp (58 px) after the press, then 1:1 (qml-asteroid SwipeToReveal dragLag, N61-09).
        // The pill is on the side the card leaves, its outer edge on the card's rest edge,
        // |offset| - 4 px wide (2 dp from the card), #343B4D, the X centred, no label yet. Let go after
        // the finger stopped (no speed: stock's release rule takes the nearest anchor), the card
        // stays at the partial reveal (64 dp x 344 / 384 = 114.7 px), not cleared
        function test_n61_20_swipe_both_ways() {
            var s = stream()
            fillThree(s)
            var row = s.rowItems[2003]
            verify(row !== undefined, "the first card's row")
            var sw = swipeOf(row)
            verify(sw !== null, "its SwipeToReveal")
            verify(sw.bidirectional, "both ways")
            verify(sw.expressiveLook, "the emulator's pill")
            var r0 = row.mapToItem(top, 0, 0)
            compare(Math.round(r0.x), 20, "the card from x 20")
            compare(Math.round(sw.width), 344)
            var y = r0.y + row.height / 2
            // the lag: a finger 40 px out has not moved the card yet
            compare(sw.dragLag, 58)
            dragTo(200, 240, y)
            compare(sw.offset, 0, "within the lag the card stays")
            mouseRelease(top, 240, y)
            wait(100)
            sw.reset()
            wait(50)
            var acts = 0
            sw.primaryAction.connect(function () { acts++ })
            // the card 160 px out: the finger 160 + 58 px
            var cases = [{ x0: 150, x1: 368, off: 160, name: "right" }, { x0: 300, x1: 82, off: -160, name: "left" }]
            for (var i = 0; i < cases.length; i++) {
                var c = cases[i]
                dragTo(c.x0, c.x1, y)
                fuzzyCompare(sw.offset, c.off, 1, c.name + ": the card follows the finger")
                compare(sw.side, c.off > 0 ? 1 : -1)
                var pill = byName(sw, "swipeRevealPill")
                verify(pill !== null && pill.visible, "the pill")
                fuzzyCompare(pill.width, Math.abs(sw.offset) - 4, 0.5, "|offset| - 4")
                fuzzyCompare(pill.height, sw.height - 4, 0.5, "the card's height less 4 px")
                var p = pill.mapToItem(top, 0, 0)
                if (c.off > 0)
                    fuzzyCompare(p.x, 20, 0.5, "at the card's left rest edge")
                else
                    fuzzyCompare(p.x + pill.width, 364, 0.5, "at the card's right rest edge")
                compare(String(pill.children[0].color), "#343b4d")
                var img = shot(top, "n61-20-hold-" + c.name)
                var py = Math.round(p.y + pill.height / 2)
                verify(near(px(img, Math.round(p.x + 12), py), [0x34, 0x3b, 0x4d], 3),
                       "#343B4D at the pill's end: " + px(img, Math.round(p.x + 12), py))
                // the X glyph in the middle, light on the pill
                var icon = byName(sw, "swipeRevealIcon")
                compare(icon.opacity, 1)
                var ic = icon.mapToItem(top, icon.width / 2, icon.height / 2)
                fuzzyCompare(ic.x, p.x + pill.width / 2, 1, "the X centred")
                compare(byName(sw, "swipeRevealLabel").visible, false, "no 'Clear' at 160 px")
                // held still, then let go: no speed, the nearest anchor (the partial reveal)
                wait(120)
                mouseRelease(top, c.x1, y)
                var partial = (c.off > 0 ? 1 : -1) * sw.revealingOffset
                fuzzyCompare(sw.revealingOffset, 114.67, 0.1, "64 dp of the 192 dp screen, for the 344 px card")
                tryVerify(function () { return Math.abs(sw.offset - partial) < 1 }, 3000,
                          c.name + ": at the partial reveal: " + sw.offset)
                compare(sw.state_, "revealing")
                compare(acts, 0, "not cleared")
                sw.reset()
                wait(50)
            }
        }

        // A full swipe clears the card once: the emulator's M10 fling (80 -> 340 px in 200 ms, about
        // 650 dp/s), let go while the finger moves, goes to the next anchor in its direction (stock's
        // release rule, 200-800 dp/s: the full reveal from about 200 px out). Its row, the pill at the
        // full width, stays drawn under its neighbours for 100 ms, then fades in 100 ms; the next card
        // moves up to the list's top (84 px) over 282 ms on LinearOutSlowIn (M10); both ways.
        // The rule is checked on SwipeToReveal.anchorFor with M10's numbers. The gesture goes past the
        // middle of the partial and the full reveal (255 px out), so it clears whether the release counts
        // as a fling or as a stopped finger: the control reads the wall clock (a finger still for 40 ms
        // is no fling), which a loaded host stretches; M10's 200 px release could then stop at the
        // partial reveal
        function test_n61_20_full_swipe() {
            var s = stream()
            fillThree(s)
            var lv = s.listView
            compare(s.removeHoldMs, 100)
            compare(s.removeFadeMs, 100)
            compare(s.displacedMs, 282)
            compare(s.displacedEasing, [0, 0, 0.2, 1, 1, 1])
            // M10: about 200 px out at 650 dp/s: the full reveal; the same place held still: the partial one
            var sw0 = swipeOf(s.rowItems[2003])
            compare(sw0.anchorFor(202, 1300), sw0.width, "M10's fling to the right: the full reveal")
            compare(sw0.anchorFor(-202, -1300), -sw0.width, "and to the left")
            compare(sw0.anchorFor(202, 0), sw0.revealingOffset, "held still there: the partial reveal")
            var dirs = [{ id: 2003, next: 2002, x0: 70, x1: 383 }, { id: 2002, next: 2001, x0: 314, x1: 1 }]
            for (var k = 0; k < dirs.length; k++) {
                var d = dirs[k]
                var row = s.rowItems[d.id]
                var sw = swipeOf(row)
                var n = row.notification
                var acts = 0
                sw.primaryAction.connect(function () { acts++ })
                var next = s.rowItems[d.next]
                var y = row.mapToItem(top, 0, 0).y + row.height / 2
                var h = row.height
                var wrapper = row.parent.parent
                // when the notification went, and when the row's fade began
                var t0 = 0, tFade = 0
                n.removalsChanged.connect(function () { if (!t0) t0 = Date.now() })
                wrapper.opacityChanged.connect(function () { if (!tFade && wrapper.opacity < 1) tFade = Date.now() })
                dragTo(d.x0, d.x1, y)
                // let go at once: the card 255 px out (past the middle of the two reveals), short of the full one
                verify(Math.abs(sw.offset) < sw.width * 0.75, "short of the full reveal at the release: " + sw.offset)
                verify(Math.abs(sw.offset) > (sw.revealingOffset + sw.width) / 2, "past the middle: " + sw.offset)
                mouseRelease(top, d.x1, y)
                tryVerify(function () { return acts > 0 }, 3000, "the card cleared")
                compare(n.removals, 1, "dismissed once")
                tryVerify(function () { return wrapper.z === -1 }, 1000, "the row under its neighbours")
                verify(row.visible, "the pill still drawn")
                fuzzyCompare(row.height, h, 0.5, "at its height")
                var pill = byName(sw, "swipeRevealPill")
                fuzzyCompare(pill.width, 340, 0.5, "the pill at the full width")
                var o = wrapper.opacity
                var img = shot(top, "n61-20-cleared-" + k)
                tryVerify(function () { return tFade > 0 }, 1000, "then it fades")
                var held = tFade - t0
                verify(held >= 90, "held about 100 ms: " + held + " (opacity " + o + " at the start)")
                tryVerify(function () { return Math.abs(next.mapToItem(lv, 0, 0).y - 84) < 1 && lv.count === 2 - k }, 3000,
                          "the next card at the top")
                var moved = Date.now() - t0
                verify(moved >= 250, "moved up over about 282 ms: " + moved)
                console.log("N61-20 full swipe " + k + ": held " + held + " ms, next card at the top after " + moved + " ms")
                wait(400)
                compare(acts, 1, "primaryAction once")
            }
        }

        /* ---- N61-21: the flat full view and the emulator's morph ----------- */

        function fullText(card) {
            return findAll(fullLoader(card), function (it) { return it.compact === false && it.headerInset !== undefined })[0]
        }
        // the first column from x0 to x1 with a pixel brighter than mid grey between rows y0 and y1
        function inScreen(x, y) {
            return (x - 192) * (x - 192) + (y - 192) * (y - 192) < 186 * 186
        }
        function inkLeft(img, x0, x1, y0, y1) {
            for (var x = x0; x < x1; x++)
                for (var y = y0; y < y1; y++) {
                    var c = px(img, x, y)
                    if (c[0] + c[1] + c[2] > 300 && inScreen(x, y))
                        return x
                }
            return -1
        }
        function labelWith(root, text) {
            var r = findAll(root, function (it) { return it.text === text && it.font !== undefined && it.visible })
            return r.length ? r[0] : null
        }

        // S10-d settled: no card surface, the header disc 45 px at x 44-88, y 84-128, the app
        // name after it, the title and body from x 37; the card's text sizes
        function test_n61_21_flat_detail() {
            var n = notif({ replacesId: 2101, appName: "Shell", summary: "Retest one", body: "First test notification body" })
            var d = make("notifications/HeadsUpDetail.qml", { width: 384, height: 384, notification: n })
            tryVerify(function () { return d.card !== null && fullLoader(d.card).item !== null }, 3000, "the open card")
            wait(200)
            var c = d.card
            verify(c.flat, "flat")
            var bg = byName(c, "cardSurface")
            compare(bg.color.a, 0, "no surface")
            var rip = findAll(bg, function (it) { return it.pressX !== undefined && it.pressed !== undefined })
            verify(rip.length === 1 && !rip[0].visible, "no ripple")
            fuzzyCompare(c.y, 64, 0.5, "the card at the top padding less its 10 dp")
            var ft = fullText(c)
            verify(ft !== undefined, "the full text")
            var disc = byName(ft, "headerIcon")
            var dp = disc.mapToItem(d, 0, 0)
            fuzzyCompare(dp.x, 44, 1)
            fuzzyCompare(dp.y, 84, 1)
            fuzzyCompare(disc.width, 45, 0.5)
            fuzzyCompare(disc.height, 45, 0.5)
            var app = labelWith(ft, "Shell")
            fuzzyCompare(app.mapToItem(d, 0, 0).x, 101, 1, "the app name 6 dp after the disc")
            var title = labelWith(ft, "Retest one")
            var body = labelWith(ft, "First test notification body")
            // the labels 7 dp in: their ink from x 37 (checked on the render below)
            fuzzyCompare(title.mapToItem(d, 0, 0).x, 34, 1, "the title 7 dp in")
            fuzzyCompare(body.mapToItem(d, 0, 0).x, 34, 1, "the body 7 dp in")
            compare(title.font.pixelSize, 32, "the card's title size")
            compare(String(title.color), "#d4c7ff")
            compare(String(body.color), "#cecdd4")
            var img = shot(top, "n61-21-flat")
            // around the text: black, none of the card colours (#2F3036, #24262B)
            var pts = [[30, 150], [350, 150], [30, 220], [352, 200], [192, 76], [60, 136]]
            for (var i = 0; i < pts.length; i++)
                compare(px(img, pts[i][0], pts[i][1]), [0, 0, 0], "black at " + pts[i])
            // the disc is drawn there (accent primary)
            var on = px(img, 46, 106)
            verify(on[0] > 150 && on[2] > 150, "the disc's colour at its left: " + on)
            // the title's and the body's ink start at x 37 +- 1 (S10-d: 37 and 36)
            var ty = Math.round(title.mapToItem(d, 0, 0).y)
            var tl = inkLeft(img, 30, 300, ty, ty + Math.round(title.height))
            verify(tl >= 36 && tl <= 38, "the title's ink from x 37: " + tl)
            var by = Math.round(body.mapToItem(d, 0, 0).y)
            var bl = inkLeft(img, 30, 300, by, by + 36)
            verify(bl >= 35 && bl <= 38, "the body's ink from x 36-37: " + bl)
        }

        // The morph's numbers (M09) and the first frame of the full view at 0.88
        function test_n61_21_morph() {
            compare(HU.MORPH.glanceFadeMs, 80)
            compare(HU.MORPH.glanceScaleTo, 1.15)
            compare(HU.MORPH.detailFadeMs, 85)
            compare(HU.MORPH.detailScaleFrom, 0.88)
            compare(HU.MORPH.detailScaleMs, 540)
            compare(HU.MORPH.detailScaleEasing, [0.4, 0, 0.2, 1, 1, 1])
            var p = preview()
            var n = notif({ replacesId: 2102, appName: "Shell", summary: "Retest one", body: "First test notification body" })
            notificationPreviewPresenter.kind = 1
            notificationPreviewPresenter.notification = n
            tryCompare(p, "mode", "glance", 3000)
            var first = -1, t0 = 0, tIn = 0, tEnd = 0, mid = []
            p.modeChanged.connect(function () {
                if (p.mode === "full" && first < 0) {
                    first = p.detailScale
                    tIn = Date.now()
                }
            })
            p.detailScaleChanged.connect(function () {
                if (tIn > 0 && p.detailScale < 1)
                    mid.push([Date.now() - tIn, p.detailScale])
                if (tIn > 0 && p.detailScale === 1 && tEnd === 0)
                    tEnd = Date.now()
            })
            t0 = Date.now()
            p.toFull()
            tryVerify(function () { return tEnd > 0 && p.detailOpacity === 1 }, 4000, "the morph over")
            fuzzyCompare(first, 0.88, 0.001, "the full view's first frame at 0.88")
            var glanceMs = tIn - t0
            var scaleMs = tEnd - tIn
            console.log("N61-21 morph: glanceable out " + glanceMs + " ms, view scale " + scaleMs + " ms, samples " + JSON.stringify(mid.slice(0, 6)))
            verify(glanceMs >= 70, "the glanceable out in about 80 ms: " + glanceMs)
            verify(scaleMs >= 500, "the view grows over about 540 ms: " + scaleMs)
            // FastOutSlowIn, not CP3A's InOutSine: from 30 % to 55 % of the time the view is well
            // ahead of the sine (at half the time 77 % of the way, the sine 50 %)
            var early = mid.filter(function (m) { return m[0] > 0.3 * 540 && m[0] < 0.55 * 540 })
            verify(early.length > 0, "samples in the middle of the morph")
            for (var i = 0; i < early.length; i++) {
                var sine = (1 - Math.cos(Math.PI * early[i][0] / 540)) / 2
                verify((early[i][1] - 0.88) / 0.12 > sine + 0.08, "fast out: " + early[i] + " (sine " + sine + ")")
            }
        }

        /* ---- N61-22: the glanceable ---------------------------------------- */

        // the first row from y0 to y1 with a pixel brighter than mid grey between columns x0 and x1
        function inkTop(img, x0, x1, y0, y1) {
            for (var y = y0; y < y1; y++)
                for (var x = x0; x < x1; x++) {
                    var c = px(img, x, y)
                    if (c[0] + c[1] + c[2] > 300 && inScreen(x, y))
                        return y
                }
            return -1
        }

        // What it says: the notification's title (S09: contentTitle 'Retest one', not the text),
        // the text when there is no title, a chat's newest message
        function test_n61_22_title_of() {
            compare(HU.titleOf(notif({ summary: "Retest one", body: "First test notification body" })), "Retest one")
            compare(HU.titleOf(notif({ summary: "", body: "Battery low" })), "Battery low")
            var msgs = JSON.stringify([{ s: "Sam", t: "older" }, { s: "Sam", t: "newest one" }])
            compare(HU.titleOf(notif({ summary: "Sam", body: "x", hints: { "x-asteroid-messages": msgs } })), "newest one")
        }

        // S09 at 0.5 s / hsheet at 0.7 s: on black, the small icon bare and white, a 60 px box with
        // its glyph's ink from (38, 84), the title start-aligned with its ink from x 39 and its
        // capitals' top at y 158 (S09 measured the same way), one 24 sp line, no body; the app name
        // along the bottom edge in bold with no tracking
        function test_n61_22_glanceable() {
            compare(HU.GLANCE.iconTopFraction, 0.219)
            compare(HU.GLANCE.iconInkStartFraction, 0.099)
            compare(HU.GLANCE.iconInkInset, 5)
            compare(HU.GLANCE.sidePaddingFraction, 0.092)
            var n = notif({ replacesId: 2201, appName: "Shell", summary: "Retest one", body: "First test notification body" })
            var g = make("notifications/Glanceable.qml", { width: 384, height: 384, notification: n })
            g.stop()
            wait(100)
            compare(g.titleItem.text, "Retest one")
            compare(g.titleItem.horizontalAlignment, Text.AlignLeft)
            compare(g.titleItem.effectiveHorizontalAlignment, Text.AlignLeft)
            compare(g.titleItem.x, 35)
            compare(g.titleItem.lineCount, 1)
            compare(g.sidePadding, 35)
            compare(g.iconTop, 79)
            compare(g.iconItem.x, 33)
            compare(g.iconItem.y, 79)
            compare(g.iconItem.width, 60)
            compare(g.iconItem.height, 60)
            var discs = findAll(g.iconItem, function (it) { return it.radius !== undefined && it.color !== undefined })
            compare(discs.length, 0, "no container")
            var glyph = findAll(g.iconItem, function (it) { return it.name !== undefined && it.visible })
            compare(glyph.length, 1, "a glyph")
            compare(String(glyph[0].color), "#ffffff", "white")
            compare(g.nameItem.text, "Shell")
            compare(g.nameItem.role, "arcMedium")
            compare(g.nameItem.pixelSize, 30)
            compare(g.nameItem.edgeMargin, 8)
            var letters = findAll(g.nameItem, function (it) { return it.along !== undefined && it.visible })
            compare(letters.length, 5)
            compare(letters[0].font.weight, Font.Bold)
            compare(letters[0].font.letterSpacing, 0)
            var shellLen = g.nameItem.naturalLength
            n.appName = "Retest"
            wait(50)
            var retestLen = g.nameItem.naturalLength
            console.log("N61-22 name: 'Shell' " + shellLen + " px (emulator 76), 'Retest' " + retestLen + " px (eos 99 before)")
            verify(retestLen < 90, "'Retest' narrower than 90 px: " + retestLen)
            n.appName = "Shell"
            wait(50)
            var img = shot(g, "n61-22-glance")
            var it = inkTop(img, 30, 120, 70, 140)
            var il = inkLeft(img, 30, 120, 70, 140)
            var ct = inkTop(img, 30, 330, 140, 200)
            var cl = inkLeft(img, 30, 330, 140, 200)
            console.log("N61-22 render: icon ink from (" + il + ", " + it + "), title ink from x " + cl + ", cap top " + ct)
            verify(Math.abs(ct - 158) <= 1, "the title's capitals' top at y 158: " + ct)
            verify(Math.abs(cl - 39) <= 1, "the title's ink from x 39: " + cl)
            // the mail glyph (ios-mail-outline): Material's 'mail', 80-880 x 160-800 of 960
            verify(Math.abs(il - 38) <= 1, "the icon's ink from x 38: " + il)
            verify(Math.abs(it - 89) <= 1, "the mail glyph's ink from y 89 (a full-height glyph's 84): " + it)
            // no disc colour: black around the glyph inside its box
            compare(px(img, 36, 82), [0, 0, 0])
            compare(px(img, 64, 86), [0, 0, 0])
            compare(px(img, 90, 136), [0, 0, 0])
            // nothing under the one title line (no body)
            compare(inkTop(img, 30, 354, 205, 330), -1, "no text under the title")
        }

        // An icon given as a picture file is drawn as it is (no white glyph)
        function test_n61_22_file_icon() {
            var n = notif({ replacesId: 2202, appName: "Shell", summary: "Retest one", icon: "/usr/share/icons/hicolor/x.png" })
            var g = make("notifications/Glanceable.qml", { width: 384, height: 384, notification: n })
            g.stop()
            verify(g.iconIsFile)
            var img = findAll(g.iconItem, function (it) { return it.fillMode !== undefined && it.visible })
            compare(img.length, 1)
            compare(String(img[0].source), "file:///usr/share/icons/hicolor/x.png")
            compare(findAll(g.iconItem, function (it) { return it.name !== undefined && it.visible }).length, 0)
        }

        /* ---- N61-23: the opened stream card ---------------------------------- */

        function cardOf(row) {
            return findAll(row, function (it) { return it.expandProgress !== undefined })[0]
        }

        // S08: the second of three cards tapped opens in place and the list scrolls its top to y 45
        // (0.117 of the height; its drawn top: the row is inside the list's packed wrapper), the card
        // above edge-scaled over the gap; the surface #24262B; the header disc at (38, 65); the
        // title and the body 9 dp in (the body's ink from x 38)
        function test_n61_23_open_top() {
            var s = stream()
            fillThree(s)
            compare(s.openTop, 45)
            var lv = s.listView
            var row = s.rowItems[2002]
            var c = cardOf(row)
            verify(c !== undefined, "the second card")
            compare(String(byName(c, "cardSurface").color), "#2f3036", "closed: surfaceContainer")
            s.toggleCard(2002)
            tryVerify(function () { return isNaN(s.scrollWritten) && c.openP > 0.999 && !c.animating }, 8000,
                      "opened and scrolled")
            wait(200)
            var t = row.mapToItem(s, 0, 0).y
            console.log("N61-23 open: drawn top " + t + ", contentY " + lv.contentY)
            fuzzyCompare(t, 45, 1, "the open card's drawn top at y 45")
            compare(String(byName(c, "cardSurface").color), "#24262b", "open: surfaceContainerLow")
            var ft = fullText(c)
            var disc = byName(ft, "headerIcon")
            var dp = disc.mapToItem(s, 0, 0)
            fuzzyCompare(dp.x, 38, 1, "the disc 9 dp in")
            fuzzyCompare(dp.y, 65, 1, "the disc 20 px under the top")
            compare(disc.width, 48)
            var title = labelWith(ft, "Retest two")
            var body = labelWith(ft, "Second body, long enough to wrap to two lines on the card")
            fuzzyCompare(title.mapToItem(s, 0, 0).x, 38, 1, "the title 9 dp in")
            fuzzyCompare(body.mapToItem(s, 0, 0).x, 38, 1, "the body 9 dp in")
            // the card above is drawn above it, edge-scaled
            var above = s.rowItems[2003]
            var ab = above.mapToItem(s, 0, above.height)
            verify(ab.y <= 45, "the card above ends over the gap: " + ab.y)
            var img = shot(s, "n61-23-open")
            var ty = Math.round(title.mapToItem(s, 0, 0).y)
            var tl = inkLeft(img, 30, 200, ty, ty + Math.round(title.height))
            var by = Math.round(body.mapToItem(s, 0, 0).y)
            var bl = inkLeft(img, 30, 200, by, by + Math.round(body.height))
            console.log("N61-23 ink: title from x " + tl + " (S08 39), body from x " + bl + " (S08 38)")
            // Noto Sans' R starts 3 px in, the emulator font's about 1 px: the title's ink 2 px right
            verify(Math.abs(tl - 41) <= 1, "the title's ink from x 41: " + tl)
            verify(Math.abs(bl - 38) <= 1, "the body's ink from x 38: " + bl)
            // the surface's colour on the screen, between the disc and the edge
            var sc = px(img, 28, Math.round(dp.y + 60))
            verify(near(sc, [0x24, 0x26, 0x2b], 2), "#24262B on the screen: " + sc)
        }

        // Every opened card is #24262B, also one whose full layout is no taller than its collapsed
        // one (the colour follows the open progress, not the height)
        function test_n61_23_short_card_colour() {
            var n = notif({ replacesId: 2302, summary: "Sam", body: "On my way" })
            var c = make("NotificationCard.qml", { width: 344, notification: n })
            wait(100)
            compare(String(byName(c, "cardSurface").color), "#2f3036", "closed")
            var collapsedH = c.collapsedHeight
            var bg = byName(c, "cardSurface")
            // the colour at each step of the open progress: surfaceContainer -> surfaceContainerLow
            var steps = []
            c.openPChanged.connect(function () { steps.push([c.openOpacity, bg.color.r * 255]) })
            c.expanded = true
            settle(c)
            verify(c.surfaceFullHeight + c.actionsFullHeight <= collapsedH + 0.5, "no taller open")
            compare(String(bg.color), "#24262b", "open")
            verify(steps.length > 2, "steps of the open progress")
            for (var i = 0; i < steps.length; i++)
                fuzzyCompare(steps[i][1], 0x2f + (0x24 - 0x2f) * steps[i][0], 1, "the colour on the open progress at " + steps[i][0])
            c.expanded = false
            settle(c)
            compare(String(byName(c, "cardSurface").color), "#2f3036", "closed again")
        }

        // A full swipe whose notification is not taken away yet (a phone's that waits for the
        // phone): the row is the cleared pill until the card comes back, then a card again at its
        // own height
        function test_n61_20_cleared_comes_back() {
            var s = stream()
            Lipstick.notificationModel.add(notif({ replacesId: 2010, appName: "Shell", summary: "Retest one", body: "Stays" }))
            tryVerify(function () { return s.listView && s.listView.count === 1 }, 4000)
            wait(300)
            var row = s.rowItems[2010]
            var sw = swipeOf(row)
            var acts = 0
            sw.primaryAction.connect(function () { acts++ })
            var y = row.mapToItem(top, 0, 0).y + row.height / 2
            dragTo(70, 383, y)
            mouseRelease(top, 383, y)
            tryVerify(function () { return acts === 1 }, 3000, "cleared")
            verify(row.cleared, "the row is the pill")
            compare(sw.state_, "revealed")
            // another card's reveal covers it (SwipeToReveal _coverOthers)
            sw.settle("covered")
            tryVerify(function () { return sw.state_ === "covered" && Math.abs(sw.offset) < 0.5 }, 3000, "the card back")
            verify(!row.cleared, "a card again")
            verify(row.visible)
            var c = cardOf(row)
            fuzzyCompare(row.height, c.height, 0.5, "at its own height")
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
