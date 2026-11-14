/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import org.asteroid.utils
import "faceeditor.js" as FE

/*
 * The editor's page dots (face-interaction-28): WearPageIndicatorDrawable with the
 * stock values: 12 px dots (radius 3 dp), the current page at alpha 1.0 and the
 * others at 0.5 (255 and 127). On a round screen they sit on the bottom arc at
 * radius min/2 - 6 dp - dotRadius/2 (177 px at 384 px), a fixed 6.6 degrees per
 * dot (hcy.java: the padding 6 dp is the inset from the edge, not the gap; the
 * centres are about 20.4 px apart). A square screen gets a straight row 12 px
 * apart. ArcPageIndicator has fixed 4 dp gaps and a 0.3 alpha, so the
 * editor draws its own. `position` may be fractional while a finger drags the
 * pages. It fills its parent and is passive.
 */
Item {
    id: dots

    property int count: 0
    property real position: 0

    anchors.fill: parent
    enabled: false
    visible: count > 1

    readonly property real dot: FE.DOT_PX * Theme.dp(1) / 2
    readonly property real gap: FE.DOT_GAP_PX * Theme.dp(1) / 2
    // hcy.java c(): min(w/2, h/2) - padding - dotRadius / 2
    readonly property real radius: Math.min(width, height) / 2 - Theme.dp(FE.DOT_EDGE_DP) - dot / 4
    // the angle between two dots on the arc: fixed, 6.6 degrees
    readonly property real stepAngle: DeviceSpecs.hasRoundScreen && radius > 0 ? FE.DOT_STEP_DEG * Math.PI / 180 : 0

    // the centre of the dot at (fractional) slot p, 0 = first page
    function pointAt(p) {
        var off = (p - (count - 1) / 2) * (dots.LayoutMirroring.enabled ? -1 : 1)
        if (!DeviceSpecs.hasRoundScreen)
            return Qt.point(width / 2 + off * (dot + gap), height - Theme.dp(FE.DOT_EDGE_DP) - dot / 4)
        var a = off * stepAngle
        return Qt.point(width / 2 + radius * Math.sin(a), height / 2 + radius * Math.cos(a))
    }

    Repeater {
        model: dots.count
        delegate: Rectangle {
            objectName: "eosEditorDot"
            readonly property point c: dots.pointAt(index)
            x: c.x - width / 2
            y: c.y - height / 2
            width: dots.dot
            height: width
            radius: width / 2
            color: Theme.color.onBackground
            // the dot of the page on screen is solid; the dot a drag is moving to fills in
            opacity: FE.DOT_OTHER_ALPHA + (FE.DOT_SELECTED_ALPHA - FE.DOT_OTHER_ALPHA)
                     * Math.max(0, 1 - Math.abs(dots.position - index))
        }
    }
}
