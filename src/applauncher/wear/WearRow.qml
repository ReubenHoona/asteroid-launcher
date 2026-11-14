/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "WearEdge.js" as Edge

/*
 * One row of the Wear app list (a Wear M3 Button as stock's launcher draws
 * it, app-launcher-04/-05/-06/-19/-23/-24): a pill 52 dp (104 px) tall, full
 * radius, surfaceContainer; the app's icon 36 dp (72 px) in a circle, 8 dp
 * (16 px) from the pill's start; then 8 dp to the label (labelMedium, 15 sp
 * on an 18 sp line, tracking 0.4 sp, width axis 110, at most 2 lines, one
 * with a status line), 14 dp (28 px) from the end. A press shows the shared
 * ripple, no scale (the Wear M3 button's default indication).
 *
 * An app with an ongoing activity shows its status as a second line in
 * primary (labelSmall): it fades in over 250 ms after 50 ms and the row
 * opens over 200 ms; it fades out over 250 ms and closes over 200 ms after
 * 50 ms (hca.java:238-271 hca.F).
 *
 * The edge transformation is the list's: it sets containerAlpha (the pill)
 * and contentAlpha (icon and labels) from the row's place.
 */
MouseArea {
    id: row

    property string title: ""
    property string iconId: ""
    property color discColor: Theme.color.primary
    /* the secondary line (an ongoing activity), "" for none */
    property string status: ""
    property real containerAlpha: 1
    property real contentAlpha: 1
    /* the first run tutorial presses the row */
    property bool fakePressed: false

    readonly property alias disc: disc
    readonly property alias pill: pill
    readonly property alias titleLabel: label
    readonly property alias statusLabel: statusLabel
    readonly property alias ripple: ripple
    readonly property bool held: _held
    readonly property alias enterAnimation: enterAnim
    readonly property alias leaveAnimation: leaveAnim

    signal activated()
    signal longPressed()

    // 8 dp, 8 dp, 14 dp (irn.java 8, 6, 14, 6 dp with the 2 dp label padding)
    readonly property real startPadding: Theme.dp(8)
    readonly property real iconGap: Theme.dp(8)
    readonly property real endPadding: Theme.dp(14)

    property bool _held: false

    height: Theme.size.button
    pressAndHoldInterval: Edge.LONG_PRESS_MS
    onPressed: _held = false
    onPressAndHold: {
        _held = true
        Haptics.longPress()
        longPressed()
    }
    onClicked: if (!_held) activated()

    Accessible.role: Accessible.Button
    Accessible.name: title

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        color: Theme.color.surfaceContainer
        opacity: row.containerAlpha
    }

    Ripple {
        id: ripple
        radius: pill.radius
        color: Theme.color.onSurface
        pressed: row.pressed || row.fakePressed
        pressX: row.mouseX
        pressY: row.mouseY
        opacity: row.containerAlpha
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: row.contentAlpha

        Rectangle {
            id: disc
            x: row.startPadding
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.dp(36)
            height: width
            radius: width / 2
            color: row.discColor
        }

        Icon {
            anchors.centerIn: disc
            // inside the adaptive icon's safe zone (about 66 % of the disc)
            width: disc.width * 0.66
            height: width
            color: "white"
            name: row.iconId === "" ? "ios-help" : row.iconId
        }

        Column {
            id: texts
            x: disc.x + disc.width + row.iconGap
            width: parent.width - x - row.endPadding
            anchors.verticalCenter: parent.verticalCenter

            Label {
                id: label
                width: parent.width
                text: row.title
                role: "labelMedium"
                color: Theme.color.onSurface
                // the launcher's label is the widest cut of the face (SysUI fcc.ar-aw)
                font.variableAxes: ({ "wdth": 110, "ROND": 100, "opsz": 15 })
                wrapMode: Text.Wrap
                maximumLineCount: row._statusShown ? 1 : 2
                elide: Text.ElideRight
            }

            Item {
                id: statusBox
                width: parent.width
                height: row._expand * statusLabel.implicitHeight
                clip: true
                visible: height > 0.5

                Label {
                    id: statusLabel
                    width: parent.width
                    text: row._statusText
                    role: "labelSmall"
                    color: Theme.color.primary
                    opacity: row._fade
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---- the status line: fade and expand (hca.F) ----
    property string _statusText: ""
    property real _fade: 0
    property real _expand: 0
    readonly property bool _statusShown: status !== ""
    readonly property real _motion: Motion.animationScale

    onStatusChanged: {
        if (status !== "") {
            _statusText = status
            leaveAnim.stop()
            if (_motion === 0) {
                _fade = 1
                _expand = 1
            } else if (_fade < 1 || _expand < 1) {
                enterAnim.restart()
            }
        } else if (_statusText !== "") {
            enterAnim.stop()
            if (_motion === 0) {
                _fade = 0
                _expand = 0
                _statusText = ""
            } else {
                leaveAnim.restart()
            }
        }
    }
    Component.onCompleted: {
        if (status !== "") {
            _statusText = status
            _fade = 1
            _expand = 1
        }
    }

    // in: the text fades 250 ms after 50 ms, the row opens 200 ms
    ParallelAnimation {
        id: enterAnim
        SequentialAnimation {
            PauseAnimation { duration: 50 }
            NumberAnimation { target: row; property: "_fade"; to: 1; duration: 250 }
        }
        NumberAnimation { target: row; property: "_expand"; to: 1; duration: 200 }
    }
    // out: the text fades 250 ms, the row closes 200 ms after 50 ms
    SequentialAnimation {
        id: leaveAnim
        ParallelAnimation {
            NumberAnimation { target: row; property: "_fade"; to: 0; duration: 250 }
            SequentialAnimation {
                PauseAnimation { duration: 50 }
                NumberAnimation { target: row; property: "_expand"; to: 0; duration: 200 }
            }
        }
        ScriptAction { script: if (row.status === "") row._statusText = "" }
    }
}
