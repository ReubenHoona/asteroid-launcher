/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

// BurnInMask.qml and the display offload daemon (CR-46 mask): while the burn-in image mask shows on the
// AP-drawn always-on screen, the compositor is asked once for "mask 1" (the daemon doubles the always-on
// levels), and for "mask 0" when it goes (display on, ambient left); never while the hub draws (no mask).
// The dconf key aod-mask-boost is retired: nothing is written. MODE=st (the staged tree).
import QtQuick
import QtTest
import org.nemomobile.lipstick

Item {
    id: top
    width: 384
    height: 384

    // LipstickCompositor's side: the ambient signals and the offload request (recorded)
    QtObject {
        id: fakeComp
        property bool displayAmbient: false
        property bool displayOffloaded: false
        property var masks: []
        signal displayAmbientEntered()
        signal displayAmbientUpdate()
        signal displayAmbientLeft()
        signal displayOn()
        function setOffloadMask(shown) { var m = masks.slice(); m.push(shown); masks = m }
    }

    Loader { id: ml; active: false; anchors.fill: parent; source: Qt.resolvedUrl("st/qml/compositor/BurnInMask.qml") }

    TestCase {
        name: "BurnInMaskOffload"
        when: windowShown

        property var mask: null
        property real minute: 60000

        function initTestCase() {
            Lipstick.compositor = fakeComp
            ml.active = true
            tryCompare(ml, "status", Loader.Ready, 30000)
            mask = ml.item
        }

        // the always-on screen begins at minute m, then the AP updates it at minute m + 1
        function enterAndUpdate(m) {
            mask.fakeNow = m * minute
            fakeComp.displayAmbient = true
            fakeComp.displayAmbientEntered()
            mask.fakeNow = (m + 1) * minute
            fakeComp.displayAmbientUpdate()
        }

        function init() {
            fakeComp.displayOn()
            fakeComp.displayAmbient = false
            fakeComp.displayOffloaded = false
            fakeComp.masks = []
        }

        function test_00_mask_1_while_it_shows_then_mask_0() {
            enterAndUpdate(1000)
            verify(mask.shown)
            compare(fakeComp.masks, [true])
            // the next minute update keeps it: nothing more is sent
            mask.fakeNow = 1002 * minute
            fakeComp.displayAmbientUpdate()
            compare(fakeComp.masks, [true])
            // the display comes on: the mask goes, mask 0
            fakeComp.displayAmbient = false
            fakeComp.displayOn()
            verify(!mask.shown)
            compare(fakeComp.masks, [true, false])
        }

        function test_01_not_before_the_first_whole_minute() {
            mask.fakeNow = 2000 * minute
            fakeComp.displayAmbient = true
            fakeComp.displayAmbientEntered()
            fakeComp.displayAmbientUpdate()          // the same minute: no mask yet
            verify(!mask.shown)
            compare(fakeComp.masks, [])
        }

        function test_02_hub_drawing_has_no_mask() {
            enterAndUpdate(3000)
            compare(fakeComp.masks, [true])
            // the hub takes the display: the mask is not drawn, mask 0
            fakeComp.displayOffloaded = true
            verify(!mask.shown)
            compare(fakeComp.masks, [true, false])
            fakeComp.displayAmbientLeft()
            compare(fakeComp.masks, [true, false])
        }

        function test_03_ambient_left() {
            enterAndUpdate(4000)
            fakeComp.displayAmbient = false
            fakeComp.displayAmbientLeft()
            compare(fakeComp.masks, [true, false])
        }
    }
}
