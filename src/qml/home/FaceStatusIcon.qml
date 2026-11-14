/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "status.js" as Status

/* The face status icon (W2-launcher-status; audit status-indicators-01, -04): one
 * 18 x 18 dp icon at the top centre, 1 dp from the edge, the one type StatusSources
 * says (stock "system tray", assets/system_tray.css, nae.java:24,76-140).
 *   first icon     fades in over 350 ms, cubic-bezier(0, 0, 0, 1);
 *   last icon gone fades out over 150 ms, cubic-bezier(0.3, 0, 1, 1), then display none;
 *   replacement    the old icon (a second image) fades out in 150 ms, the new one fades in
 *                  over 350 ms starting 350 ms after the change.
 * Animated only while `interactive` (the display is on and not ambient, animations on);
 * otherwise the change is at once, at full opacity: the always-on screen has no
 * animation, and a change that comes while the sensor hub draws waits for the next draw
 * anyway. Nothing runs when nothing changes. */
Item {
    id: tray

    // the slot's content (Status.slotKey of StatusSources)
    property string slotKey: ""
    property bool interactive: true

    // what the slot holds now (the target of the running change)
    readonly property string shownKey: _held
    // the words of the icon (the stock w2_status_* strings), translated
    readonly property var wordsTable: ({
        //% "Watch is warm"
        "thermal": qsTrId("id-status-thermal"),
        //% "Water lock on"
        "wet-water": qsTrId("id-status-water-lock"),
        "wet-touch": qsTrId("id-touch-lock-on"),
        //% "Microphone on"
        "mic": qsTrId("id-status-mic"),
        //% "Location on"
        "location": qsTrId("id-status-location"),
        //% "Safety signal is active"
        "safety": qsTrId("id-status-safety"),
        //% "Device is locked"
        "screenLock": qsTrId("id-status-screen-lock"),
        //% "Charging"
        "charging": qsTrId("id-status-charging"),
        //% "Airplane mode on"
        "airplane": qsTrId("id-status-airplane"),
        //% "Bluetooth off"
        "btOff": qsTrId("id-status-bt-off"),
        //% "LTE Disconnected"
        "lteDisconnected": qsTrId("id-status-lte"),
        //% "Disconnected from phone"
        "phoneDisconnected": qsTrId("id-status-phone"),
        //% "Bedtime mode on"
        "bedtime": qsTrId("id-status-bedtime"),
        //% "Theater mode on"
        "theater": qsTrId("id-status-theater"),
        //% "Do Not Disturb Mode on"
        "dnd": qsTrId("id-status-dnd"),
        //% "Power Save mode on"
        "batterySaver": qsTrId("id-status-saver"),
        //% "Battery Low"
        "batteryLow": qsTrId("id-status-battery-low")
    })
    readonly property string description: _held !== "" && wordsTable[_held] !== undefined ? wordsTable[_held] : ""
    readonly property alias mainIcon: main
    readonly property alias crossIcon: cross
    // the animations, for the tests
    readonly property alias fadeInAnim: fadeIn
    readonly property alias fadeOutAnim: fadeOut
    readonly property alias crossOutAnim: crossOut
    readonly property alias replaceInAnim: replaceIn
    readonly property bool animating: fadeIn.running || fadeOut.running || crossOut.running || replaceIn.running
    readonly property bool animated: interactive && Motion.animationScale > 0

    // y 1 dp from the top edge, 18 dp square, centred
    width: Theme.dp(Status.SIZE_DP)
    height: width
    x: parent ? (parent.width - width) / 2 : 0
    y: Theme.dp(Status.TOP_DP)
    // (the images are shown by these two flags: a child is only visible when its parent is)
    property bool _mainOn: false
    property bool _crossOn: false
    visible: _mainOn || _crossOn

    property string _held: ""

    component Glyph: Image {
        anchors.fill: parent
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: true
        visible: false
        opacity: 0
    }
    Glyph { id: main; objectName: "statusIcon"; visible: tray._mainOn }
    Glyph { id: cross; objectName: "statusIconFading"; visible: tray._crossOn }

    function settle() {
        var next = slotKey
        if (next === _held)
            return
        var kind = Status.transition(_held, next)
        var old = _held
        _held = next
        stopAll()
        if (!animated || kind === "none") {
            apply(next)
            return
        }
        switch (kind) {
        case "show":
            main.source = Status.iconSource(next)
            main.opacity = 0
            _mainOn = true
            fadeIn.restart()
            break
        case "hide":
            fadeOut.restart()
            break
        case "replace":
            var oldSource = Status.iconSource(old)
            cross.source = oldSource
            cross.opacity = 1
            _crossOn = oldSource !== ""
            crossOut.restart()
            main.source = Status.iconSource(next)
            main.opacity = 0
            _mainOn = true
            replaceIn.restart()
            break
        }
    }

    // the final look, at once
    function apply(key) {
        main.source = Status.iconSource(key)
        main.opacity = key !== "" ? 1 : 0
        _mainOn = key !== ""
        _crossOn = false
        cross.opacity = 0
    }
    function stopAll() {
        fadeIn.stop(); fadeOut.stop(); crossOut.stop(); replaceIn.stop()
    }

    onSlotKeyChanged: settle()
    // the display went off or ambient with a change running: it is over, at once
    onAnimatedChanged: if (!animated) {
        stopAll()
        apply(_held)
    }
    Component.onCompleted: settle()

    NumberAnimation {
        id: fadeIn
        target: main
        property: "opacity"
        to: 1
        duration: Motion.duration(Status.FADE_IN_MS)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Status.FADE_IN_CURVE
    }
    SequentialAnimation {
        id: fadeOut
        NumberAnimation {
            target: main
            property: "opacity"
            to: 0
            duration: Motion.duration(Status.FADE_OUT_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.FADE_OUT_CURVE
        }
        // then display none
        ScriptAction { script: if (tray._held === "") _mainOn = false }
    }
    SequentialAnimation {
        id: crossOut
        NumberAnimation {
            target: cross
            property: "opacity"
            to: 0
            duration: Motion.duration(Status.FADE_OUT_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.FADE_OUT_CURVE
        }
        ScriptAction { script: _crossOn = false }
    }
    SequentialAnimation {
        id: replaceIn
        PauseAnimation { duration: Motion.duration(Status.REPLACE_DELAY_MS) }
        NumberAnimation {
            target: main
            property: "opacity"
            to: 1
            duration: Motion.duration(Status.FADE_IN_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.FADE_IN_CURVE
        }
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: description
}
