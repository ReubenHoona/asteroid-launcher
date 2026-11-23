// SPDX-License-Identifier: BSD-3-Clause
//
// The face picker (src/qml/misc/FacePicker.qml) and its Add new list (src/qml/misc/FaceAddList.qml) drawn with
// the image's controls on the repo mocks. 384 x 384 px = 192 dp, 1 dp = 2 px. WO-11 of the image 60 defect list:
//
// D60-29: the chip stays in the middle (x 140-244) and the arrows keep their slots (x 68 and 252, 8 px gaps):
// CP3A hides them INVISIBLE (ibk.java:30-31), the row is not centred again. A button that hides waits (chip
// 75 ms, arrows 150 ms: ibj.java) and slides down by the row's height (8 + 13 + 32 + 5 = 58 dp) in 375 ms
// (Slide, Accelerate); one that shows fades in over 450 ms (Fade IN, AccelerateDecelerate) and slides up after
// the wait in 375 ms (Decelerate) (ibk.java:13-27).
// D60-30: CP3A's glyphs: quantum_gm_ic_arrow_left/right_vd_theme_24 (management_ui_root_layout.xml:47,62),
// filled carets in a 24 dp box in primary; pencil_icon.xml (iaf.java:277-283), the outlined pencil 20 x 18 dp
// inset 2 / 3 dp in a 24 dp box, in onPrimary.
// D60-31: the curved face name in onSurface #E8E7EE.
// D60-32: the names hide for 166 ms and fade in over 100 ms on the ValueAnimator default, AccelerateDecelerate
// (= InOutSine) (ManagementView.java:580-587).
//
// Shots go to /tmp/wo11-shots. Run by motion-wt/wo11/run.sh (qmltestrunner under qemu-aarch64 on the image
// rootfs; the picker staged as module LauncherQml at its resource paths).
import QtQuick
import QtQuick.Shapes
import QtTest
import org.asteroid.controls
import LauncherQml

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
            // the show it ran (a Transition makes its animations when it first runs)
            var show = findAnim(right, "eosRowShow")
            verify(show !== null, "the show transition")
            compare(findAnim(show, "eosRowShowWait").duration, Motion.duration(150), "arrow show waits 150 ms")
            var ss = findAnim(show, "eosRowShowSlide")
            compare(ss.duration, Motion.duration(375), "show slide 375 ms")
            compare(ss.easing.type, Easing.OutQuad, "Slide in on DecelerateInterpolator (1 - (1 - t)^2)")
            var sf = findAnim(show, "eosRowShowFade")
            compare(sf.duration, Motion.duration(450), "Fade in 450 ms")
            compare(sf.easing.type, Easing.InOutSine, "Fade on the ValueAnimator default (AccelerateDecelerate)")

            // to the first: the left arrow hides. It stays where it is during the 150 ms wait, then slides down
            // 116 px; it goes transparent only at the end (Fade is MODE_IN only)
            picker.positionAt("w1")
            compare(left.opacity, 1, "not faded at the start")
            near(left.y, aY, 0.5, "not moved at the start (the 150 ms wait)")
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
            compare(findAnim(hide, "eosRowHideWait").duration, Motion.duration(150), "arrow hide waits 150 ms")
            var hs = findAnim(hide, "eosRowHideSlide")
            compare(hs.duration, Motion.duration(375), "hide slide 375 ms")
            compare(hs.easing.type, Easing.InQuad, "Slide out on AccelerateInterpolator (t^2)")

            // Add new: the chip and the right arrow hide in their places; the chip waits 75 ms
            find(picker, "eosFaceList").currentIndex = store.entries.length
            compare(chip.opacity, 1, "the chip is not faded at the start")
            near(chip.y, picker.chipY, 0.5, "nor moved (its 75 ms wait)")
            tryCompare(chip, "opacity", 0, 5000)
            near(chip.x, 140, 1, "chip slot kept on Add new")
            near(chip.y, picker.chipY + 116, 0.5, "chip slid down")
            compare(findAnim(findAnim(chip, "eosRowHide"), "eosRowHideWait").duration, Motion.duration(75),
                    "the chip waits 75 ms")
            tryCompare(right, "opacity", 0, 5000)
            near(right.x, 252, 0.5, "right arrow slot kept on Add new")
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
    }
}
