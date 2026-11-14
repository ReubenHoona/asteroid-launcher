/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * A time as the Clock tiles draw it (hoa.java:13-30): the digits at 40 sp
 * (displayLarge, 80 px) weight 500 in tabular figures, and in 12 hour mode
 * the locale's AM/PM after them (before them where the locale writes it
 * first) in labelLarge, on the digits' baseline. parts is
 * TimeFormat.timeParts(): { time, marker, markerFirst }.
 */
Item {
    id: tt

    property var parts: ({ time: "", marker: "", markerFirst: false })
    property color color: Theme.color.onSurface
    property real markerGap: Theme.dp(4)
    readonly property alias timeLabel: timeLabel
    readonly property alias markerLabel: markerLabel
    readonly property bool markerFirst: parts.markerFirst === true && parts.marker !== ""

    implicitWidth: timeLabel.implicitWidth + (markerLabel.visible ? markerGap + markerLabel.implicitWidth : 0)
    implicitHeight: timeLabel.height
    width: implicitWidth
    height: implicitHeight

    Label {
        id: timeLabel
        x: tt.markerFirst ? markerLabel.width + tt.markerGap : 0
        text: tt.parts.time
        role: "displayLarge"
        font.weight: Font.Medium
        font.features: Theme.tabularNumerals
        color: tt.color
        maximumLineCount: 1
        elide: Text.ElideNone
    }
    Label {
        id: markerLabel
        visible: text !== ""
        x: tt.markerFirst ? 0 : timeLabel.implicitWidth + tt.markerGap
        y: timeLabel.y + timeLabel.baselineOffset - baselineOffset
        text: tt.parts.marker
        role: "labelLarge"
        color: tt.color
        elide: Text.ElideNone
    }
}
