/*
 * Copyright (C) 2022 - Timo Könnecke <github.com/eLtMosen>
 *               2022 - Darrel Griët <dgriet@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import org.asteroid.controls
import org.nemomobile.lipstick
import Qt5Compat.GraphicalEffects

/* The hand-over from the boot screen to the watch face (power-boot-warnings-07,
 * -15). The early boot screen (power-boot-warnings-05) shows our logo in an
 * 88 x 90 px box centred at (191, 191) and, under it, a 128 x 24 px pill
 * (#303030, x 128-255, y 324-347 of the 384 px screen) with a #f0f0f0
 * highlight that sweeps through it left to right in 0.8 s (ease-out) and
 * pauses 1.43 s, looping. This continues the same picture until the face is
 * drawn (`ready`), then, as stock's boot animation part3 (13 frames at 60
 * fps): the logo and the pill fade to black linearly over 150 ms (9 frames),
 * black holds 67 ms (4 frames), and the black layer goes (the face shows).
 * The old zoom and its circular cut-out are gone. The sweep runs only while
 * this is up and the display is on. When it is done one journal line records
 * the time of the first usable screen: "eos-boot: first face frame at <s> s"
 * (CLOCK_BOOTTIME), so that boot-to-face can be followed from image to
 * image. */
Item {
    id: splash
    objectName: "bootSplash"
    anchors.fill: parent

    /* the watch face behind is there: hand over */
    property bool ready: false
    property bool displayOn: true
    /* the face is waited for at most this long (ms), as a face that does not load must not keep the screen black */
    property int maxHoldMs: 8000
    /* "show", "fade" (logo and pill to black), "black", "reveal", "gone" */
    property string phase: "show"
    readonly property bool done: phase === "gone"
    // the last line written to the journal
    property string bootLine: ""
    readonly property alias logoLayer: logoLayer
    readonly property alias pill: pill
    readonly property alias blackLayer: background

    visible: phase !== "gone"

    // the timings of stock's part3
    readonly property int fadeMs: 150
    readonly property int blackHoldMs: 67
    readonly property int revealMs: 150

    function handOver() {
        if (phase !== "show")
            return
        phase = "fade"
        sequence.start()
    }
    onReadyChanged: if (ready) handOver()
    Component.onCompleted: {
        if (ready)
            handOver()
        else
            cap.start()
    }
    Timer { id: cap; interval: splash.maxHoldMs; onTriggered: splash.handOver() }

    function bootSeconds() {
        var ms = 0
        if (typeof Lipstick !== "undefined" && Lipstick.compositor && Lipstick.compositor.bootTimeMs)
            ms = Lipstick.compositor.bootTimeMs()
        return (ms / 1000).toFixed(3)
    }

    SequentialAnimation {
        id: sequence
        NumberAnimation { target: logoLayer; property: "opacity"; to: 0; duration: splash.fadeMs; easing.type: Easing.Linear }
        ScriptAction { script: splash.phase = "black" }
        PauseAnimation { duration: splash.blackHoldMs }
        ScriptAction { script: splash.phase = "reveal" }
        NumberAnimation { target: background; property: "opacity"; to: 0; duration: splash.revealMs; easing.type: Easing.Linear }
        ScriptAction {
            script: {
                splash.phase = "gone"
                splash.bootLine = "eos-boot: first face frame at " + splash.bootSeconds() + " s"
                console.info(splash.bootLine)
            }
        }
    }

    Rectangle {
        id: background
        anchors.fill: parent
        color: "black"
        opacity: 1
    }

    // the logo and the pill, one layer to fade
    Item {
        id: logoLayer
        anchors.fill: parent

        Image {
            id: logoSvg
            x: 147
            y: 147
            width: 88
            height: 90
            fillMode: Image.PreserveAspectFit
            source: "qrc:/images/bootlogo.svg"
            sourceSize: Qt.size(88, 90)
        }

        Rectangle {
            id: pill
            objectName: "bootPill"
            x: 128
            y: 324
            width: 128
            height: 24
            radius: 12
            color: "#303030"

            Rectangle {
                id: pillMask
                visible: false
                width: pill.width
                height: pill.height
                radius: pill.radius
            }

            // the highlight, cut to the pill's round ends
            Item {
                id: sweepHost
                anchors.fill: parent
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: pillMask }
                Rectangle {
                    id: highlight
                    objectName: "bootHighlight"
                    width: 48
                    height: parent.height
                    radius: height / 2
                    color: "#f0f0f0"
                    x: -width
                    SequentialAnimation on x {
                        running: splash.visible && splash.displayOn && splash.phase === "show"
                        loops: Animation.Infinite
                        // left to right in 0.8 s, ease-out, then 1.43 s without it
                        NumberAnimation { from: -48; to: 128; duration: 800; easing.type: Easing.OutQuad }
                        PauseAnimation { duration: 1430 }
                    }
                }
            }
        }
    }
}
