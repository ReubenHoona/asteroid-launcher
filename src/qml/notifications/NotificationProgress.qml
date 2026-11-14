/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.lipstick
import org.asteroid.controls

/*
 * The progress bar of a phone's live-update notification, in the open card
 * (stock koi.java:189-260 ProgressBarData; only Android's ProgressStyle gets
 * one, a plain setProgress() bar is not sent by asteroid-btsyncd). The hints:
 * x-asteroid-progress and -progress-max (the value and its maximum),
 * x-asteroid-progress-indeterminate (a bar with no value),
 * x-asteroid-progress-segments ("25:ff0000,75:-": segment lengths and their
 * colours, "-" the theme's). 8 dp spacer above, track 4 dp (8 px) tall with
 * round caps (the shared LinearProgressIndicator's look), segments 4 px apart.
 * Battery: the indeterminate bar moves only while it shows and the display
 * is fully on (not dimmed, not ambient).
 */
Item {
    id: pb

    property QtObject notification
    // the owner's say (not in a collapsed card)
    property bool active: true
    readonly property var hints: notification && notification.hints ? notification.hints : ({})
    readonly property bool indeterminate: hints["x-asteroid-progress-indeterminate"] === true
                                          || String(hints["x-asteroid-progress-indeterminate"]) === "true"
    readonly property real maximum: Math.max(1, Number(hints["x-asteroid-progress-max"] || 100))
    readonly property bool hasValue: hints["x-asteroid-progress"] !== undefined
    readonly property real progress: hasValue ? Math.max(0, Math.min(1, Number(hints["x-asteroid-progress"]) / maximum)) : 0
    readonly property bool wanted: indeterminate || hasValue
    // [{ len, color }] from the segments hint, at most ten, [] for one bar
    readonly property var segments: parse(hints["x-asteroid-progress-segments"])
    readonly property real spacer: Theme.dp(8)
    readonly property real thickness: Theme.dp(4)
    readonly property real segmentGap: Theme.dp(2)
    readonly property bool dim: Lipstick.compositor.displayAmbient || Lipstick.compositor.displayDimmed

    function parse(raw) {
        if (!raw)
            return []
        var out = []
        var parts = String(raw).split(",")
        var total = 0
        for (var i = 0; i < parts.length && out.length < 10; i++) {
            var m = parts[i].match(/^(\d+):([0-9a-fA-F]{6}|-)$/)
            if (!m || Number(m[1]) <= 0)
                return []
            out.push({ len: Number(m[1]), color: m[2] === "-" ? "" : "#" + m[2] })
            total += Number(m[1])
        }
        return total > 0 ? out : []
    }

    // (the size follows the conditions, not `visible`: that is false for the whole card
    // while it is still closed, and the card needs its height to open)
    visible: wanted && active
    height: wanted && active ? spacer + thickness : 0

    // one bar
    LinearProgressIndicator {
        id: bar
        y: pb.spacer
        width: parent.width
        visible: !pb.indeterminate && pb.segments.length === 0
        progress: pb.progress
    }

    // segments: each a track in its length's share, filled up to the progress
    Row {
        id: segRow
        y: pb.spacer
        width: parent.width
        spacing: pb.segmentGap
        visible: !pb.indeterminate && pb.segments.length > 0
        Repeater {
            id: segRepeater
            model: pb.segments.length
            delegate: Item {
                id: seg
                objectName: "progressSegment"
                readonly property var s: pb.segments[index]
                readonly property real total: {
                    var t = 0
                    for (var i = 0; i < pb.segments.length; i++) t += pb.segments[i].len
                    return t
                }
                readonly property real start: {
                    var t = 0
                    for (var i = 0; i < index; i++) t += pb.segments[i].len
                    return t / total
                }
                readonly property real share: s.len / total
                // how much of this segment the progress has filled
                readonly property real fill: Math.max(0, Math.min(1, (pb.progress - start) / share))
                width: (segRow.width - (pb.segments.length - 1) * pb.segmentGap) * share
                height: pb.thickness
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.color.surfaceContainer
                }
                Rectangle {
                    width: seg.fill > 0 ? Math.max(height, parent.width * seg.fill) : 0
                    height: parent.height
                    radius: height / 2
                    visible: seg.fill > 0
                    color: seg.s.color !== "" ? seg.s.color : Theme.color.tertiary
                }
            }
        }
    }

    // no value: a block that runs along the track
    Rectangle {
        id: track
        y: pb.spacer
        width: parent.width
        height: pb.thickness
        radius: height / 2
        visible: pb.indeterminate
        color: Theme.color.surfaceContainer
        clip: true
        Rectangle {
            id: block
            width: parent.width * 0.3
            height: parent.height
            radius: height / 2
            color: Theme.color.tertiary
            x: -width
            SequentialAnimation on x {
                running: pb.indeterminate && pb.visible && !pb.dim
                loops: Animation.Infinite
                NumberAnimation { from: -block.width; to: track.width; duration: 1500; easing.type: Easing.InOutQuad }
            }
        }
    }
}
