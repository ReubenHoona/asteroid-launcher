/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick
import org.asteroid.utils
import "../home/ambient.js" as Ambient

/* The burn-in protection of the always-on screen, as stock Wear OS (audit
 * ambient-aod-07; WS display/burninprotection): no system pixel shift, an
 * image mask over the whole screen: a 2x2 tile {{1,0},{0,1}} in black (half of
 * the pixels off), the tile shifted by the minute: phase = minute mod 4
 * (ImageMaskTileFactory.getShiftedX/Y). It starts at the first whole minute
 * after the AP-drawn always-on screen began, so only the minute updates carry
 * it, is not drawn while the sensor hub draws the screen (the hub's own
 * checkerboard, SmartDMA, is its counterpart), is gone with the display on,
 * and the always-on brightness is doubled while it shows
 * (/org/asteroidos/launcher/aod-mask-boost, AodBrightness).
 *
 * Nothing runs on its own: it follows the ambient signals of the compositor,
 * and the two tile pictures are 2x2 px images. Instantiated once in
 * compositor.qml above the always-on screen. */
Item {
    id: mask
    objectName: "eosBurnInMask"

    // the panel needs it (an OLED: DeviceSpecs.needsBurnInProtection)
    property bool supported: DeviceSpecs.needsBurnInProtection
    // the minute the always-on screen began, and the phase of this minute's mask
    property real entryMinute: 0
    property int phase: 0
    // began: the first whole minute after the entry has come
    property bool began: false
    readonly property bool shown: supported && began && Lipstick.compositor.displayAmbient
                                  && !Lipstick.compositor.displayOffloaded
    // which tile picture: 0 black where x + y is even, 1 where it is odd
    readonly property int parity: Ambient.maskParity(phase)

    visible: shown
    enabled: false

    ConfigurationValue {
        id: boost
        key: "/org/asteroidos/launcher/aod-mask-boost"
        defaultValue: false
    }
    // x2 brightness only while the mask shows
    onShownChanged: boost.value = shown
    // a launcher that died with the mask up left the brightness doubled
    Component.onCompleted: if (boost.value === true) boost.value = false

    Image {
        objectName: "eosBurnInTile"
        anchors.fill: parent
        source: "qrc:/images/burnin-mask-" + mask.parity + ".png"
        fillMode: Image.Tile
        smooth: false
        mipmap: false
        cache: true
        horizontalAlignment: Image.AlignLeft
        verticalAlignment: Image.AlignTop
    }

    // the time of the update (a test sets it; 0: the clock)
    property real fakeNow: 0
    function nowMs() { return fakeNow > 0 ? fakeNow : Date.now() }
    function minuteNow() { return Math.floor(nowMs() / 60000) }
    function leave() {
        began = false
        if (boost.value !== false)
            boost.value = false
    }

    Connections {
        target: Lipstick.compositor
        function onDisplayAmbientEntered() {
            mask.entryMinute = mask.minuteNow()
            mask.began = false
        }
        // a minute update drawn by the AP
        function onDisplayAmbientUpdate() {
            if (Ambient.maskStarts(mask.entryMinute, mask.minuteNow())) {
                mask.phase = Ambient.maskPhase(new Date(mask.nowMs()).getMinutes())
                mask.began = true
            }
        }
        // not displayAboutToBeOn: it is also emitted at every AP ambient update
        // (stock BurnInProtector keeps the mask up between the minute updates)
        function onDisplayAmbientLeft() { mask.leave() }
        function onDisplayOn() { mask.leave() }
    }
}
