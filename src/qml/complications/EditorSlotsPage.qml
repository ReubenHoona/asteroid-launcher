/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "faceeditor.js" as FE
import "complications.js" as C

/*
 * The complications page of the face editor, as stock's (jcb.java, jbz.java,
 * face-interaction-26): the face at full size (the editor draws it behind) with a
 * highlight round every slot, all in one layer: #999aa0a6 (#9aa0a6 at 60 %)
 * outlines about 4 px thick that follow the slot's shape, the inside faintly
 * white. 500 ms after the page shows the layer pulses, alpha 1.0 -> 0.5 in
 * 300 ms and back, for as long as the page is on screen. Invisible tap targets
 * lie over the slots: a tap opens the chooser for that slot. No title, no hint;
 * an empty slot is announced "Add complication".
 */
Item {
    id: page

    // the face item (full size, at the editor's origin) and its slots (items named eosComplication)
    property Item face: null
    property var slots: []
    // the editor's sources and what each slot shows: sourceOf(slotItem) -> id
    property QtObject sources: null
    property var sourceOf: function (slot) { return "empty" }
    // this page is the one on screen, with the display on
    property bool active: true

    // a slot was tapped
    signal slotTapped(Item slot)

    readonly property real k: face && face.width > 0 ? width / face.width : 1
    // the band of an arc slot, in face px: from the text's inner side to 4 px outside the ring
    readonly property real arcOuter: C.ARC.radius + C.ARC.stroke / 2 + 4
    readonly property real arcInner: C.ARC.radius - C.ARC.stroke / 2 - 4 - C.ARC.text - 4
    readonly property alias highlightLayer: highlights
    readonly property bool pulsing: pulse.running
    readonly property real lowAlpha: FE.PULSE_LOW

    // one layer for every slot's highlight: its opacity is what pulses
    Item {
        id: highlights
        objectName: "eosEditorHighlights"
        anchors.fill: parent

        Repeater {
            model: page.slots
            delegate: Item {
                id: hl
                objectName: "eosEditorHighlight"
                readonly property Item slot: modelData
                readonly property string shape: slot && slot.shape ? String(slot.shape) : "circle"
                readonly property rect r: page.face && slot ? slot.mapToItem(page.face, 0, 0, slot.width, slot.height)
                                                            : Qt.rect(0, 0, 0, 0)
                x: r.x * page.k
                y: r.y * page.k
                width: r.width * page.k
                height: r.height * page.k

                // a bulb, a circle, a text or a long slot: its outline, the inside faintly white
                Rectangle {
                    objectName: "eosEditorSlotOutline"
                    visible: hl.shape !== "arc"
                    anchors.fill: parent
                    radius: hl.shape === "circle" || hl.shape === "bulb" ? Math.min(width, height) / 2 : height / 2
                    color: FE.HIGHLIGHT_FILL
                    border.color: FE.HIGHLIGHT_COLOR
                    border.width: FE.HIGHLIGHT_STROKE_PX * page.width / 384
                    antialiasing: true
                }

                // an arc slot: a band on the rim from arcStart over arcSweep, with its two edges drawn
                Shape {
                    id: arcShape
                    objectName: "eosEditorArcOutline"
                    visible: hl.shape === "arc"
                    anchors.centerIn: parent
                    width: Math.min(hl.width, hl.height)
                    height: width
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real kk: width / 384
                    readonly property real start: hl.slot && hl.slot.arcStart !== undefined ? hl.slot.arcStart : 20
                    readonly property real sweep: hl.slot && hl.slot.arcSweep !== undefined ? hl.slot.arcSweep : 50
                    // the ring and its text: from 4 px outside the ring to the text's inner side
                    readonly property real outer: page.arcOuter * kk
                    readonly property real inner: page.arcInner * kk
                    readonly property real stroke: FE.HIGHLIGHT_STROKE_PX * page.width / 384
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: FE.HIGHLIGHT_FILL
                        strokeWidth: arcShape.outer - arcShape.inner
                        capStyle: ShapePath.FlatCap
                        PathAngleArc {
                            centerX: arcShape.width / 2; centerY: arcShape.height / 2
                            radiusX: (arcShape.outer + arcShape.inner) / 2
                            radiusY: radiusX
                            startAngle: arcShape.start; sweepAngle: arcShape.sweep
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: FE.HIGHLIGHT_COLOR
                        strokeWidth: arcShape.stroke
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: arcShape.width / 2; centerY: arcShape.height / 2
                            radiusX: arcShape.outer; radiusY: radiusX
                            startAngle: arcShape.start; sweepAngle: arcShape.sweep
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: FE.HIGHLIGHT_COLOR
                        strokeWidth: arcShape.stroke
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: arcShape.width / 2; centerY: arcShape.height / 2
                            radiusX: arcShape.inner; radiusY: radiusX
                            startAngle: arcShape.start; sweepAngle: arcShape.sweep
                        }
                    }
                }
            }
        }
    }

    // the pulse: 500 ms after the page shows, 1.0 -> 0.5 and back in 300 ms each way, forever
    SequentialAnimation {
        id: pulse
        objectName: "eosEditorPulse"
        running: page.active && page.slots.length > 0
        onRunningChanged: if (!running) highlights.opacity = 1
        PauseAnimation { duration: Motion.duration(FE.PULSE_DELAY_MS) }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation {
                target: highlights; property: "opacity"; from: 1; to: FE.PULSE_LOW
                duration: Motion.duration(FE.PULSE_MS)
            }
            NumberAnimation {
                target: highlights; property: "opacity"; from: FE.PULSE_LOW; to: 1
                duration: Motion.duration(FE.PULSE_MS)
            }
        }
    }

    // the invisible tap targets (a finger-sized area round a small slot)
    Repeater {
        model: page.slots
        delegate: MouseArea {
            id: tap
            objectName: "eosEditorSlotTap"
            readonly property Item slot: modelData
            readonly property rect r: page.face && slot ? slot.mapToItem(page.face, 0, 0, slot.width, slot.height)
                                                        : Qt.rect(0, 0, 0, 0)
            readonly property string source: page.sourceOf(slot)
            // arc slots span the whole face: the tap goes to the band on the rim
            readonly property bool arc: slot && slot.shape === "arc"
            x: (r.x + r.width / 2) * page.k - width / 2
            y: (r.y + r.height / 2) * page.k - height / 2
            width: Math.max(r.width * page.k, page.width * FE.SLOT_TAP_MIN_FRACTION)
            height: Math.max(r.height * page.k, page.width * FE.SLOT_TAP_MIN_FRACTION)
            enabled: page.active
            // an arc slot is the whole face: only its band takes the tap
            containmentMask: QtObject {
                function contains(p: point): bool {
                    if (!tap.arc)
                        return true
                    return FE.inArc(p.x / page.k - tap.width / page.k / 2, p.y / page.k - tap.height / page.k / 2,
                                    tap.slot.arcStart !== undefined ? tap.slot.arcStart : 20,
                                    tap.slot.arcSweep !== undefined ? tap.slot.arcSweep : 50,
                                    page.arcInner, page.arcOuter)
                }
            }
            Accessible.role: Accessible.Button
            //% "Add complication"
            Accessible.name: source === "empty" ? qsTrId("id-face-add-complication") + localeManager.changesObserver
                                                : (page.sources ? page.sources.name(source) : "")
            onClicked: page.slotTapped(slot)
        }
    }
}
