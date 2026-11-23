/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * PanelsGrid's trays: the tray's black background stays on the screen while the tray slides
 * over it, so the face dims evenly at TrayRules.backgroundAlpha of how far out the tray is
 * (D60-19; CP3A ihv.java:13-19 from jud.java:189-197 and jul.java:137-142). The grid runs on
 * the repo mocks (org.asteroid.launcher's GestureFilterArea stand-in), staged as LauncherQml
 * with tray.js and pager.js. A white face, so the dimming reads as brightness; trays that draw
 * nothing themselves. Screenshots (384x384) go to /tmp/qs-shots.
 */

import QtQuick
import QtTest
import LauncherQml
import "LauncherQml/tray.js" as TrayRules

Item {
    id: root
    width: 384
    height: 384

    // what MainScreen gives the grid
    property bool displayAmbient: false

    Rectangle { anchors.fill: parent; color: "black" }
    Item {
        id: screen
        anchors.fill: parent
        clip: true
        PanelsGrid {
            id: grid
            width: root.width
            height: root.height
            trayMode: true
        }
    }
    Component { id: faceComponent; Rectangle { color: "white" } }
    Component { id: trayComponent; Item { } }

    TestCase {
        name: "PanelsGridTrays"
        when: windowShown

        property Item qs: null
        property Item ns: null

        function findBy(item, pred) {
            if (!item)
                return null
            if (pred(item))
                return item
            var kids = item.children || []
            for (var i = 0; i < kids.length; i++) {
                var r = findBy(kids[i], pred)
                if (r)
                    return r
            }
            return null
        }
        // the background attachTray() made for a row (by its properties: the old ones had no name)
        function background(row) {
            return findBy(grid, function (o) { return o.tray !== undefined && o.row === row && o.radius !== undefined })
        }
        function near(a, b, tol, msg) { verify(Math.abs(a - b) <= tol, (msg || "") + " " + a + " != " + b) }
        // the tray out by f (the finger's way, as applyTrayDrag sets it); checks follow before the
        // grid's 500 ms hide timer
        function pull(row, f) {
            grid.contentY = TrayRules.sign(row) * f * grid.height
            wait(50)
        }
        function brightness(img, x, y) {
            var p = img.pixel(x, y)
            return (p.r + p.g + p.b) / 3
        }

        function initTestCase() {
            grid.addPanel(0, 0, faceComponent, grid.faceHost)
            qs = grid.addPanel(0, -1, trayComponent)
            grid.attachTray(qs, -1)
            ns = grid.addPanel(0, 1, trayComponent)
            grid.attachTray(ns, 1)
        }

        function test_01_background_stays_on_the_screen() {
            var b = background(-1)
            verify(b !== null, "quick settings' background")
            pull(-1, 0.4)
            compare(grid.topTrayFraction, 0.4)
            verify(qs.visible)
            // the tray is 40 % down: its own box is at -230.4 .. 153.6; the background fills the screen
            near(qs.mapToItem(root, 0, 0).y, -230.4, 0.01, "tray top")
            var p = b.mapToItem(root, 0, 0)
            compare(p.x, 0); compare(p.y, 0)
            compare(b.width, 384); compare(b.height, 384); compare(b.radius, 192)
            verify(b.visible)
            near(b.opacity, 0.6, 1e-6, "alpha at 40 %")
            // the face under it dims evenly: top, middle and bottom within 10 % (stock R07slow)
            var img = grabImage(screen)
            var t = brightness(img, 192, 95), m = brightness(img, 192, 193), lo = brightness(img, 192, 325)
            near(t, 0.4, 0.03, "top"); near(m, 0.4, 0.03, "middle"); near(lo, 0.4, 0.03, "bottom")
            verify(Math.max(t, m, lo) - Math.min(t, m, lo) <= 0.1 * Math.max(t, m, lo), "even: " + [t, m, lo])
            img.save("/tmp/qs-shots/grid-01-qs-40.png")
            // half out and more: opaque, still on the screen
            pull(-1, 0.7)
            compare(b.mapToItem(root, 0, 0).y, 0)
            compare(b.opacity, 1)
            // under 25 % it is not drawn at all
            pull(-1, 0.2)
            compare(b.opacity, 0)
            verify(!b.visible)
            // a sideways move of the content (the tiles pager) does not move it either
            pull(-1, 0.4)
            grid.contentX = 40
            wait(20)
            compare(b.mapToItem(root, 0, 0).x, 0)
            grid.contentX = 0
            pull(-1, 0)
        }

        function test_02_stream_background_too() {
            var b = background(1)
            verify(b !== null, "the stream's background")
            pull(1, 0.4)
            compare(grid.bottomTrayFraction, 0.4)
            var p = b.mapToItem(root, 0, 0)
            compare(p.x, 0); compare(p.y, 0)
            near(b.opacity, 0.6, 1e-6)
            // quick settings' background is not drawn meanwhile
            verify(!background(-1).visible)
            var img = grabImage(screen)
            var t = brightness(img, 192, 60), lo = brightness(img, 192, 325)
            near(t, lo, 0.04, "even")
            pull(1, 0)
        }
    }
}
