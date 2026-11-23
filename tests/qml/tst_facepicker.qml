// SPDX-License-Identifier: BSD-3-Clause
//
// The face picker (src/qml/misc/FacePicker.qml) and its Add new list (src/qml/misc/FaceAddList.qml) drawn with
// the image's controls on the repo mocks. 384 x 384 px = 192 dp, 1 dp = 2 px. WO-11 of the image 60 defect list:
//
// D60-31: the curved face name in onSurface #E8E7EE.
//
// Shots go to /tmp/wo11-shots. Run by motion-wt/wo11/run.sh (qmltestrunner under qemu-aarch64 on the image
// rootfs; the picker staged as module LauncherQml at its resource paths).
import QtQuick
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
    }
}
