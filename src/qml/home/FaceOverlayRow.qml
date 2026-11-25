/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "status.js" as Status

/* The face's bottom row (N61-17): what the Wear OS 6 emulator (BP2A) draws over the watch face, the
 * same awake and always-on (S01, S02, X-face-ongoing-stopwatch(-6s), X-face-ongoing-plus-unread,
 * X-ambient-ongoing-plus-unread, X-face-charging(-dnd), X-face-airplane). One row at 6 o'clock in
 * place of CP3A's three overlays (the status icon at the top, the unread bar, the Live Space pill):
 *   - slots of 18 dp (36 px) along a circle 11.5 dp inside the screen's edge (radius 169 px; one
 *     slot is centred at pixel 191.5, 360.5), 36 px of arc apart, upright; left to right the ongoing
 *     activity's icon (LiveSpace), the unread dot (a 12 px white disc), the status icon
 *     (FaceStatusIcon); only the visible ones count, centred as a group: x 191.5; 174 / 210;
 *     156 / 192 / 228;
 *   - behind them one band: an arc stroke 42 px thick on the same circle (y 340-382 at 6 o'clock),
 *     round caps, n * 36 - 21 px between the cap centres (57, 93, 129 px end to end), black at 70 %;
 *     nothing under it when no slot shows;
 *   - a slot comes and goes with opacity and scale 0 <-> 1, its neighbours slide to their places and
 *     the band follows, in 300 ms FastOutSlowIn; nothing moves while not `interactive` (always-on:
 *     the final look at once).
 * The sensor hub's always-on layout has the row from the AP's grab: the band, the glyphs and the dot
 * are part of its background picture (huboffload.cpp), and StatusSlot.ambientIconsKey and the dot
 * flag rebuild that layout when they change (AmbientController.hubLayoutInputs). The band lies
 * outside every hub-drawn sprite of Concentric (its inner dial reaches radius 138 px, the band
 * starts at 148 px). Owned by StatusSlot. */
Item {
    id: row
    objectName: "faceOverlayRow"
    anchors.fill: parent

    // the screen is on and showing: the row animates; else it is static
    property bool interactive: true
    // the status slot's key (StatusSources.slotKey), the registry's first entry, the unread dot
    property string statusKey: ""
    property var ongoingEntry: ({})
    property bool dotWanted: false

    signal ongoingTapped(string key, string app)
    signal ongoingMenuRequested(string key, string app, string title)

    readonly property bool ongoingWanted: live.wanted
    // a status type without a glyph (safety, LTE) takes no slot
    readonly property bool statusWanted: Status.iconSource(statusKey) !== ""
    readonly property var slots: Status.rowSlots(ongoingWanted, dotWanted, statusWanted)
    readonly property int count: slots.length

    readonly property real slotSize: Theme.dp(Status.ROW_SLOT_DP)
    readonly property real arcRadius: Math.min(width, height) / 2 - Theme.dp(Status.ROW_EDGE_DP)
    readonly property real bandWidth: Theme.dp(Status.ROW_BAND_DP)
    readonly property bool animated: interactive && Motion.animationScale > 0
    readonly property bool animating: slotOngoing.moving || slotDot.moving || slotStatus.moving || bandShape.moving

    readonly property alias statusIcon: statusIconItem
    readonly property alias liveSpace: live
    readonly property alias dot: dotItem
    readonly property alias band: bandShape
    readonly property alias ongoingSlot: slotOngoing
    readonly property alias dotSlot: slotDot
    readonly property alias statusIconSlot: slotStatus

    // One slot: its angle from 6 o'clock on the row's circle, how far it is shown (opacity and scale)
    component RowSlot: Item {
        id: s
        property string kind
        // set by the row (layout()), never bound
        property real angle: 0
        property real appear: 0
        property real arcRadius: 0
        property real slotSize: 0
        readonly property var centre: Status.rowPoint(angle, parent ? parent.width / 2 : 0,
                                                      parent ? parent.height / 2 : 0, arcRadius)
        readonly property bool moving: slide.running || fade.running
        width: slotSize
        height: slotSize
        x: centre.x - width / 2
        y: centre.y - height / 2
        opacity: appear
        scale: appear
        visible: appear > 0

        // anim: the row's `animated` now (a binding here could still hold the old value)
        function show(target, anim) {
            if (!anim) {
                slide.stop(); fade.stop()
                angle = target
                appear = 1
                return
            }
            if (appear === 0 && !fade.running) {
                // a new slot comes in at its place; only the others slide
                slide.stop()
                angle = target
            } else if (angle !== target) {
                slide.to = target
                slide.restart()
            }
            if (appear < 1 || fade.running) {
                fade.to = 1
                fade.restart()
            }
        }
        function hide(anim) {
            if (!anim) {
                slide.stop(); fade.stop()
                appear = 0
                return
            }
            // it goes where it is
            if (appear > 0) {
                fade.to = 0
                fade.restart()
            }
        }
        NumberAnimation {
            id: slide
            target: s
            property: "angle"
            duration: Motion.duration(Status.ROW_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.ROW_CURVE
        }
        NumberAnimation {
            id: fade
            target: s
            property: "appear"
            duration: Motion.duration(Status.ROW_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.ROW_CURVE
        }
    }

    function layout() {
        // (slots itself: `count` may not have followed it yet in this handler)
        var n = slots.length
        var all = [slotOngoing, slotDot, slotStatus]
        for (var k = 0; k < all.length; k++) {
            var i = slots.indexOf(all[k].kind)
            if (i >= 0)
                all[k].show(Status.rowAngle(i, n, slotSize, arcRadius), animated)
            else
                all[k].hide(animated)
        }
        bandShape.follow(n)
    }
    onSlotsChanged: layout()
    onArcRadiusChanged: layout()
    onSlotSizeChanged: layout()
    // the display went off or ambient with a change running: the final look, at once
    onAnimatedChanged: if (!animated) layout()
    Component.onCompleted: layout()

    // ---- the band ----
    Shape {
        id: bandShape
        objectName: "faceRowBand"
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // its sweep (degrees) and how far it is shown; set by follow(), never bound
        property real sweep: 0
        property real fade: 0
        readonly property bool moving: sweepAnim.running || fadeAnim.running
        opacity: Status.ROW_BAND_OPACITY * fade
        visible: fade > 0

        function follow(n) {
            var to = Status.bandSweepDeg(n, row.slotSize, row.bandWidth, row.arcRadius)
            if (!row.animated) {
                sweepAnim.stop(); fadeAnim.stop()
                if (n > 0)
                    sweep = to
                fade = n > 0 ? 1 : 0
                return
            }
            if (n > 0) {
                if (fade === 0 && !fadeAnim.running) {
                    // the first slot: the band comes in at its length
                    sweepAnim.stop()
                    sweep = to
                } else if (sweep !== to) {
                    sweepAnim.to = to
                    sweepAnim.restart()
                }
                if (fade < 1 || fadeAnim.running) {
                    fadeAnim.to = 1
                    fadeAnim.restart()
                }
            } else if (fade > 0) {
                // the last slot goes: the band goes with it, at its length
                fadeAnim.to = 0
                fadeAnim.restart()
            }
        }

        ShapePath {
            strokeColor: "#000000"
            strokeWidth: row.bandWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: row.width / 2
                centerY: row.height / 2
                radiusX: row.arcRadius
                radiusY: row.arcRadius
                // 90 degrees is 6 o'clock (clockwise from 3 o'clock)
                startAngle: 90 - bandShape.sweep / 2
                sweepAngle: bandShape.sweep
            }
        }
        NumberAnimation {
            id: sweepAnim
            target: bandShape
            property: "sweep"
            duration: Motion.duration(Status.ROW_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.ROW_CURVE
        }
        NumberAnimation {
            id: fadeAnim
            target: bandShape
            property: "fade"
            duration: Motion.duration(Status.ROW_MS)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Status.ROW_CURVE
        }
    }

    // ---- the slots, left to right ----
    RowSlot {
        id: slotOngoing
        objectName: "faceRowOngoing"
        kind: "ongoing"
        arcRadius: row.arcRadius
        slotSize: row.slotSize
        LiveSpace {
            id: live
            anchors.fill: parent
            entry: row.ongoingEntry
            interactive: row.interactive
            present: slotOngoing.appear > 0
            onTapped: function (key, app) { row.ongoingTapped(key, app) }
            onMenuRequested: function (key, app, title) { row.ongoingMenuRequested(key, app, title) }
        }
    }
    RowSlot {
        id: slotDot
        objectName: "faceRowDot"
        kind: "dot"
        arcRadius: row.arcRadius
        slotSize: row.slotSize
        Rectangle {
            id: dotItem
            objectName: "unreadDot"
            anchors.centerIn: parent
            width: Theme.dp(Status.ROW_DOT_DP)
            height: width
            radius: width / 2
            color: "#ffffff"
            antialiasing: true
        }
    }
    RowSlot {
        id: slotStatus
        objectName: "faceRowStatus"
        kind: "status"
        arcRadius: row.arcRadius
        slotSize: row.slotSize
        FaceStatusIcon {
            id: statusIconItem
            anchors.fill: parent
            slotKey: row.statusKey
            animated: row.animated
            present: slotStatus.appear > 0
        }
    }
}
