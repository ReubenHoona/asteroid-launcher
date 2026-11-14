/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.asteroid.controls
import "charging.js" as Charging

/* The charging quality screen (W2-launcher-charging; app-inventory-03), stock's
 * ChargingQualityActivity: full screen, not swipe-dismissable, one filled icon of
 * 24 dp above one line. Three states: `misaligned` (a charger: 'Check if charger
 * is aligned and has power'), `moisture` (a water drop: 'Dry watch and charger,
 * wait 1 min for charging to resume') and `unsupported` (a warning: 'Unsupported
 * charger'). The icons are drawn here. Which state shows is the controller's job
 * (ChargingController: only `misaligned` has a source on eos today: a charger is
 * connected, the battery is not full and it has not started charging for 30 s).
 * Nothing animates; touches are swallowed. */
Item {
    id: problem
    objectName: "eosChargerProblem"

    // "", "misaligned", "moisture" or "unsupported"
    property string kind: ""
    readonly property bool shown: kind !== ""

    visible: shown

    // the line, in stock's words
    //% "Check if charger is aligned and has power"
    readonly property string misalignedText: qsTrId("id-charging-problem-misaligned")
    //% "Dry watch and charger, wait 1 min for charging to resume"
    readonly property string moistureText: qsTrId("id-charging-problem-moisture")
    //% "Unsupported charger"
    readonly property string unsupportedText: qsTrId("id-charging-problem-unsupported")
    readonly property string text: kind === "misaligned" ? misalignedText
                                 : kind === "moisture" ? moistureText
                                 : kind === "unsupported" ? unsupportedText : ""

    Accessible.role: Accessible.Pane
    Accessible.name: problem.text

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }
    MouseArea {
        anchors.fill: parent
        enabled: problem.visible
        onPressed: (mouse) => mouse.accepted = true
        onReleased: (mouse) => mouse.accepted = true
    }

    Column {
        id: column
        objectName: "eosChargerProblemColumn"
        anchors.centerIn: parent
        spacing: Theme.space.l
        width: parent.width - 2 * Theme.dp(parent.width / Theme.density * 0.12)

        Item {
            id: glyph
            objectName: "eosChargerProblemIcon"
            width: Theme.dp(Charging.PROBLEM.iconDp)
            height: width
            anchors.horizontalCenter: parent.horizontalCenter

            // a charging pad with the bolt in it
            Shape {
                visible: problem.kind === "misaligned"
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                antialiasing: true
                ShapePath {
                    strokeWidth: -1
                    fillColor: Theme.color.error
                    PathAngleArc { centerX: glyph.width / 2; centerY: glyph.height / 2; radiusX: glyph.width / 2; radiusY: glyph.width / 2; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: -1
                    fillColor: Theme.color.background
                    PathPolyline {
                        path: {
                            var s = glyph.width / 24, out = [], p = Charging.BOLT.points
                            for (var i = 0; i <= p.length; i++)
                                out.push({ x: p[i % p.length][0] * s * 0.8 + glyph.width * 0.1, y: p[i % p.length][1] * s * 0.8 + glyph.height * 0.1 })
                            return out
                        }
                    }
                }
            }
            // a water drop
            Shape {
                visible: problem.kind === "moisture"
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                antialiasing: true
                ShapePath {
                    strokeWidth: -1
                    fillColor: Theme.color.primary
                    startX: glyph.width * 0.5; startY: glyph.height * 0.04
                    PathLine { x: glyph.width * 0.82; y: glyph.height * 0.52 }
                    PathArc {
                        x: glyph.width * 0.18; y: glyph.height * 0.52
                        radiusX: glyph.width * 0.32; radiusY: glyph.width * 0.32
                        direction: PathArc.Clockwise
                        useLargeArc: true
                    }
                    PathLine { x: glyph.width * 0.5; y: glyph.height * 0.04 }
                }
            }
            // a warning triangle with its mark
            Shape {
                visible: problem.kind === "unsupported"
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                antialiasing: true
                ShapePath {
                    strokeWidth: -1
                    fillColor: Theme.color.error
                    startX: glyph.width * 0.5; startY: glyph.height * 0.06
                    PathLine { x: glyph.width * 0.96; y: glyph.height * 0.9 }
                    PathLine { x: glyph.width * 0.04; y: glyph.height * 0.9 }
                    PathLine { x: glyph.width * 0.5; y: glyph.height * 0.06 }
                }
                ShapePath {
                    strokeWidth: glyph.width * 0.1
                    strokeColor: Theme.color.background
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: glyph.width * 0.5; startY: glyph.height * 0.36
                    PathLine { x: glyph.width * 0.5; y: glyph.height * 0.62 }
                }
                ShapePath {
                    strokeWidth: glyph.width * 0.1
                    strokeColor: Theme.color.background
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: glyph.width * 0.5; startY: glyph.height * 0.76
                    PathLine { x: glyph.width * 0.5; y: glyph.height * 0.762 }
                }
            }
        }

        Label {
            objectName: "eosChargerProblemText"
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: problem.text
            color: Theme.color.onSurface
        }
    }
}
