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
// D60-32: the names hide for 166 ms and fade in over 100 ms on the ValueAnimator default, AccelerateDecelerate
// (= InOutSine) (ManagementView.java:580-587).
// D60-33: the Add new list follows a swipe right as CP3A's SwipeDismissFrameLayout (gar.java:174-194,
// gax.java:36-127): scale 1 - 0.3 p with the right edge pinned, dim min(0.3, p / 2); it goes past 0.33 W (not
// moving back) or on a fling of 500 dp/s on a 1.0/600 spring to x = W and the carousel is back
// (iax.java:15-26), otherwise it springs back.
//
// Shots go to /tmp/wo11-shots. Run by motion-wt/wo11/run.sh (qmltestrunner under qemu-aarch64 on the image
// rootfs; the picker staged as module LauncherQml at its resource paths).
import QtQuick
import QtQuick.Shapes
import QtTest
import org.asteroid.controls
import LauncherQml
import "LauncherQml/facepicker.js" as FP

Item {
    id: top
    width: 384; height: 384

    // the launcher's context properties (lipstick localemanager.cpp)
    QtObject { id: localeManager; property string changesObserver: "" }

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
        }
    }

    Component { id: pickerC; FacePicker { } }

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
            picker.sync()
        }
        function openPicker() {
            picker.open()
            tryCompare(picker, "shown", true, 10000)
            tryCompare(picker, "zoom", 1, 10000)
            tryCompare(picker, "namesOpacity", 1, 5000)
            wait(50)
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
        }

        // ---- D60-28 ----------------------------------------------------------------------------------------
        // r1 has a cached snapshot with a transparent background (/tmp/wo11-prev/r1.png from the runner: 384 px,
        // the white block of liveFace), as the watch's GL grabs are. The software renderer of this test makes
        // its own grabs opaque (black where the item is empty), so the live snapshot hides what is under it here:
        // its layering is checked on the items, the pixels under a snapshot on r1.
        function test_d60_28_previews() {
            setup([["r1", "018-modular"], ["r2", "021-classic"], ["r3", "022-large"]], "r2")
            openPicker()
            var c = cellOf("r2")
            var ring = find(c, "eosFaceRing")
            verify(ring !== null, "ring")
            compare(String(ring.color), "#000000", "inside the ring is black, not filled grey")
            near(ring.border.width, 2 * dp, 0.01, "the ring is managementui_items_border_width 2 dp")
            compare(String(ring.border.color), "#202124", "managementui_border_color")
            near(ring.width, 238 + 8, 0.5, "outer 246 px")
            // the face on the watch: its snapshot over the wallpaper of the open, no shipped picture
            var shot = find(c, "eosFaceShot"), shipped = find(c, "eosFaceShipped"), bg = find(c, "eosFaceBackground")
            verify(shot.ready, "the snapshot of the face on the watch")
            compare(String(shot.source), picker.liveUrl, "taken at the open")
            compare(shipped.opacity, 0, "the shipped picture is not drawn under the snapshot")
            verify(bg !== null && bg.visible, "the wallpaper under the live snapshot")
            verify(picker.backgroundUrl !== "", "the wallpaper was snapshotted at the open")
            compare(String(bg.source), picker.backgroundUrl, "that snapshot")
            near(bg.width, 238 * 1.1, 0.6, "the wallpaper at the preview's scale (110 % of the face)")
            near(bg.height, 238 * 1.1, 0.6, "both ways")
            near(bg.x, (238 - 238 * 1.1) / 2, 0.6, "centred as on the screen")
            near(bg.y, (238 - 238 * 1.1) / 2, 0.6, "centred as on the screen")
            var kids = find(c, "eosFacePreview").children
            var under = -1, over = -1
            for (var k = 0; k < kids.length; k++) {
                if (kids[k].objectName === "eosFacePicture")
                    under = k
                if (kids[k] === shot)
                    over = k
            }
            verify(under >= 0 && over > under, "the wallpaper is drawn under the snapshot")
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-open.png")
            var cy = Math.round(picker.previewCy)
            colourNear(img, 192, 144, "#ffffff", 8, "the face's block")
            colourNear(img, 192 + 121, cy, "#202124", 4, "the 4 px ring")
            colourNear(img, 192 + 127, cy, "#000000", 4, "outside the ring")

            // a face with no snapshot yet: the shipped picture (the face on nothing, as a snapshot) on the same
            // wallpaper, its square corners masked round; one picture
            var c3 = cellOf("r3")
            verify(c3 !== null, "r3 is made (cache buffer)")
            compare(find(c3, "eosFaceShot").ready, false, "no snapshot of r3")
            compare(find(c3, "eosFaceShipped").opacity, 1, "the shipped picture of r3")
            var bg3 = find(c3, "eosFaceBackground")
            verify(bg3.visible, "the wallpaper under a shipped picture")
            compare(String(bg3.source), picker.backgroundUrl, "the wallpaper of the open")
            near(bg3.width, 238 * 1.1, 0.6, "at the preview's scale")
            verify(find(c3, "eosFaceMask").visible, "the corners masked round")
            picker.positionAt("r3")
            wait(100)
            img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-shipped.png")
            colourNear(img, 192 - 112, cy + 20, "#2050a0", 8, "the wallpaper inside the ring of a shipped picture")
            colourNear(img, 192 - 121, cy, "#202124", 4, "its ring")
            colourNear(img, 192 - 112, cy - 112, "#000000", 4, "black at the picture's corner, outside the round")

            // a face with a cached snapshot (transparent, as on the watch): that snapshot on the wallpaper, once
            picker.positionAt("r1")
            wait(100)
            c = cellOf("r1")
            verify(find(c, "eosFaceShot").ready, "the cached snapshot of r1")
            compare(find(c, "eosFaceShipped").opacity, 0, "no shipped picture under it")
            verify(find(c, "eosFaceBackground").visible, "the wallpaper under the cached snapshot")
            img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-cached.png")
            colourNear(img, 192, 144, "#ffffff", 8, "the cached face's block")
            colourNear(img, 130, 230, "#2050a0", 8, "the wallpaper under the cached snapshot")
            colourNear(img, 91, 188, "#e04020", 12, "the wallpaper's mark where the screen has it")
            colourNear(img, 153, 152, "#2050a0", 12, "no digits of the shipped 018 picture (ink there)")
            colourNear(img, 192 + 121, cy, "#202124", 4, "the ring")

            // the face on the watch was saved for the next time when the picker opened
            tryVerify(function () { return facePreviews.exists("r2") }, 10000, "r2 cached")
            // the wallpaper's snapshot goes with the picker
            picker.closeNow()
            compare(picker.backgroundUrl, "", "let go at the close")
        }

        // the repo's fallback pictures (src/watchfaces-preview/182), when the runner stages them next to this
        // file as previews182/ (wo11/run.sh): 016 (redrawn on GL, 10:09, English) is a 75 % black disc with the
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
            var folder = Qt.resolvedUrl("previews182/").toString()
            if (!fileExists(folder + "016-masked-spartan.png"))
                skip("the repo's previews are not staged as previews182/ next to the test")
            setup([["m1", "021-classic"], ["m2", "016-masked-spartan"], ["m3", "008-numerals-duo-synth-neon-green"],
                   ["m4", "009-analog-scientific-v2"]], "m1")
            picker.previewFolder = folder
            openPicker()
            picker.positionAt("m2")
            var c = cellOf("m2")
            tryVerify(function () { return find(c, "eosFaceShipped").ready }, 5000, "016's picture")
            compare(find(c, "eosFaceShot").ready, false, "no snapshot of m2")
            verify(find(c, "eosFaceBackground").visible, "016 on the wallpaper")
            wait(150)
            var img = grabImage(picker)
            img.save("/tmp/wo11-shots/d60-28-016.png")
            // the 182 px picture is drawn 238 px wide from x 73; two points of it: (111, 129) inside a digit,
            // (86, 46) on the disc
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
            // 009: the wallpaper through its dial, at two points of the 182 px picture where it draws nothing
            // ((138, 138) between 4 and 5, (58, 131) between 7 and 8)
            picker.positionAt("m4")
            c = cellOf("m4")
            tryVerify(function () { return find(c, "eosFaceShipped").ready }, 5000, "009's picture")
            compare(find(c, "eosFaceShot").ready, false, "no snapshot of m4")
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
        // list item's preview frame, ManagementView.java:289-380): it leaves what lies outside its ring, such as
        // the delete button of the item, as it is. 009's picture (no background) shows through its dial.
        function test_d60_28_flyer() {
            var folder = Qt.resolvedUrl("previews182/").toString()
            if (!fileExists(folder + "009-analog-scientific-v2.png"))
                skip("the repo's previews are not staged as previews182/ next to the test")
            setup([["f1", "021-classic"], ["f2", "018-modular"], ["f3", "022-large"]], "f1")
            picker.previewFolder = folder
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
            // the picture inside the ring, in its upper left (away from the delete button and the arrows, which
            // the flyer passes under the carousel's row): flying and landed alike
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
            // the delete button outside the ring: not covered by the flyer
            var del = find(c, "eosFaceDelete")
            verify(del.visible && del.opacity === 1, "the item's delete button")
            var dc = del.mapToItem(picker, del.width / 2, del.height / 2)
            var vx = dc.x - 192, vy = dc.y - picker.previewCy, vl = Math.sqrt(vx * vx + vy * vy)
            var ox = Math.round(dc.x + vx / vl * (del.width / 2 - 6)), oy = Math.round(dc.y + vy / vl * (del.width / 2 - 6))
            var outR = Math.sqrt((ox - 192) * (ox - 192) + (oy - picker.previewCy) * (oy - picker.previewCy))
            verify(outR > 119 + 4 + 2, "the point " + ox + "," + oy + " lies outside the ring (" + outR + ")")
            verify(Math.abs(ox - 192) < 119 && Math.abs(oy - picker.previewCy) < 119, "and inside the picture's square")
            var dd = Math.abs(flying.red(ox, oy) - landed.red(ox, oy)) + Math.abs(flying.green(ox, oy) - landed.green(ox, oy))
                     + Math.abs(flying.blue(ox, oy) - landed.blue(ox, oy))
            verify(landed.red(ox, oy) + landed.green(ox, oy) + landed.blue(ox, oy) > 60, "the delete button is drawn there")
            verify(dd <= 12, "the flyer leaves the delete button outside its ring as it is: " + dd)
        }
        // without the wallpaper (no background item): the flyer's picture on black, as the item draws it
        function test_d60_28_flyer_no_wallpaper() {
            var folder = Qt.resolvedUrl("previews182/").toString()
            if (!fileExists(folder + "009-analog-scientific-v2.png"))
                skip("the repo's previews are not staged as previews182/ next to the test")
            setup([["g1", "021-classic"], ["g2", "018-modular"]], "g1")
            picker.background = null
            picker.previewFolder = folder
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

        // ---- D60-32 ----------------------------------------------------------------------------------------
        function test_d60_32_names_fade() {
            setup([["f1", "018-modular"], ["f2", "021-classic"]], "f1")
            var open = find(picker, "eosFaceOpenAnim")
            verify(open !== null, "open animation")
            var hidden = findAnim(open, "eosFaceNamesHidden"), fade = findAnim(open, "eosFaceNamesFade")
            verify(hidden !== null && fade !== null, "names hidden and fade")
            compare(hidden.duration, Motion.duration(166), "names hidden 166 ms")
            compare(fade.duration, Motion.duration(100), "then 100 ms")
            compare(fade.easing.type, Easing.InOutSine, "AccelerateDecelerate: (1 - cos(pi t)) / 2")
            openPicker()
            compare(picker.namesOpacity, 1, "names in")
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
    }
}
