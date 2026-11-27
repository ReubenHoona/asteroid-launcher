// SPDX-License-Identifier: BSD-3-Clause
//
// The face picker (src/qml/misc/FacePicker.qml) and its Add new list (src/qml/misc/FaceAddList.qml) drawn with
// the image's controls on the repo mocks. 384 x 384 px = 192 dp, 1 dp = 2 px. WO-11 of the image 60 defect list:
//
// D60-28: a preview is the face on its own background inside a 4 px #202124 ring, black inside
// (managementui_border_color, managementui_items_border_width 2 dp). The face on the watch is the snapshot taken
// at the open, a face with a cached snapshot is that snapshot (CP3A kdu.java:305-345, kch.java:134-150); an eos
// face is drawn over the wallpaper, so the wallpaper goes under a snapshot, and under the shipped picture, which
// is drawn only while there is no snapshot: never two pictures at once.
// D60-29: the chip stays in the middle (x 140-244) and the arrows keep their slots (x 68 and 252, 8 px gaps):
// CP3A hides them INVISIBLE (ibk.java:30-31), the row is not centred again. The buttons of one centred item
// change in one transition (kdu.java:221-240, iaf.java:188-199); its Slide starts each button that changes at
// its ibj delay (chip 75 ms, arrows 150 ms) less the smallest of them (Transition.createAnimators): a lone
// arrow waits 0 ms, the chip with an arrow 0 ms and the arrow 75 ms. A button that hides waits, then slides
// down by the row's height (8 + 13 + 32 + 5 = 58 dp) in 375 ms (Slide, Accelerate); one that shows fades in
// over 450 ms (Fade IN, AccelerateDecelerate) and slides up after its wait in 375 ms (Decelerate)
// (ibk.java:13-27).
// D60-30: CP3A's glyphs: quantum_gm_ic_arrow_left/right_vd_theme_24 (management_ui_root_layout.xml:47,62),
// filled carets in a 24 dp box in primary; pencil_icon.xml (iaf.java:277-283), the outlined pencil 20 x 18 dp
// inset 2 / 3 dp in a 24 dp box, in onPrimary.
// D60-31: the curved face name in onSurface #E8E7EE.
// D60-32: the names fade in on the ValueAnimator default, AccelerateDecelerate (= InOutSine)
// (ManagementView.java:580-587); N61-36 takes the emulator's times: hidden 100 ms, in over 50 ms.
// D60-33: the Add new list follows a swipe right as CP3A's SwipeDismissFrameLayout (gar.java:174-194,
// gax.java:36-127): scale 1 - 0.3 p with the right edge pinned, dim min(0.3, p / 2); it goes past 0.33 W (not
// moving back) or on a fling of 500 dp/s on a 1.0/600 spring to x = W and the carousel is back
// (iax.java:15-26), otherwise it springs back.
//
// N61-19: the fresh carousel leads with Concentric, the default face (FP.defaults), as the Wear OS 6 emulator.
// N61-35 (S15, S15-b, S15-c, M11's first frame): every preview, the face on the watch included, is the face at
// 10:09 on Thursday 24 May: an eos face's picture drawn for the favourite by FacePreviewRenderer (its style; the
// file FP.renderKey(id) of the cache), else the shipped 384 px picture. No snapshot of the live face is taken and
// the picker does not wait: it shows in the frame of the open. The previews' centre is y 171: the ring's box
// x 69-315, y 48-294, the right neighbour's ring at x 347-350 (dimmed to #101012), the Add new disc x 132-252,
// y 111-231. This overrides D60-28's live and cached snapshots; its ring, its fallback pictures (now the 384 px
// set) and the wallpaper under the pictures stay.
// N61-36 (M11): the open is a cut to the centre preview at the face's size, held 30 ms, then two underdamped
// springs: the previews' scale 1.613 -> 1 (WearSpring 627 / 0.67: under 1 by 6 % of the travel, settled in about
// 270 ms) and their centre 192 -> 171 (700 / 0.53: past 171 by 14 %, about 330 ms); the names, the chip and the
// arrows are hidden 100 ms, then in over 50 ms. Leaving without a change (dismiss: the side button, the crown
// on Add new, the idle timeout over the add list) is a cut: the picker is gone in the same frame, no zoom back,
// no away exit; choosing a face still grows the carousel into it.
// N61-37 (n6137, the emulator's own removal): no delete control at rest. A hold on the middle favourite that is not
// on the watch lifts it; dragged up it follows the finger 1:1, its name hides and a trash disc grows under it
// (58 px at (192, 239) after 90 px, 97 px at (192, 225) and alpha 0.6 after 150 px); a fling up (500 dp/s)
// removes it at once and the next slides in; a slow release springs back; the face on the watch does not move;
// a hold let go where it was puts the face on.
//
// Shots go to /tmp/wo11-shots. Run by newlook-wt/l6h/run.sh fp (qmltestrunner under qemu-aarch64 on the image
// rootfs; the picker staged as module LauncherQml at its resource paths, the repo's 384 px and 182 px pictures
// as previews384/ and previews182/, the repo's watchfaces/ and watchfaces-preview/ (every size) as they are,
// the stand-in face stage/watchfaces/990-stub-1009.qml with src/eoskit as
// stage/eoskit, and in /tmp/wo11-prev the fixtures r1-1009.png (a picture of r1, transparent as the watch's GL
// grabs are: the white block at x 172-212, y 100-140) and r2.png (a live snapshot of the earlier picker's
// cache, which must not show)).
import QtQuick
import QtQuick.Shapes
import QtTest
import Qt.labs.folderlistmodel
import org.asteroid.controls
import LauncherQml
import LauncherTest
import "LauncherQml/facepicker.js" as FP

Item {
    id: top
    width: 384; height: 384

    // the launcher's context properties (lipstick localemanager.cpp)
    QtObject { id: localeManager; property string changesObserver: "" }
    // MainScreen's clock, as the faces see it: 07:29 (M11's live face), not the pictures' 10:09
    property var wallClock: ({ time: new Date(2026, 10, 26, 7, 29, 0) })

    // the cached previews (the launcher's FacePreviews, C++): files in /tmp/wo11-prev
    QtObject {
        id: facePreviews
        function path(id) { return "/tmp/wo11-prev/" + id + ".png" }
        function url(id) {
            var u = "file://" + path(id)
            var x = new XMLHttpRequest()
            try {
                x.open("GET", u, false)
                x.send()
            } catch (e) {
                return ""
            }
            return x.responseText.length > 0 ? u : ""
        }
        function exists(id) { return url(id) !== "" }
        function remove(id) { }
    }

    // the favourites (FaceFavourites): what the picker reads and calls
    QtObject {
        id: store
        property var entries: []
        property string currentId: ""
        property var installed: []
        function indexOf(id) {
            for (var i = 0; i < entries.length; i++)
                if (entries[i].id === id)
                    return i
            return -1
        }
        function choose(id) { currentId = id }
        function move(id, dir) {
            var i = indexOf(id), j = i + dir
            if (i < 0 || j < 0 || j >= entries.length)
                return false
            var e = entries.slice()
            var t = e[i]
            e[i] = e[j]
            e[j] = t
            entries = e
            return true
        }
        function remove(id) {
            var i = indexOf(id)
            if (i < 0)
                return false
            var e = entries.slice()
            e.splice(i, 1)
            entries = e
            return true
        }
        function add(file) {
            var id = "added" + entries.length
            entries = entries.concat([{ id: id, file: file }])
            return id
        }
    }
    function face(stem) { return "file:///usr/share/asteroid-launcher/watchfaces/" + stem + ".qml" }

    // the home screen as MainScreen draws it: the wallpaper (110 % of the screen, centred) under the face
    Item {
        anchors.fill: parent
        Item {
            id: wallpaper
            width: 422.4
            height: 422.4
            anchors.centerIn: parent
            Rectangle { anchors.fill: parent; color: "#2050a0" }
            // a mark at screen x 20-40, y 180-200: where the preview puts the wallpaper
            Rectangle { x: 19.2 + 20; y: 19.2 + 180; width: 20; height: 20; color: "#e04020" }
        }
        Item {
            id: liveFace
            anchors.fill: parent
            // the face: a white block (the digits), nothing under it (an eos face is drawn over the wallpaper)
            Rectangle { x: 172; y: 100; width: 40; height: 40; color: "#ffffff" }
            // N61-35: no snapshot of the face on the watch: every grab of it is counted (and refused)
            property int grabs: 0
            function grabToImage(callback, size) {
                grabs++
                return false
            }
        }
    }

    Component { id: pickerC; FacePicker { } }
    Component { id: rendererC; FacePreviewRenderer { } }
    readonly property string stubFace: Qt.resolvedUrl("stage/watchfaces/990-stub-1009.qml").toString()

    TestCase {
        id: tc
        name: "FacePicker"
        when: windowShown

        property var picker: null
        readonly property real dp: 2

        function near(a, b, eps, msg) { verify(Math.abs(a - b) <= eps, (msg || "") + ": " + a + " vs " + b) }
        function find(item, name) {
            if (!item)
                return null
            if (item.objectName === name)
                return item
            var lists = [item.data, item.children, item.contentItem ? item.contentItem.children : null]
            for (var k = 0; k < lists.length; k++) {
                var d = lists[k]
                if (d)
                    for (var i = 0; i < d.length; i++) {
                        if (!d[i])
                            continue
                        var r = find(d[i], name)
                        if (r)
                            return r
                    }
            }
            return null
        }
        // an animation by name in an animation, a Transition or an item's transitions
        function findAnim(a, name) {
            if (!a)
                return null
            if (a.objectName === name)
                return a
            var lists = [a.animations, a.transitions]
            for (var k = 0; k < lists.length; k++) {
                var l = lists[k]
                if (l)
                    for (var i = 0; i < l.length; i++) {
                        var r = findAnim(l[i], name)
                        if (r)
                            return r
                    }
            }
            return null
        }
        function cells() {
            var out = []
            var c = find(picker, "eosFaceList").contentItem.children
            for (var i = 0; i < c.length; i++)
                if (c[i].objectName === "eosFaceCell")
                    out.push(c[i])
            out.sort(function (a, b) { return a.x - b.x })
            return out
        }
        function cellOf(fid) {
            var c = cells()
            for (var i = 0; i < c.length; i++)
                if (c[i].fid === fid)
                    return c[i]
            return null
        }
        // the SVG path of a Shape's first ShapePath
        function svgPath(shape) {
            var els = shape.data[0].pathElements
            for (var i = 0; i < els.length; i++)
                if (els[i].path !== undefined)
                    return els[i].path
            return ""
        }
        function colourNear(img, x, y, hex, tol, msg) {
            var c = Qt.color(hex)
            var r = img.red(x, y), g = img.green(x, y), b = img.blue(x, y)
            verify(Math.abs(r - Math.round(c.r * 255)) <= tol && Math.abs(g - Math.round(c.g * 255)) <= tol
                   && Math.abs(b - Math.round(c.b * 255)) <= tol,
                   msg + " at " + x + "," + y + ": " + r + "," + g + "," + b + " vs " + hex)
        }

        // pairs [id, face stem]
        function setup(pairs, current) {
            store.entries = pairs.map(function (p) { return { id: p[0], file: top.face(p[1]) } })
            store.currentId = current
            store.installed = [top.face("018-modular"), top.face("021-classic"), top.face("022-large"),
                               top.face("019-list"), top.face("020-stacked"), top.face("023-bold-numerals")]
            picker = pickerC.createObject(top, { store: store, liveFace: liveFace, awake: true })
            if ("background" in picker)
                picker.background = wallpaper
            // the repo's 384 px pictures, when the runner stages them (else nothing loads: the placeholder)
            picker.pictureFolder = Qt.resolvedUrl("previews384/").toString()
            picker.sync()
        }
        function openPicker() {
            picker.open()
            tryCompare(picker, "shown", true, 10000)
            atRest()
            tryCompare(picker, "namesOpacity", 1, 5000)
            wait(50)
        }
        // the open's two springs at rest (zoom passes 1 on the overshoot before)
        function atRest() {
            var a = find(picker, "eosFaceScaleSpring"), b = find(picker, "eosFaceYSpring")
            tryVerify(function () { return picker.arrived && !a.running && !b.running }, 10000, "the open at rest")
            compare(picker.zoom, 1, "zoom 1 at rest")
        }
        // the row buttons come to rest (their transitions run up to 525 ms)
        function settleRow() {
            wait(Motion.duration(700))
        }
        function cleanup() {
            if (picker) {
                picker.closeNow()
                picker.destroy()
                picker = null
                wait(30)
            }
            if (renderer) {
                renderer.destroy()
                renderer = null
            }
        }
        property var renderer: null

        // ---- N61-35 ----------------------------------------------------------------------------------------
        // r1 has its picture in the cache (/tmp/wo11-prev/r1-1009.png from the runner: 384 px, transparent, the
        // white block); r2, the face on the watch, has none, only an old live snapshot (r2.png), which must not
        // show: it is the shipped 10:09 picture. The software renderer's own grabs are opaque (black where the item
        // is empty), the watch's GL grabs are not: the layering of the wallpaper is checked on r1.
        function test_n61_35_previews() {
            setup([["r1", "018-modular"], ["r2", "021-classic"], ["r3", "022-large"]], "r2")
            near(picker.previewCy, 171, 0.001, "the previews' centre: y 171 at 384 px (S15)")
            near(FP.previewCy(384), 171, 0.001, "FP.previewCy")
            // the open: at once, in this frame, with no grab of the face on the watch
            liveFace.grabs = 0
            picker.open()
            compare(picker.shown, true, "shown in the frame of the open: no wait for a snapshot")
            near(picker.zoom, 0, 0.001, "at the face's size")
            compare(liveFace.grabs, 0, "no grabToImage of the face on the watch")
            atRest()
            tryCompare(picker, "namesOpacity", 1, 5000)
            wait(50)
            compare(liveFace.grabs, 0, "none during the open either")
            compare("liveUrl" in picker, false, "no live snapshot")
            compare("opening" in picker, false, "no wait for grabs")

            var c = cellOf("r2")
            var ring = find(c, "eosFaceRing")
            compare(String(ring.color), "#000000", "inside the ring is black")
            near(ring.border.width, 2 * dp, 0.01, "the ring is managementui_items_border_width 2 dp")
            compare(String(ring.border.color), "#202124", "managementui_border_color")
            var tl = ring.mapToItem(picker, 0, 0), br = ring.mapToItem(picker, ring.width, ring.height)
            near(tl.x, 69, 1, "ring box left (S15 x 69)")
            near(br.x, 315, 1, "ring box right (S15 x 314, box 315)")
            near(tl.y, 48, 1, "ring box top (S15 y 48)")
            near(br.y, 294, 1, "ring box bottom (S15 y 293, box 294)")
            // the face on the watch: its shipped 10:09 picture (no picture of its own yet), not a snapshot
            var rendered = find(c, "eosFaceRender"), shipped = find(c, "eosFaceShipped"), bg = find(c, "eosFaceBackground")
            compare(String(rendered.source), "", "no picture of r2's own; the old live snapshot r2.png is not used")
            verify(String(shipped.source).indexOf("previews384/021-classic.png") >= 0, "the 384 px picture: " + shipped.source)
            compare(shipped.sourceSize.width, 384, "read at 384 px")
            compare(shipped.asynchronous, false, "the face on the watch loads at once (the open's first frame)")
            // the wallpaper under it, when its snapshot (the one grab of the open) is there
            tryVerify(function () { return picker.backgroundUrl !== "" }, 5000, "the wallpaper snapshot")
            if (shipped.status === Image.Ready)
                tryVerify(function () { return bg.visible }, 5000, "the wallpaper under the picture")
            near(bg.width, 238 * 1.1, 0.6, "the wallpaper at the preview's scale (110 % of the face)")
            near(bg.x, (238 - 238 * 1.1) / 2, 0.6, "centred as on the screen")

            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-35-rest.png")
            colourNear(img, 192 + 121, 171, "#202124", 4, "the 4 px ring at the right")
            colourNear(img, 192 - 121, 171, "#202124", 4, "the ring at the left")
            colourNear(img, 192, 292, "#202124", 4, "the ring at the bottom (y 290-293)")
            colourNear(img, 192, 296, "#000000", 4, "black under the ring")
            colourNear(img, 348, 171, "#101012", 4, "the right neighbour's ring at x 347-350, dimmed to 50 %")
            colourNear(img, 345, 171, "#000000", 4, "black left of it")

            // the Add new disc on the same centre (S15-c: x 132-251, y 111-230, the QML box 132-252 x 111-231)
            var faces = find(picker, "eosFaceList")
            faces.currentIndex = store.entries.length
            tryCompare(picker, "centredAdd", true, 2000)
            wait(Motion.duration(400))
            var addCells = cells().filter(function (x) { return x.isAdd })
            compare(addCells.length, 1, "one Add new item")
            var plus = find(addCells[0], "eosFaceAdd")
            var pt = plus.mapToItem(picker, 0, 0), pb = plus.mapToItem(picker, plus.width, plus.height)
            near(pt.x, 132, 1, "Add new disc left")
            near(pb.x, 252, 1, "Add new disc right")
            near(pt.y, 111, 1, "Add new disc top")
            near(pb.y, 231, 1, "Add new disc bottom")
            var tap = find(addCells[0], "eosFaceTap")
            near(tap.mapToItem(picker, 0, tap.height / 2).y, 171, 1, "its tap area on the same centre")
            img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-35-add.png")
            colourNear(img, 192, 115, String(Theme.color.primary), 6, "the disc's top")
            colourNear(img, 192, 108, "#000000", 6, "black above it")

            // r3: the shipped picture, no picture of its own
            var c3 = cellOf("r3")
            verify(c3 !== null, "r3 is made (cache buffer)")
            compare(String(find(c3, "eosFaceRender").source), "", "no picture of r3's own")
            compare(find(c3, "eosFaceShipped").opacity, 1, "the shipped picture of r3")

            // r1: its own picture (the file of the cache), on the wallpaper, once
            picker.positionAt("r1")
            wait(Motion.duration(400))
            c = cellOf("r1")
            rendered = find(c, "eosFaceRender")
            verify(rendered.ready, "r1's own picture")
            verify(String(rendered.source).indexOf("/tmp/wo11-prev/r1-1009.png") >= 0, "the cache's r1-1009: " + rendered.source)
            compare(find(c, "eosFaceShipped").opacity, 0, "no shipped picture under it")
            verify(find(c, "eosFaceBackground").visible, "the wallpaper under it")
            verify(find(c, "eosFaceMask").visible, "the corners masked round")
            img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-35-render.png")
            // the picture's block (x 172-212, y 100-140 of 384) at the preview's scale (238 / 384, from x 73, y 52)
            var k = 238 / 384
            colourNear(img, Math.round(73 + 192 * k), Math.round(52 + 120 * k), "#ffffff", 8, "r1's picture")
            colourNear(img, 130, 230, "#2050a0", 8, "the wallpaper under r1's picture")
            colourNear(img, Math.round(73 + 30 * k), Math.round(52 + 190 * k), "#e04020", 12,
                       "the wallpaper's mark where the screen has it")
            // a new picture of a favourite (previewVersion): read again
            var before = String(rendered.source)
            picker.previewVersion++
            verify(String(rendered.source) !== before, "the source changes with previewVersion")
            tryVerify(function () { return rendered.ready }, 5000, "and loads")
            picker.closeNow()
            compare(picker.backgroundUrl, "", "the wallpaper's snapshot is let go at the close")
            compare(liveFace.grabs, 0, "never a grab of the face on the watch")
        }

        // the picture of an eos face's favourite: the stand-in face drawn at 10:09 on Thursday 24 May with the
        // favourite's style (Color: Watermelon), never at the wall clock's 07:29; written to the cache as
        // c1-1009.png and shown by the picker as the face on the watch
        function test_n61_35_render() {
            // the favourite drawn here has an id of this run only: the cache folder /tmp/wo11-prev is the same
            // for every run, so a picture another run left there (or wrote at the same time) can never stand
            // in for the one this test draws (renderMissing() would find it and draw nothing)
            var c1 = "c" + Date.now()
            Backend.confSet("/org/asteroidos/watchface/style/" + c1, JSON.stringify({ color: "watermelon" }))
            store.entries = [{ id: c1, file: top.stubFace }, { id: "c3", file: top.face("000-default-digital") }]
            store.currentId = c1
            renderer = rendererC.createObject(top, { cache: facePreviews, store: store })
            verify(renderer !== null, "the renderer")
            compare(FP.upstreamFace(top.face("000-default-digital")), true, "000 reads wallClock: its shipped picture")
            compare(FP.upstreamFace(top.face("017-contemporary-digital-rings")), true, "017 too")
            compare(FP.upstreamFace(top.face("018-modular")), false, "018 is an eos face")
            compare(FP.upstreamFace(top.face("027-concentric")), false, "027 is an eos face")
            compare(FP.renderKey("c1"), "c1-1009", "the cache file of c1's picture")
            compare(renderer.render("c3"), false, "an upstream face is not drawn")
            var loader = find(renderer, "eosFaceRenderLoader")
            verify(loader !== null, "the hidden instance's loader")
            var seen = null
            var spy = function () {
                if (loader.item && seen === null)
                    seen = { h: loader.item.hour24, m: loader.item.minute, d: loader.item.now.getDate(),
                             wd: loader.item.now.getDay(), ambient: loader.item.ambient }
            }
            loader.itemChanged.connect(spy)
            compare(renderer.renderMissing(), 1, "c1 has no picture yet: drawn; c3 is an upstream face")
            tryVerify(function () { return seen !== null }, 5000, "the instance was made")
            loader.itemChanged.disconnect(spy)
            compare(seen.h, 10, "drawn at 10:09 (hour), not at the wall clock's 07:29")
            compare(seen.m, 9, "minute 09")
            compare(seen.d, 24, "on the 24th")
            compare(seen.wd, 4, "a Thursday")
            compare(seen.ambient, false, "interactive")
            tryCompare(renderer, "version", 1, 10000)
            tryCompare(renderer, "busy", false, 5000)
            verify(facePreviews.exists(c1 + "-1009"), "written to the cache as <id>-1009")
            compare(loader.item, null, "the instance is gone")
            compare(renderer.renderMissing(), 0, "nothing left to draw")

            // the picker shows it as the face on the watch
            picker = pickerC.createObject(top, { store: store, liveFace: liveFace, awake: true, background: wallpaper })
            picker.pictureFolder = Qt.resolvedUrl("previews384/").toString()
            picker.previewVersion = renderer.version
            picker.sync()
            liveFace.grabs = 0
            openPicker()
            compare(liveFace.grabs, 0, "no grab of the face on the watch")
            var r = find(cellOf(c1), "eosFaceRender")
            verify(r.ready, "the picture of c1")
            verify(String(r.source).indexOf(c1 + "-1009.png") >= 0, String(r.source))
            wait(100)
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-35-stub.png")
            // the block of 10:09 (x 72-88, y 160-176 of 384) at the preview's scale, in Watermelon; nothing where
            // 07:29 would put it (x 232-248, y 112-128)
            var k = 238 / 384
            colourNear(img, Math.round(73 + 80 * k), Math.round(52 + 168 * k), "#ff7b78", 12, "10:09's block in Watermelon")
            var x0 = Math.round(73 + 240 * k), y0 = Math.round(52 + 120 * k)
            verify(img.red(x0, y0) < 120, "no block at 07:29's place: " + img.red(x0, y0))
            // a new style: the picture is drawn again (the editor closed)
            Backend.confSet("/org/asteroidos/watchface/style/" + c1, JSON.stringify({ color: "cloud" }))
            verify(renderer.render(c1), "drawn again")
            tryCompare(renderer, "version", 2, 10000)
            picker.previewVersion = renderer.version
            tryVerify(function () { return r.ready }, 5000, "read again")
            wait(100)
            img = grabImage(picker)
            colourNear(img, Math.round(73 + 80 * k), Math.round(52 + 168 * k), "#e4e4e4", 12, "now in Cloud")
        }

        // the repo's fallback pictures, now the 384 px set the carousel shows (src/watchfaces-preview/384, the
        // D60-28 GL renderer, N61-35), when the runner stages them next to this file as previews384/: 016 (10:09,
        // English) is a 75 % black disc with the
        // time cut out of it, a face drawn over the wallpaper (016-masked-spartan.qml): on the picker it shows
        // the wallpaper through its digits, not black on black. 009 (redrawn on GL) has no background either
        // (its dial is drawn on nothing, 009-analog-scientific-v2.qml): the wallpaper shows between its marks,
        // not black (the software renderer had drawn its layer.enabled dial as an opaque black square)
        function fileExists(u) {
            var x = new XMLHttpRequest()
            try {
                x.open("GET", u, false)
                x.send()
            } catch (e) {
                return false
            }
            return x.responseText.length > 0
        }
        function test_d60_28_fallbacks() {
            var folder = Qt.resolvedUrl("previews384/").toString()
            if (!fileExists(folder + "016-masked-spartan.png"))
                skip("the repo's previews are not staged as previews384/ next to the test")
            setup([["m1", "021-classic"], ["m2", "016-masked-spartan"], ["m3", "008-numerals-duo-synth-neon-green"],
                   ["m4", "009-analog-scientific-v2"]], "m1")
            picker.pictureFolder = folder
            openPicker()
            picker.positionAt("m2")
            var c = cellOf("m2")
            tryVerify(function () { return find(c, "eosFaceShipped").ready }, 5000, "016's picture")
            compare(find(c, "eosFaceRender").ready, false, "no picture of m2's own")
            verify(find(c, "eosFaceBackground").visible, "016 on the wallpaper")
            wait(150)
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-016.png")
            // the picture is drawn 238 px wide from x 73; two points of it, in units of its 182 px size: (111, 129)
            // inside a digit, (86, 46) on the disc (234, 272 and 181, 97 of the 384 px file)
            var cy = Math.round(picker.previewCy), k = 238 / 182
            colourNear(img, Math.round(73 + 111 * k), Math.round(cy - 119 + 129 * k), "#2050a0", 10,
                       "the wallpaper through a digit of 016")
            colourNear(img, Math.round(73 + 86 * k), Math.round(cy - 119 + 46 * k), "#081428", 6,
                       "016's disc: the wallpaper under 75 % black")
            // 008 (redrawn on GL: THURSDAY, 10 09, 2018-05-24) for a look
            picker.positionAt("m3")
            c = cellOf("m3")
            tryVerify(function () { return find(c, "eosFaceShipped").ready }, 5000, "008's picture")
            wait(150)
            grabImage(picker).save("/tmp/wo11-shots/d60-28-008.png")
            // 009: the wallpaper through its dial, at two points (182 px units) where the picture draws nothing
            // ((138, 138) between 4 and 5, (58, 131) between 7 and 8)
            picker.positionAt("m4")
            c = cellOf("m4")
            tryVerify(function () { return find(c, "eosFaceShipped").ready }, 5000, "009's picture")
            compare(find(c, "eosFaceRender").ready, false, "no picture of m4's own")
            verify(find(c, "eosFaceBackground").visible, "009 on the wallpaper")
            wait(150)
            img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-009.png")
            colourNear(img, Math.round(73 + 138 * k), Math.round(cy - 119 + 138 * k), "#2050a0", 10,
                       "the wallpaper through 009's dial (lower right)")
            colourNear(img, Math.round(73 + 58 * k), Math.round(cy - 119 + 131 * k), "#2050a0", 10,
                       "the wallpaper through 009's dial (lower left)")
            colourNear(img, 192 + 121, cy, "#202124", 4, "009's ring")
        }

        // the preview that flies in from Add new (picker.addFace, as FaceAddList's picked) is drawn as the
        // item it lands in: black inside the 4 px #202124 ring, the shipped picture on the wallpaper of the open
        // (not the old #202124 disc without the wallpaper), and it is round as stock's flyer (a bitmap of the
        // list item's preview frame, ManagementView.java:289-380): it leaves what lies outside its ring as it is.
        // 009's picture (no background) shows through its dial.
        function test_d60_28_flyer() {
            var folder = Qt.resolvedUrl("previews384/").toString()
            if (!fileExists(folder + "009-analog-scientific-v2.png"))
                skip("the repo's previews are not staged as previews384/ next to the test")
            setup([["f1", "021-classic"], ["f2", "018-modular"], ["f3", "022-large"]], "f1")
            picker.pictureFolder = folder
            openPicker()
            var flyer = find(picker, "eosFaceFlyer"), anim = find(picker, "eosFaceFlyAnim")
            verify(flyer !== null && anim !== null, "flyer and its animation")
            // picked in the list: a 160 px preview centred at (100, 260)
            picker.addFace(top.face("009-analog-scientific-v2"), 100, 260, 160)
            anim.pause()
            verify(flyer.visible, "the flyer is out")
            near(flyer.width, 160 + 2 * 2 * dp, 0.01, "the list's 160 px preview and the 4 px ring")
            var ring = find(flyer, "eosFlyerRing")
            compare(String(ring.color), "#000000", "black inside the ring, not the #202124 disc")
            near(ring.border.width, 2 * dp, 0.01, "the 4 px ring")
            compare(String(ring.border.color), "#202124", "managementui_border_color")
            // (the item's picture of the same face may still be loading: the flyer shares that load)
            tryVerify(function () { return flyer.backed }, 5000, "the flyer draws the wallpaper of the open")
            compare(find(flyer, "eosFlyerShipped").opacity, 0, "the picture is drawn in the cut, on the wallpaper")
            // the cut: centred rectangles that cover the picture's disc and stay inside the ring (3 px past
            // the 238 px picture at the slot, so at most 160 / 238 * 3 here)
            var pic = find(flyer, "eosFlyerPicture"), cut = []
            for (var i = 0; i < pic.children.length; i++)
                if (pic.children[i].objectName === "eosFlyerCut")
                    cut.push(pic.children[i])
            compare(cut.length, picker.flyerCut.length, "one clip per rectangle of the cut")
            verify(cut.length >= 10 && cut.length <= 30, "a cut of " + cut.length + " clips")
            var r = pic.width / 2
            for (i = 0; i < cut.length; i++) {
                near(cut[i].x + cut[i].width / 2, r, 0.01, "clip " + i + " centred")
                near(cut[i].y + cut[i].height / 2, r, 0.01, "clip " + i + " centred")
                verify(Math.sqrt(cut[i].width * cut[i].width + cut[i].height * cut[i].height) / 2 <= r + 3 * 160 / 238 + 0.01,
                       "clip " + i + " stays inside the ring")
                verify(cut[i].clip, "clip " + i + " clips")
            }
            for (var a = 0; a < 360; a += 3) {
                var px = r + (r - 0.01) * Math.cos(a * Math.PI / 180), py = r + (r - 0.01) * Math.sin(a * Math.PI / 180)
                var hit = false
                for (i = 0; i < cut.length && !hit; i++)
                    hit = px >= cut[i].x && px <= cut[i].x + cut[i].width && py >= cut[i].y && py <= cut[i].y + cut[i].height
                verify(hit, "the cut covers the disc's edge at " + a + " degrees")
            }
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-flyer-start.png")
            var k = flyer.side / 182, fx = flyer.x + 2 * dp, fy = flyer.y + 2 * dp
            colourNear(img, Math.round(fx + 138 * k), Math.round(fy + 138 * k), "#2050a0", 10,
                       "the wallpaper through the flyer's 009 dial")
            colourNear(img, Math.round(fx + 58 * k), Math.round(fy + 131 * k), "#2050a0", 10,
                       "the wallpaper through the flyer's 009 dial (left)")
            colourNear(img, Math.round(flyer.x + flyer.width - dp), Math.round(flyer.y + flyer.width / 2), "#202124", 4,
                       "the flyer's ring")

            // at the slot, still flying (the animation's own end values), then landed: the same picture
            for (i = 0; i < 4; i++)
                flyer[anim.animations[i].property] = anim.animations[i].to
            near(flyer.width, 238 + 8, 0.5, "at the slot: the item's 246 px")
            // the cut at the slot: out to 3 px past the 238 px picture at most, inside the 4 px ring
            var reach = 0
            for (i = 0; i < cut.length; i++)
                reach = Math.max(reach, Math.sqrt(cut[i].width * cut[i].width + cut[i].height * cut[i].height) / 2)
            verify(reach <= 119 + 3 + 0.01 && reach >= 119 + 2.9, "the cut reaches " + reach + " px from the centre")
            compare(FP.roundCut(0).length, 1, "no margin: one rectangle")
            compare(FP.roundCut(0)[0].width, 1, "the whole square")
            var flying = grabImage(picker)
            flying.save("/tmp/wo11-shots/d60-28-flyer-slot.png")
            anim.resume()
            tryCompare(anim, "running", false, 5000)
            verify(!flyer.visible, "the flyer is gone")
            var c = cellOf("added3")
            verify(c !== null, "the added face's item")
            compare(find(c, "eosFaceShipped").opacity, 1, "it shows its shipped picture")
            verify(find(c, "eosFaceBackground").visible, "on the wallpaper")
            wait(100)
            var landed = grabImage(picker)
            landed.save("/tmp/wo11-shots/d60-28-flyer-landed.png")
            // the picture inside the ring, in its upper left (away from the arrows, which the flyer passes under the
            // carousel's row): flying and landed alike
            var cy = Math.round(picker.previewCy), n = 0
            for (var gx = 30; gx <= 110; gx += 20)
                for (var gy = 30; gy <= 80; gy += 10) {
                    if (Math.sqrt((gx - 91) * (gx - 91) + (gy - 91) * (gy - 91)) > 80)
                        continue
                    var sx = Math.round(73 + gx * 238 / 182), sy = Math.round(cy - 119 + gy * 238 / 182)
                    var d = Math.abs(flying.red(sx, sy) - landed.red(sx, sy)) + Math.abs(flying.green(sx, sy) - landed.green(sx, sy))
                            + Math.abs(flying.blue(sx, sy) - landed.blue(sx, sy))
                    verify(d <= 24, "flying and landed alike at " + sx + "," + sy + ": " + d)
                    n++
                }
            verify(n >= 12, n + " points compared")
            colourNear(landed, Math.round(73 + 138 * 238 / 182), Math.round(cy - 119 + 138 * 238 / 182), "#2050a0", 10,
                       "landed: the wallpaper through 009's dial")
            colourNear(flying, Math.round(73 + 138 * 238 / 182), Math.round(cy - 119 + 138 * 238 / 182), "#2050a0", 10,
                       "flying: the wallpaper through 009's dial")
            colourNear(flying, 192 + 121, cy, "#202124", 4, "flying: the ring")
            // outside the ring, in the picture's square (its lower left corner): black flying and landed (the flyer is
            // round, no corner of wallpaper; N61-37 took the delete button that was tested here)
            var ox = 73 + 10, oy = Math.round(cy - 119 + 228)
            verify(Math.sqrt((ox - 192) * (ox - 192) + (oy - cy) * (oy - cy)) > 119 + 4 + 2, "outside the ring")
            colourNear(flying, ox, oy, "#000000", 6, "flying: no square corner")
            colourNear(landed, ox, oy, "#000000", 6, "landed: no square corner")
        }
        // without the wallpaper (no background item): the flyer's picture on black, as the item draws it
        function test_d60_28_flyer_no_wallpaper() {
            var folder = Qt.resolvedUrl("previews384/").toString()
            if (!fileExists(folder + "009-analog-scientific-v2.png"))
                skip("the repo's previews are not staged as previews384/ next to the test")
            setup([["g1", "021-classic"], ["g2", "018-modular"]], "g1")
            picker.background = null
            picker.pictureFolder = folder
            openPicker()
            compare(picker.backgroundUrl, "", "no wallpaper snapshot")
            var flyer = find(picker, "eosFaceFlyer"), anim = find(picker, "eosFaceFlyAnim")
            picker.addFace(top.face("009-analog-scientific-v2"), 192, 200, 160)
            anim.pause()
            tryVerify(function () { return find(flyer, "eosFlyerShipped").ready }, 5000, "the flyer's picture")
            verify(!flyer.backed, "nothing to cut")
            compare(find(flyer, "eosFlyerShipped").opacity, 1, "the picture as it is")
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-flyer-black.png")
            var k = flyer.side / 182, fx = flyer.x + 2 * dp, fy = flyer.y + 2 * dp
            colourNear(img, Math.round(fx + 138 * k), Math.round(fy + 138 * k), "#000000", 4,
                       "black through the dial, not #202124")
            colourNear(img, Math.round(flyer.x + flyer.width - dp), Math.round(flyer.y + flyer.width / 2), "#202124", 4,
                       "the ring")
            anim.resume()
            tryCompare(anim, "running", false, 5000)
        }

        // every face of the repo (src/watchfaces) has its picture in every size, size x size px: 112-182
        // (Settings; the Add new list reads 182) and 384 (the carousel and the flyer), and no picture is left
        // without its face; when the runner stages the repo's watchfaces/ and watchfaces-preview/ next to this
        // file. (001 had only its 384 px picture: "Cannot open" of FaceAddList in the launcher's journal.)
        function folderFiles(folder, filter) {
            var m = Qt.createQmlObject("import Qt.labs.folderlistmodel; FolderListModel { showDirs: false; "
                                       + "nameFilters: ['" + filter + "']; folder: '" + folder + "' }", top)
            tryVerify(function () { return m.status === FolderListModel.Ready && m.count > 0 }, 5000,
                      "listed " + folder)
            var out = []
            for (var i = 0; i < m.count; i++)
                out.push(String(m.get(i, "fileName")))
            m.destroy()
            return out
        }
        function test_d60_28_every_size() {
            var pv = Qt.resolvedUrl("watchfaces-preview/").toString()
            if (!fileExists(pv + "384/027-concentric.png"))
                skip("the repo's watchfaces/ and watchfaces-preview/ are not staged next to the test")
            var faces = folderFiles(Qt.resolvedUrl("watchfaces/").toString(), "*.qml").map(function (f) {
                return f.replace(/\.qml$/, "")
            })
            verify(faces.length >= 28, "the repo's faces: " + faces.length)
            verify(faces.indexOf("001-words-worte-palabras-mots") >= 0, "001 among them")
            var img = Qt.createQmlObject("import QtQuick; Image { asynchronous: false; cache: false }", top)
            var sizes = [112, 128, 144, 160, 182, 384]
            var gaps = [], orphans = [], wrong = []
            for (var s = 0; s < sizes.length; s++) {
                var have = folderFiles(pv + sizes[s] + "/", "*.png").map(function (f) {
                    return f.replace(/\.png$/, "")
                })
                for (var i = 0; i < faces.length; i++) {
                    if (have.indexOf(faces[i]) < 0) {
                        gaps.push(sizes[s] + "/" + faces[i])
                        continue
                    }
                    img.source = pv + sizes[s] + "/" + faces[i] + ".png"
                    tryVerify(function () { return img.status === Image.Ready || img.status === Image.Error }, 5000)
                    if (img.status !== Image.Ready || img.implicitWidth !== sizes[s] || img.implicitHeight !== sizes[s])
                        wrong.push(sizes[s] + "/" + faces[i] + " " + img.implicitWidth + "x" + img.implicitHeight)
                    img.source = ""
                }
                for (var j = 0; j < have.length; j++)
                    if (faces.indexOf(have[j]) < 0)
                        orphans.push(sizes[s] + "/" + have[j])
            }
            img.destroy()
            compare(gaps.join(" "), "", "faces without a picture")
            compare(wrong.join(" "), "", "pictures not size x size")
            compare(orphans.join(" "), "", "pictures without a face")
        }

        // ---- D60-29 ----------------------------------------------------------------------------------------
        function test_d60_29_row() {
            setup([["w1", "018-modular"], ["w2", "021-classic"], ["w3", "022-large"]], "w3")
            openPicker()
            settleRow()
            var chip = find(picker, "eosFaceChip"), left = find(picker, "eosFaceLeft"), right = find(picker, "eosFaceRight")
            var aY = picker.arrowY
            // the last favourite: the right arrow is hidden, the chip stays in the middle
            near(chip.x, 140, 1, "chip x on the last favourite")
            near(chip.x + chip.width, 244, 1, "chip right edge")
            near(left.x, 68, 0.5, "left arrow slot")
            compare(left.opacity, 1, "left arrow shown")
            near(left.y, aY, 0.5, "left arrow in its row")
            near(right.x, 252, 0.5, "the hidden right arrow keeps its slot")
            compare(right.opacity, 0, "right arrow hidden")
            compare(right.visible, false, "and not drawn")
            near(right.y, aY + 58 * dp, 0.5, "slid down by the row's 58 dp")
            near(chip.y, picker.chipY, 0.5, "chip in its row")
            grabImage(picker).save("/tmp/wo11-shots/d60-29-last.png")

            // the middle: both arrows, the same slots
            picker.positionAt("w2")
            settleRow()
            near(chip.x, 140, 1, "chip x in the middle")
            near(left.x, 68, 0.5, "left arrow")
            near(right.x, 252, 0.5, "right arrow")
            compare(right.opacity, 1, "right arrow shown again")
            near(right.y, aY, 0.5, "right arrow slid back up")
            // the show it ran (a Transition makes its animations when it first runs): the right arrow changed
            // alone, so it waited 150 - 150 = 0 ms
            var show = findAnim(right, "eosRowShow")
            verify(show !== null, "the show transition")
            compare(right.waitMs, 0, "a lone arrow shows at once")
            compare(findAnim(show, "eosRowShowWait").duration, Motion.duration(0), "arrow show waits 0 ms")
            var ss = findAnim(show, "eosRowShowSlide")
            compare(ss.duration, Motion.duration(375), "show slide 375 ms")
            compare(ss.easing.type, Easing.OutQuad, "Slide in on DecelerateInterpolator (1 - (1 - t)^2)")
            var sf = findAnim(show, "eosRowShowFade")
            compare(sf.duration, Motion.duration(450), "Fade in 450 ms")
            compare(sf.easing.type, Easing.InOutSine, "Fade on the ValueAnimator default (AccelerateDecelerate)")

            // to the first: the left arrow hides on its own, at once (0 ms), slides down 116 px and goes
            // transparent only at the end (Fade is MODE_IN only)
            picker.positionAt("w1")
            tryCompare(left, "on", false, 2000)
            compare(left.waitMs, 0, "a lone arrow hides at once")
            compare(chip.on, true, "the chip stays")
            compare(right.on, true, "the right arrow stays")
            compare(left.opacity, 1, "not faded at the start")
            near(left.x, 68, 0.5, "never moves sideways")
            near(chip.x, 140, 1, "the chip does not move")
            tryCompare(left, "opacity", 0, 5000)
            near(left.y, aY + 116, 0.5, "slid down by 116 px")
            near(left.x, 68, 0.5, "slot kept")
            near(chip.x, 140, 1, "chip x on the first favourite")
            near(right.x, 252, 0.5, "right arrow")

            // the hide it ran (ibk.java, ibj.java)
            var hide = findAnim(left, "eosRowHide")
            verify(hide !== null, "the hide transition")
            compare(findAnim(hide, "eosRowHideWait").duration, Motion.duration(0), "a lone arrow's hide waits 0 ms")
            var hs = findAnim(hide, "eosRowHideSlide")
            compare(hs.duration, Motion.duration(375), "hide slide 375 ms")
            compare(hs.easing.type, Easing.InQuad, "Slide out on AccelerateInterpolator (t^2)")

            // Add new: the chip and the right arrow hide in their places, in one change: the chip waits
            // 75 - 75 = 0 ms, the arrow 150 - 75 = 75 ms
            var faces = find(picker, "eosFaceList")
            faces.currentIndex = store.entries.length
            compare(chip.opacity, 1, "the chip is not faded at the start")
            tryCompare(chip, "on", false, 2000)
            compare(right.on, false, "the right arrow in the same change")
            compare(chip.waitMs, 0, "the chip waits 0 ms")
            compare(right.waitMs, 75, "the arrow with the chip waits 75 ms")
            tryCompare(chip, "opacity", 0, 5000)
            near(chip.x, 140, 1, "chip slot kept on Add new")
            near(chip.y, picker.chipY + 116, 0.5, "chip slid down")
            compare(findAnim(findAnim(chip, "eosRowHide"), "eosRowHideWait").duration, Motion.duration(0),
                    "the chip's hide waits 0 ms")
            tryCompare(right, "opacity", 0, 5000)
            near(right.x, 252, 0.5, "right arrow slot kept on Add new")
            compare(findAnim(findAnim(right, "eosRowHide"), "eosRowHideWait").duration, Motion.duration(75),
                    "the arrow's hide waits 75 ms")
            settleRow()

            // back from Add new to the last favourite: the chip and the left arrow show in one change, the
            // chip at once, the arrow 75 ms later
            faces.currentIndex = store.entries.length - 1
            tryCompare(chip, "on", true, 2000)
            compare(left.on, true, "the left arrow in the same change")
            compare(right.on, false, "the right arrow stays hidden on the last")
            compare(chip.waitMs, 0, "the chip waits 0 ms")
            compare(left.waitMs, 75, "the arrow with the chip waits 75 ms")
            tryCompare(chip, "opacity", 1, 5000)
            tryCompare(left, "opacity", 1, 5000)
            settleRow()
            near(chip.y, picker.chipY, 0.5, "the chip back up")
            near(left.y, aY, 0.5, "the arrow back up")
            compare(findAnim(findAnim(chip, "eosRowShow"), "eosRowShowWait").duration, Motion.duration(0),
                    "the chip's show waits 0 ms")
            compare(findAnim(findAnim(left, "eosRowShow"), "eosRowShowWait").duration, Motion.duration(75),
                    "the arrow's show waits 75 ms")
        }
        // the waits of one change (FP.rowWaits): the ibj delays less the smallest of the buttons that change
        function test_d60_29_waits() {
            function w(from, to) {
                var r = FP.rowWaits({ left: from[0], chip: from[1], right: from[2] },
                                    { left: to[0], chip: to[1], right: to[2] })
                return [r.left, r.chip, r.right]
            }
            compare(FP.ROW_CHIP_WAIT_MS, 75, "ibj: the chip 75 ms")
            compare(FP.ROW_ARROW_WAIT_MS, 150, "ibj: the arrows 150 ms")
            compare(w([true, true, true], [false, true, true]), [0, -1, -1], "middle to first: the left arrow alone, 0 ms")
            compare(w([false, true, true], [true, true, true]), [0, -1, -1], "first to middle: 0 ms")
            compare(w([true, true, true], [true, true, false]), [-1, -1, 0], "middle to last: the right arrow alone")
            compare(w([true, true, false], [false, false, false]), [75, 0, -1], "last to Add new: chip 0, arrow 75")
            compare(w([false, false, false], [true, true, false]), [75, 0, -1], "Add new to last: chip 0, arrow 75")
            compare(w([false, true, true], [false, false, false]), [-1, 0, 75], "first to Add new: chip 0, arrow 75")
            compare(w([false, true, true], [true, true, false]), [0, -1, 0], "two favourites: both arrows 0 ms")
            compare(w([true, true, true], [false, false, false]), [75, 0, 75], "all three: the arrows 75 ms after the chip")
            compare(w([false, true, false], [false, false, false]), [-1, 0, -1], "the chip alone: 0 ms")
            compare(w([true, true, false], [true, true, false]), [-1, -1, -1], "no change")
        }

        // ---- D60-30 ----------------------------------------------------------------------------------------
        function test_d60_30_glyphs() {
            setup([["g1", "018-modular"], ["g2", "021-classic"], ["g3", "022-large"]], "g2")
            openPicker()
            settleRow()
            var left = find(picker, "eosFaceLeft"), right = find(picker, "eosFaceRight"), chip = find(picker, "eosFaceChip")
            var lg = find(left, "eosFaceLeftGlyph"), rg = find(right, "eosFaceRightGlyph"), pg = find(chip, "eosFaceChipGlyph")
            verify(lg !== null && rg !== null && pg !== null, "the glyphs")
            compare(svgPath(lg), "M14,7l-5,5 5,5V7z", "quantum_gm_ic_arrow_left_vd_theme_24")
            compare(svgPath(rg), "M10,17l5,-5 -5,-5v10z", "quantum_gm_ic_arrow_right_vd_theme_24")
            compare(svgPath(pg), "M18.4088,1.9375L17.0588,0.5875C16.2788,-0.1925 15.0088,-0.1925 14.2288,0.5875"
                    + "L0.9988,13.8175V17.9975H5.1788L18.4088,4.7675C19.1988,3.9875 19.1988,2.7175 18.4088,1.9375Z"
                    + "M4.4088,16.0575L2.9988,15.9975V14.6375L12.8188,4.8175L14.2288,6.2275L4.4088,16.0575Z",
                    "pencil_icon.xml")
            compare(lg.data[0].fillColor, Theme.color.primary, "carets in primary")
            compare(pg.data[0].fillColor, Theme.color.onPrimary, "pencil in onPrimary")
            compare(pg.data[0].fillRule, ShapePath.OddEvenFill, "pencil evenOdd (an outline)")
            near(lg.width * lg.scale, 24 * dp, 0.01, "a 24 dp icon box")
            near(pg.width * pg.scale, 20 * dp, 0.01, "the pencil 20 dp wide")
            near(pg.height * pg.scale, 18 * dp, 0.01, "and 18 dp high")

            var img = grabImage(left)
            img.save("/tmp/wo11-shots/d60-30-left.png")
            colourNear(img, 33, 32, String(Theme.color.primary), 10, "the left caret is filled primary")
            colourNear(img, 44, 32, String(Theme.color.surfaceContainer), 6, "no shaft right of the caret")
            colourNear(img, 20, 32, String(Theme.color.surfaceContainer), 6, "nothing left of the tip")
            img = grabImage(right)
            img.save("/tmp/wo11-shots/d60-30-right.png")
            colourNear(img, 31, 32, String(Theme.color.primary), 10, "the right caret is filled primary")
            colourNear(img, 20, 32, String(Theme.color.surfaceContainer), 6, "no shaft left of the caret")
            img = grabImage(chip)
            img.save("/tmp/wo11-shots/d60-30-chip.png")
            colourNear(img, 63, 20, String(Theme.color.onPrimary), 12, "the pencil's cap in onPrimary")
            colourNear(img, 48, 30, String(Theme.color.onPrimary), 24, "the pencil's upper wall")
            colourNear(img, 51, 33, String(Theme.color.primary), 10, "an outline: the body is open (no filled box)")
            colourNear(img, 20, 32, String(Theme.color.primary), 6, "nothing beside the pencil")
        }

        // ---- D60-31 ----------------------------------------------------------------------------------------
        function test_d60_31_name_colour() {
            setup([["n1", "018-modular"], ["n2", "021-classic"]], "n1")
            openPicker()
            var c = cells()
            verify(c.length >= 2, "cells")
            for (var i = 0; i < c.length; i++) {
                var n = find(c[i], "eosFaceName")
                compare(String(n.color), String(Theme.color.onSurface), "the name is onSurface")
                compare(String(n.color), "#e8e7ee", "onSurface #E8E7EE")
            }
        }

        // ---- N61-36 ----------------------------------------------------------------------------------------
        // the springs: their parameters, their closed form (WearSpring.sample and settleMs: no frame clock), and
        // what a live open writes
        function test_n61_36_springs() {
            setup([["s1", "018-modular"], ["s2", "021-classic"]], "s1")
            var ss = find(picker, "eosFaceScaleSpring"), ys = find(picker, "eosFaceYSpring")
            verify(ss !== null && ys !== null, "the two springs")
            compare(ss.stiffness, 627, "scale: k 627 (M11)")
            compare(ss.dampingRatio, 0.67, "scale: zeta 0.67")
            compare(ys.stiffness, 700, "centre: k 700")
            compare(ys.dampingRatio, 0.53, "centre: zeta 0.53")
            compare(FP.OPEN_SCALE_STIFFNESS, 627)
            compare(FP.OPEN_Y_DAMPING, 0.53)
            // settled (99 %): the emulator's 259 ms and 320-340 ms
            var t1 = ss.settleMs(627, 0.67), t2 = ys.settleMs(700, 0.53)
            verify(t1 > 240 && t1 < 300, "the scale settles in " + t1 + " ms")
            verify(t2 > 300 && t2 < 360, "the centre settles in " + t2 + " ms")
            // the overshoot: the scale under 1 by 6 % of its 0.613 travel (0.964; the emulator's screen 0.69 dipping
            // to 0.66), the centre past 171 by 14 % of its 21 px (168.1)
            var s0 = FP.openScale(384), minS = 9, minY = 999, atS = 0, atY = 0
            for (var ms = 0; ms <= 600; ms++) {
                var vs = ss.sample(627, 0.67, s0, 1, 0, ms), vy = ys.sample(700, 0.53, 192, 171, 0, ms)
                if (vs < minS) { minS = vs; atS = ms }
                if (vy < minY) { minY = vy; atY = ms }
            }
            verify(minS > 0.955 && minS < 0.97, "the scale dips to " + minS + " at " + atS + " ms")
            verify(minY > 167.5 && minY < 169, "the centre rises to " + minY + " at " + atY + " ms")

            // a live open
            var seen = { minS: 9, minY: 999 }
            var onS = function () { seen.minS = Math.min(seen.minS, picker.previewScale) }
            var onY = function () { seen.minY = Math.min(seen.minY, picker.previewY) }
            picker.previewScaleChanged.connect(onS)
            picker.previewYChanged.connect(onY)
            picker.open()
            // the cut: the centre preview's picture is the screen
            near(picker.previewScale, s0, 0.0001, "at the face's size")
            near(picker.previewY, 192, 0.0001, "on the middle")
            var pic = find(cellOf("s1"), "eosFacePicture")
            var a = pic.mapToItem(picker, 0, 0), b = pic.mapToItem(picker, pic.width, pic.height)
            near(a.x, 0, 1, "the picture covers the screen (left)")
            near(b.x, 384, 1, "(right)")
            near(a.y, 0, 1, "(top)")
            near(b.y, 384, 1, "(bottom)")
            var hold = find(picker, "eosFaceOpenHold")
            compare(hold.interval, Motion.duration(30), "the cut's frame is held 30 ms (M11)")
            compare(FP.OPEN_HOLD_MS, 30)
            verify(hold.running && !ss.running && !ys.running, "held, the springs not yet started")
            compare(picker.progress, 0, "the face still counts as shown")
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-36-cut.png")
            tryVerify(function () { return ss.running && ys.running }, 2000, "then both springs run")
            tryCompare(picker, "arrived", true, 5000)
            compare(picker.progress, 1, "covered")
            tryVerify(function () { return !ss.running && !ys.running }, 5000, "both at rest")
            picker.previewScaleChanged.disconnect(onS)
            picker.previewYChanged.disconnect(onY)
            verify(seen.minS < 0.99 && seen.minS > 0.955, "the scale went under 1: " + seen.minS)
            verify(seen.minY < 169.5 && seen.minY > 167.5, "the centre went past 171: " + seen.minY)
            compare(picker.previewScale, 1, "at rest: 1")
            compare(picker.previewY, 171, "at rest: 171")
            compare(picker.zoom, 1, "zoom 1")
            compare(picker.progress, 1, "progress 1")
        }

        // the names, the chip and the arrows: hidden 100 ms after the cut, then in over 50 ms (InOutSine)
        function test_n61_36_names() {
            setup([["f1", "018-modular"], ["f2", "021-classic"]], "f1")
            var open = find(picker, "eosFaceOpenAnim")
            verify(open !== null, "open animation")
            var hidden = findAnim(open, "eosFaceNamesHidden"), fade = findAnim(open, "eosFaceNamesFade")
            verify(hidden !== null && fade !== null, "names hidden and fade")
            compare(hidden.duration, Motion.duration(100), "names hidden 100 ms")
            compare(fade.duration, Motion.duration(50), "then 50 ms")
            compare(fade.easing.type, Easing.InOutSine, "AccelerateDecelerate: (1 - cos(pi t)) / 2")
            compare(FP.NAMES_HIDDEN_MS, 100)
            compare(FP.NAMES_FADE_MS, 50)
            var row = find(picker, "eosFaceRow")
            var t = { t0: 0, first: -1, full: -1 }
            var on = function () {
                var dt = Date.now() - t.t0
                if (picker.namesOpacity > 0 && t.first < 0)
                    t.first = dt
                if (picker.namesOpacity >= 1 && t.full < 0)
                    t.full = dt
            }
            picker.namesOpacityChanged.connect(on)
            t.t0 = Date.now()
            picker.open()
            compare(picker.namesOpacity, 0, "hidden at the cut")
            compare(row.opacity, 0, "the chip and the arrows too")
            tryCompare(picker, "namesOpacity", 1, 5000)
            picker.namesOpacityChanged.disconnect(on)
            // 0 at 90 ms, 1 by 160 ms: by the animation's times (the test's frames under qemu come late, so the
            // live times can only be later: the first change is never before 90 ms)
            verify(hidden.duration > 90, "still hidden at 90 ms")
            verify(hidden.duration + fade.duration <= 160, "in by 160 ms")
            verify(t.first >= 90, "the names start at " + t.first + " ms")
            console.log("N61-36 names: first change at " + t.first + " ms, full at " + t.full + " ms (test clock)")
            compare(row.opacity, 1, "the chip and the arrows are in with them")
            compare(find(cells()[0], "eosFaceName").opacity, 1, "the name")
        }

        // leaving without a change: a cut, in the same frame, from rest and from the middle of the open; a face
        // chosen: the carousel grows into it
        function test_n61_36_cut() {
            setup([["c1", "018-modular"], ["c2", "021-classic"], ["c3", "022-large"]], "c2")
            verify(find(picker, "eosFaceAwayAnim") === null, "no away exit")
            verify(find(picker, "eosFaceExitAnim") === null, "no zoom back")
            var ss = find(picker, "eosFaceScaleSpring"), ys = find(picker, "eosFaceYSpring")
            var closed = 0
            var onClosed = function () { closed++ }
            picker.closed.connect(onClosed)
            // at rest on the face on the watch
            openPicker()
            picker.dismiss()
            compare(picker.shown, false, "gone in the same frame")
            compare(picker.visible, false, "not drawn")
            compare(picker.progress, 0, "the face is shown")
            compare(closed, 1, "closed")
            compare(store.currentId, "c2", "no change")
            // on another face (stock's away exit before): the same cut
            openPicker()
            picker.positionAt("c3")
            wait(Motion.duration(300))
            picker.dismiss()
            compare(picker.shown, false, "gone at once from another face")
            compare(store.currentId, "c2", "no change")
            // in the middle of the open: the springs stop where they are
            picker.open()
            tryVerify(function () { return ss.running && ys.running }, 2000, "the open is running")
            picker.dismiss()
            compare(picker.shown, false, "gone at once in the open")
            verify(!ss.running && !ys.running, "the springs stopped")
            compare(closed, 3, "closed each time")
            // the crown on Add new: dismiss, the same cut
            openPicker()
            find(picker, "eosFaceList").currentIndex = store.entries.length
            tryCompare(picker, "centredAdd", true, 2000)
            verify(picker.crownPressed(), "the crown is the picker's")
            compare(picker.shown, false, "the crown on Add new: a cut")
            // a face chosen: the carousel grows back to the face's size (CP3A), then goes
            openPicker()
            picker.positionAt("c1")
            wait(Motion.duration(300))
            var grow = find(picker, "eosFaceGrowAnim")
            picker.choose("c1")
            compare(store.currentId, "c1", "c1 on the watch")
            verify(grow.running, "the grow into the face")
            compare(picker.shown, true, "still shown while it grows")
            tryCompare(picker, "shown", false, 5000)
            picker.closed.disconnect(onClosed)
        }

        // ---- N61-37 ----------------------------------------------------------------------------------------
        // no delete control at rest; removal is the emulator's: a hold on a favourite that is not on the watch,
        // then a fling up (n6137)
        function holdAt(x, y) {
            mousePress(picker, x, y)
            wait(FP.LONG_PRESS_S * 1000 + 150)
        }
        function test_n61_37_no_button() {
            setup([["d1", "018-modular"], ["d2", "021-classic"], ["d3", "022-large"]], "d1")
            openPicker()
            compare(find(picker, "eosFaceDelete"), null, "no delete button on any preview")
            var c = cells()
            for (var i = 0; i < c.length; i++) {
                compare(find(c[i], "eosFaceDelete"), null, "none on " + c[i].fid)
                compare(find(c[i], "eosFaceTrash").visible, false, "no trash disc at rest on " + c[i].fid)
            }
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-37-rest.png")
            // where the corner button was (a 64 px disc at x 243-307, y 56-120): outside the ring black, inside it
            // the picture (here the wallpaper), never the button's surfaceContainer
            colourNear(img, 300, 70, "#000000", 6, "no disc at the preview's corner")
            var sc = Qt.color(String(Theme.color.surfaceContainer))
            verify(Math.abs(img.red(275, 88) - Math.round(sc.r * 255)) > 6 || Math.abs(img.blue(275, 88) - Math.round(sc.b * 255)) > 6,
                   "no surfaceContainer disc at its centre")
        }
        function test_n61_37_fling_removes() {
            setup([["d1", "018-modular"], ["d2", "021-classic"], ["d3", "022-large"]], "d1")
            openPicker()
            picker.positionAt("d2")
            wait(Motion.duration(400))
            compare(picker.centredFid, "d2")
            var c = cellOf("d2")
            holdAt(192, 171)
            compare(picker.holdId, "d2", "held")
            // 90 px up slowly: the preview follows 1:1, the name hides, the trash disc 58 px at (192, 239)
            for (var i = 1; i <= 9; i++)
                mouseMove(picker, 192, 171 - 10 * i, 40)
            near(c.dragUp, 90, 0.5, "the preview follows the finger")
            var ring = find(c, "eosFaceRing")
            near(ring.mapToItem(picker, 0, ring.height).y, 294 - 90, 1, "the ring's bottom 293 -> 203 (n6137 d1)")
            compare(find(c, "eosFaceName").opacity, 0, "the curved name is hidden")
            var trash = find(c, "eosFaceTrash")
            verify(trash.visible, "the trash disc")
            near(trash.width, 58.5, 1, "58 px across at 90 px (d1)")
            near(trash.mapToItem(picker, trash.width / 2, trash.height / 2).y, 239, 1, "centred at y 239")
            near(trash.mapToItem(picker, trash.width / 2, 0).x, 192, 1, "and x 192")
            near(trash.opacity, (90 - 73) / 128, 0.01, "coming in")
            // 150 px: 97 px at (192, 225), alpha 0.6 (i1)
            for (i = 1; i <= 6; i++)
                mouseMove(picker, 192, 81 - 10 * i, 40)
            near(c.dragUp, 150, 0.5, "150 px up")
            near(trash.width, 97.5, 1, "97 px across at 150 px (i1)")
            near(trash.mapToItem(picker, trash.width / 2, trash.height / 2).y, 225, 1, "centred at y 225")
            near(trash.opacity, (150 - 73) / 128, 0.01, "alpha 0.6: #0D0D0D over black")
            compare(String(trash.color), "#161616")
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/n61-37-drag150.png")
            colourNear(img, 192 - 40, 225, "#0d0d0d", 3, "the disc's fill, as i1")
            // a fling up (40 px steps, 5 ms apart): removed at once, the next slides into its place
            for (i = 1; i <= 4; i++)
                mouseMove(picker, 192, 21 - 40 * i, 5)
            mouseRelease(picker, 192, 21 - 160, Qt.LeftButton, Qt.NoModifier, 5)
            compare(store.entries.length, 2, "one favourite fewer")
            compare(store.indexOf("d2"), -1, "d2 removed")
            compare(store.currentId, "d1", "the face on the watch did not change")
            compare(picker.holdId, "", "let go")
            tryCompare(picker, "centredFid", "d3", 3000)
            wait(Motion.duration(400))
            grabImage(picker).save("/tmp/wo11-shots/n61-37-after.png")
            compare(picker.shown, true, "the picker stays")
        }
        function test_n61_37_slow_release_and_rules() {
            setup([["d1", "018-modular"], ["d2", "021-classic"], ["d3", "022-large"]], "d1")
            openPicker()
            picker.positionAt("d2")
            wait(Motion.duration(400))
            var c = cellOf("d2")
            // a slow drag of 150 px, then let go: back, nothing removed (i2, i3)
            holdAt(192, 171)
            for (var i = 1; i <= 15; i++)
                mouseMove(picker, 192, 171 - 10 * i, 40)
            mouseRelease(picker, 192, 21, Qt.LeftButton, Qt.NoModifier, 200)
            compare(store.entries.length, 3, "nothing removed")
            tryCompare(c, "dragUp", 0, 3000)
            compare(find(c, "eosFaceName").opacity, 1, "the name is back")
            compare(picker.shown, true, "still in the picker")
            // the face on the watch: a hold and a drag move nothing
            picker.positionAt("d1")
            wait(Motion.duration(400))
            var c1 = cellOf("d1")
            holdAt(192, 171)
            compare(picker.holdId, "", "the face on the watch cannot be held")
            mouseMove(picker, 192, 120, 40)
            mouseMove(picker, 192, 80, 40)
            compare(c1.dragUp, 0, "it does not move")
            compare(find(c1, "eosFaceTrash").visible, false, "no trash disc")
            mouseRelease(picker, 192, 80, Qt.LeftButton, Qt.NoModifier, 40)
            compare(store.entries.length, 3, "nothing removed")
            tryCompare(picker, "shown", false, 5000)
            compare(store.currentId, "d1", "a hold let go is a long press: the face is put on (it already was)")
            // a hold let go where it was on another face: it is put on (r6 'Applying theme')
            picker.open()
            atRest()
            picker.positionAt("d3")
            wait(Motion.duration(400))
            holdAt(192, 171)
            compare(picker.holdId, "d3", "held")
            mouseRelease(picker, 192, 171, Qt.LeftButton, Qt.NoModifier, 40)
            compare(store.currentId, "d3", "put on")
            compare(store.entries.length, 3, "nothing removed")
            tryCompare(picker, "shown", false, 5000)
            // the rules
            compare(FP.removeCommits(-1000, 2), true, "500 dp/s up")
            compare(FP.removeCommits(-999, 2), false, "slower")
            compare(FP.removeCommits(1500, 2), false, "down")
            var d = FP.removeDisc(90)
            near(d.size, 58.5, 0.01, "disc at 90")
            near(d.cy, 239, 0.1, "centre at 90")
            d = FP.removeDisc(150)
            near(d.size, 97.5, 0.01, "disc at 150")
            near(d.cy, 225, 0.1, "centre at 150")
            near(FP.removeDisc(400).size, FP.removeDisc(201).size, 0.001, "it stops growing")
            compare(FP.removeDisc(400).alpha, 1, "full")
            compare(FP.removeDisc(60).alpha, 0, "not yet")
        }

        // ---- D60-33 ----------------------------------------------------------------------------------------
        function openAdd() {
            setup([["s1", "018-modular"], ["s2", "021-classic"]], "s1")
            openPicker()
            var list = find(picker, "eosFaceAddList")
            list.open()
            tryCompare(list, "isOpen", true, 5000)
            wait(Motion.duration(400))
            return list
        }
        // a drag right from x 60, `steps` moves of `step` px, `ms` apart
        function dragRight(list, steps, step, ms) {
            mousePress(list, 60, 300)
            for (var i = 1; i <= steps; i++)
                mouseMove(list, 60 + step * i, 300, ms)
        }
        function test_d60_33_squeeze_and_back() {
            var list = openAdd()
            var panel = find(list, "eosAddPanel"), dim = find(list, "eosAddDim")
            verify(panel !== null && dim !== null, "panel and dim")
            // 96 px slowly (200 px/s): p = 0.25
            dragRight(list, 12, 8, 40)
            var p = 96 / 384
            near(list.swipeScale, 1 - 0.3 * p, 0.012, "scale 1 - 0.3 p")
            near(list.swipeX, 0.3 * p * 384 / 2, 1.5, "moved right by (1 - scale) W / 2")
            near(dim.opacity, Math.min(0.3, p / 2), 0.012, "dim min(0.3, p / 2)")
            var r = panel.mapToItem(list, panel.width, panel.height / 2)
            near(r.x, 384, 1.5, "the right edge stays pinned")
            var l = panel.mapToItem(list, 0, panel.height / 2)
            near(l.x, 384 - 384 * (1 - 0.3 * p), 2, "the left edge comes in")
            verify(panel.layer.enabled, "clipped round while it moves (clipToOutline)")
            // (the software renderer cannot run the round clip's shader: the shot is taken without it)
            panel.layer.enabled = false
            wait(30)
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-33-mid.png")
            panel.layer.enabled = Qt.binding(function () { return list.swiping })
            colourNear(img, 20, 192, "#000000", 6, "the carousel's black left of the squeezed list")
            colourNear(img, 381, 192, "#000000", 30, "the list's black disc still reaches the right edge")
            // released short of 0.33 W, not flung: back on the spring, the list stays
            mouseRelease(list, 60 + 96, 300, Qt.LeftButton, Qt.NoModifier, 60)
            tryCompare(list, "swipeX", 0, 5000)
            tryCompare(list, "swipeScale", 1, 5000)
            tryCompare(dim, "opacity", 0, 5000)
            verify(list.visible && list.isOpen, "still open")
            compare(panel.layer.enabled, false, "no layer at rest")
        }
        function test_d60_33_commit() {
            var list = openAdd()
            var panel = find(list, "eosAddPanel"), leave = find(list, "eosAddLeave")
            // 160 px slowly: past 0.33 W (126.7 px)
            dragRight(list, 20, 8, 40)
            var seen = { min: 1 }
            var conn = function () { seen.min = Math.min(seen.min, list.swipeScale) }
            list.swipeScaleChanged.connect(conn)
            mouseRelease(list, 60 + 160, 300, Qt.LeftButton, Qt.NoModifier, 60)
            verify(!leave.running, "not the reverse zoom")
            tryCompare(list, "visible", false, 5000)
            list.swipeScaleChanged.disconnect(conn)
            verify(seen.min >= 0.7 - 1e-6, "the scale stops at 0.7: " + seen.min)
            verify(seen.min <= 0.75, "and gets there on the way out: " + seen.min)
            compare(picker.shown, true, "the carousel is back")
            compare(picker.view, "carousel", "the carousel")
            compare(picker.zoom, 1, "not zoomed")
            compare(list.swipeX, 0, "reset")
            compare(list.swipeScale, 1, "reset")
            compare(panel.layer.enabled, false, "no layer")
        }
        // past 0.33 W, then a slow last step back: stock goes (the UP is where the last MOVE was, so not moving
        // back, gar.java:192), the step left is not a fling back (gar.java:195)
        function test_d60_33_last_step_back() {
            var list = openAdd()
            // 160 px slowly, then 8 px back in 40 ms: 152 px, past 0.33 W (126.7 px)
            dragRight(list, 20, 8, 40)
            mouseMove(list, 60 + 152, 300, 40)
            near(list.swipeX, 0.3 * (152 / 384) * 384 / 2, 1.5, "the list followed the step back")
            mouseRelease(list, 60 + 152, 300, Qt.LeftButton, Qt.NoModifier, 40)
            tryCompare(list, "visible", false, 5000)
            compare(picker.view, "carousel", "the carousel is back")
        }
        function test_d60_33_fling() {
            var list = openAdd()
            // 48 px fast (8 px per 4 ms = 2000 px/s): a fling of more than 500 dp/s
            dragRight(list, 6, 8, 4)
            mouseRelease(list, 60 + 48, 300, Qt.LeftButton, Qt.NoModifier, 4)
            tryCompare(list, "visible", false, 5000)
            compare(picker.view, "carousel", "the carousel")
        }
        function test_d60_33_rule() {
            var list = openAdd()
            // gar.java:186-194 on the 384 px screen (1 dp = 2 px, fling 500 dp/s = 1000 px/s)
            verify(list.dismissCommits(130, 0, 0, false), "past 0.33 W")
            verify(!list.dismissCommits(126, 0, 0, false), "short of 0.33 W")
            verify(!list.dismissCommits(200, 0, 0, true), "moving back at the release")
            verify(list.dismissCommits(20, 1000, 0, false), "a fling right")
            verify(!list.dismissCommits(20, 1000, 1200, false), "not when it goes more up or down")
            verify(!list.dismissCommits(200, -1200, 0, false), "a fling back cancels")
            verify(list.dismissCommits(200, -1000, 0, false), "only faster than 500 dp/s back")
            verify(!list.dismissCommits(20, 999, 0, false), "slower than 500 dp/s")
            // the spring of the way out or back (gax.java:55-62): 1.0 / 600, minimum visible change 0.5 px
            var spring = find(list, "eosAddDismissSpring")
            verify(spring !== null, "the dismiss spring")
            compare(spring.stiffness, 600, "stiffness 600")
            compare(spring.dampingRatio, 1.0, "damping ratio 1.0")
            compare(spring.visibilityThreshold, 0.5, "minimum visible change 0.5 px")
            compare(FP.ADD_DISMISS_STIFFNESS, 600, "FP stiffness")
            compare(FP.ADD_DISMISS_DAMPING, 1.0, "FP damping")
            compare(FP.ADD_DISMISS_MIN_CHANGE, 0.5, "FP minimum change")
        }

        // ---- N61-19: Concentric is the fresh watch's face and leads the carousel ---------------------------------
        // S15 / X-face-after-reset: Concentric, Utility, Classic, ..., Big Time last (ours: Modular for Utility,
        // Large for Big Time); its Add new entry is its name and its 10:09 picture.
        function test_n61_19_concentric_first() {
            var stems = ["000-default-digital", "010-analog-aviator", "018-modular", "019-list", "020-stacked",
                         "021-classic", "022-large", "023-bold-numerals", "024-step-ring", "027-concentric"]
            var installed = stems.map(function (st) { return top.face(st) })
            var names = FP.defaults(installed, top.face("027-concentric")).map(function (e) { return FP.plainName(e.file) })
            compare(names[0], "concentric")
            compare(names[1], "modular")
            compare(names[2], "classic")
            compare(names[3], "bold-numerals")
            compare(names[names.length - 1], "large")
            compare(names.length, 9, "the default faces only, the face on the watch among them")
            // a watch whose face is not a default keeps it, at the end of the fresh carousel
            names = FP.defaults(installed, top.face("024-step-ring")).map(function (e) { return FP.plainName(e.file) })
            compare(names[0], "concentric")
            compare(names[names.length - 1], "step-ring")
            // the Add new entry: the name and the shipped 10:09 picture
            compare(FP.displayName(top.face("027-concentric")), "Concentric")
            var img = Qt.createQmlObject("import QtQuick; Image { source: Qt.resolvedUrl('previews182/027-concentric.png') }", top)
            tryCompare(img, "status", Image.Ready, 5000)
            compare(img.implicitWidth, 182)
            compare(img.implicitHeight, 182)
            img.destroy()
            // and in the carousel's 384 px set (N61-35), as every face: the upstream ones and the eos ones
            var set384 = ["000-default-digital", "001-words-worte-palabras-mots", "017-contemporary-digital-rings",
                          "018-modular", "026-photo", "027-concentric"]
            for (var j = 0; j < set384.length; j++) {
                img = Qt.createQmlObject("import QtQuick; Image { source: Qt.resolvedUrl('previews384/" + set384[j] + ".png') }", top)
                tryCompare(img, "status", Image.Ready, 5000)
                compare(img.implicitWidth, 384, set384[j])
                compare(img.implicitHeight, 384, set384[j])
                img.destroy()
            }
        }
    }
}
