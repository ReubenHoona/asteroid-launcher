/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "system.js" as Sys

/* What a screenshot looks like (system-dialogs-misc-08), as stock's
 * WearScreenshotService / WearScreenshotHelper:
 *  - the display is held on 3000 ms (ScreenshotService asks mce);
 *  - a white flash: alpha 0 -> 0.18 in 150 ms, 0.18 -> 0 in 150 ms, linear;
 *  - the capture (already cut to the round screen by the service) as a
 *    circle with a 6 dp inset and an 8 dp ring #32312F, scaling from 1.0 to
 *    0.4 in 250 ms on path (0.2, 0, 0, 1) about its bottom centre;
 *  - held 1350 ms, then slid down 400 px in 150 ms on path (0.3, 0, 0.8,
 *    0.49); a touch on it starts that exit early;
 *  - a thud 100 ms after the capture and the shutter sound: ngfd's event
 *    "eos_screenshot" (class crown as stock's hardware feedback; its sample
 *    is ours, and it is silent in a silent profile).
 * Driven by `screenshotService.captured(path)` (lipstick ScreenshotService);
 * capture() asks the service for one (the chord of mce, KeyRouter). Nothing
 * runs or draws while it is not up. Instantiated in compositor.qml above
 * everything but the always-on screen. */
Item {
    id: shot
    objectName: "screenshotOverlay"
    anchors.fill: parent

    // the file being shown
    property string source: ""
    readonly property bool running: seq.running || exitAnim.running
    readonly property alias slideTransform: slide
    // "idle", "flash", "shrink", "hold", "exit"
    property string phase: "idle"
    readonly property alias preview: preview
    readonly property alias flash: flash

    visible: running

    function capture() {
        if (typeof screenshotService !== "undefined" && screenshotService)
            screenshotService.capture()
    }

    /* A capture is saved: play the show. */
    function begin(path) {
        seq.stop()
        source = path
        preview.scale = 1
        slide.y = 0
        preview.opacity = 0
        flash.opacity = 0
        phase = "flash"
        seq.start()
    }

    /* A touch on the preview: straight to the exit. */
    function exitNow() {
        if (!running || phase === "exit")
            return
        seq.stop()
        flash.opacity = 0
        preview.opacity = 1
        preview.scale = Sys.SHOT_SCALE_TO
        phase = "exit"
        exitAnim.start()
    }

    Connections {
        target: typeof screenshotService !== "undefined" ? screenshotService : null
        ignoreUnknownSignals: true
        function onCaptured(path) { shot.begin(path) }
    }

    // the thud and the shutter, 100 ms after the capture
    Timer {
        id: feedback
        interval: Sys.SHOT_HAPTIC_DELAY_MS
        onTriggered: Haptics.play("eos_screenshot")
    }

    SequentialAnimation {
        id: seq
        ScriptAction { script: feedback.restart() }
        // the flash
        NumberAnimation { target: flash; property: "opacity"; from: 0; to: Sys.SHOT_FLASH_ALPHA
                          duration: Sys.SHOT_FLASH_RISE_MS; easing.type: Easing.Linear }
        NumberAnimation { target: flash; property: "opacity"; to: 0
                          duration: Sys.SHOT_FLASH_FALL_MS; easing.type: Easing.Linear }
        // the preview shrinks
        ScriptAction { script: { shot.phase = "shrink"; preview.opacity = 1 } }
        NumberAnimation { target: preview; property: "scale"; from: 1; to: Sys.SHOT_SCALE_TO
                          duration: Sys.SHOT_SCALE_MS
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Sys.SHOT_SCALE_EASING }
        ScriptAction { script: shot.phase = "hold" }
        PauseAnimation { duration: Sys.SHOT_HOLD_MS }
        ScriptAction { script: shot.phase = "exit" }
        NumberAnimation { target: slide; property: "y"; to: Sys.SHOT_EXIT_Y
                          duration: Sys.SHOT_EXIT_MS
                          easing.type: Easing.BezierSpline; easing.bezierCurve: Sys.SHOT_EXIT_EASING }
        ScriptAction { script: { preview.opacity = 0; shot.phase = "idle" } }
    }
    NumberAnimation {
        id: exitAnim
        target: slide
        property: "y"
        to: Sys.SHOT_EXIT_Y
        duration: Sys.SHOT_EXIT_MS
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Sys.SHOT_EXIT_EASING
        onFinished: { preview.opacity = 0; shot.phase = "idle" }
    }

    Rectangle {
        id: flash
        objectName: "screenshotFlash"
        anchors.fill: parent
        color: "#ffffff"
        opacity: 0
    }

    // the preview: a circle, inset, with the ring
    Item {
        id: preview
        objectName: "screenshotPreview"
        x: Sys.SHOT_INSET
        y: Sys.SHOT_INSET
        width: parent.width - 2 * Sys.SHOT_INSET
        height: width
        // the pivot is the bottom centre: the preview scales about its own bottom edge
        transformOrigin: Item.Bottom
        transform: Translate { id: slide }
        opacity: 0
        visible: opacity > 0

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
        }
        Image {
            anchors.fill: parent
            source: shot.source !== "" ? "file://" + shot.source : ""
            fillMode: Image.PreserveAspectFit
            cache: false
            asynchronous: false
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Sys.SHOT_RING
            border.color: Sys.SHOT_RING_COLOR
        }
        MouseArea {
            anchors.fill: parent
            onClicked: shot.exitNow()
        }
    }
}
