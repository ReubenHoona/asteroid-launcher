/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "status.js" as Status

/* The face status icon (W2-launcher-status; audit status-indicators-01, -04): the one type
 * StatusSources says (stock "system tray", jpb.java, naf.java). Since N61-17 it is the last slot of
 * the face's bottom row (FaceOverlayRow), as the Wear OS 6 emulator draws it (X-face-charging,
 * X-face-charging-dnd, X-face-airplane): a bare white 18 dp glyph (the eos-status-* files of
 * WO-61-M1, no disc of their own; the charging bolt 20 x 32 px), one at a time. The row places it
 * and brings it in and out; here only a change from one glyph to another: the old one gives way
 * (opacity and scale 1 -> 0) as the new one comes (0 -> 1) in ROW_MS, while the slot is shown and
 * `animated` (the display on, not ambient, animations on); otherwise at once. A slot going away keeps
 * its glyph while the row takes it out. Nothing runs when nothing changes. */
Item {
    id: tray
    objectName: "faceStatusIcon"

    // the slot's content (Status.slotKey of StatusSources)
    property string slotKey: ""
    property bool animated: false
    // the row's slot of this icon is shown (its appear above 0)
    property bool present: false

    // what the slot holds now (the target of a running change)
    readonly property string shownKey: _held
    // the words of the icon (the stock w2_status_* strings), translated
    readonly property var wordsTable: ({
        //% "Watch is warm"
        "thermal": qsTrId("id-status-thermal"),
        //% "Water lock on"
        "wet-water": qsTrId("id-status-water-lock"),
        //% "Touch lock on"
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
    // the replacement, for the tests
    readonly property alias replaceAnim: replace
    readonly property bool animating: replace.running

    // the slot's box: 18 dp square
    width: Theme.dp(Status.ROW_SLOT_DP)
    height: width

    property string _held: ""
    property string _old: ""
    // the replacement's progress
    property real _p: 1

    component Glyph: Image {
        anchors.fill: parent
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        cache: true
    }
    Glyph {
        id: main
        objectName: "statusIcon"
        source: Status.iconSource(tray._held)
        visible: tray._held !== ""
        opacity: tray._p
        scale: tray._p
    }
    Glyph {
        id: cross
        objectName: "statusIconFading"
        source: replace.running ? Status.iconSource(tray._old) : ""
        visible: replace.running
        opacity: 1 - tray._p
        scale: 1 - tray._p
    }

    function settle() {
        var next = slotKey
        // nothing, or the slot goes: the glyph stays while the row takes the slot out
        if (next === "" || next === _held)
            return
        if (Status.transition(_held, next) === "replace" && animated && present) {
            _old = _held
            _held = next
            replace.restart()
            return
        }
        replace.stop()
        _p = 1
        _held = next
    }

    onSlotKeyChanged: settle()
    // the display went off or ambient with a change running: it is over, at once
    onAnimatedChanged: if (!animated) {
        replace.stop()
        _p = 1
    }
    Component.onCompleted: settle()

    NumberAnimation {
        id: replace
        target: tray
        property: "_p"
        from: 0
        to: 1
        duration: Motion.duration(Status.ROW_MS)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Status.ROW_CURVE
    }

    Accessible.role: Accessible.StaticText
    Accessible.name: description
}
