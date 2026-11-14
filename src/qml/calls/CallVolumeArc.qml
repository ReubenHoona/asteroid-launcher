/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * The call volume arc at the screen edge (calls-09). Stock draws it with
 * the RSBControl slider type (fragment_ongoing_voice_call.xml:155-167,
 * mirrored with scaleX -1, so on the left edge): a 51 degree track
 * centred on the edge (wkm.java: RSBControl g = 51), 6 dp thick, 5 dp from
 * the edge (rsb_stroke, rsb_outside_padding), the track #4DFFFFFF, the
 * level filled from the bottom up in wear_material_pop (#FDE293 in the
 * dialer's call screens: koo.java:268-300). Fades with the scroll bar fade
 * (250 ms: ViewConfiguration.getScrollBarFadeDuration, RSBControl.java:40).
 */
Item {
    id: arc
    objectName: "callVolumeArc"
    anchors.fill: parent

    // 0..1
    property real level: 0
    property bool shown: false
    property color color: "#FDE293"
    property color trackColor: "#4DFFFFFF"
    readonly property real sweep: 51
    readonly property real stroke: Theme.dp(6)
    readonly property real padding: Theme.dp(5)
    // the arc's centre line, from the screen centre
    readonly property real radius: Math.min(width, height) / 2 - padding - stroke / 2
    // centred on 9 o'clock; the level fills from the bottom (154.5 degrees) up
    readonly property real startAngle: 180 - sweep / 2
    readonly property real levelSweep: sweep * Math.max(0, Math.min(1, level))

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuad } }

    ProgressArc {
        id: track
        anchors.fill: parent
        radius: arc.radius
        strokeWidth: arc.stroke
        color: arc.trackColor
        startAngle: arc.startAngle
        sweepAngle: arc.sweep
    }
    ProgressArc {
        id: fill
        anchors.fill: parent
        radius: arc.radius
        strokeWidth: arc.stroke
        color: arc.color
        startAngle: arc.startAngle
        sweepAngle: arc.levelSweep
    }
}
