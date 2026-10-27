/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher

// Steps so far today (asteroid-sensorlogd's log) on a ring towards the
// daily goal, as the Wear OS / Fitbit steps tile
TileBase {
    id: tile
    //% "Steps"
    title: qsTrId("id-tile-steps") + localeManager.changesObserver
    accent: "#81c995"
    //% "Health"
    chipText: qsTrId("id-tile-health") + localeManager.changesObserver
    onChipClicked: desktop.launchByName("asteroid-health", null)

    HealthLog {
        id: log
        sensor: "stepCounter"
        buckets: 24
        active: tile.live
    }

    ConfigurationValue {
        id: goal
        key: "/org/asteroidos/ux/steps-goal"
        defaultValue: 10000
    }

    readonly property real progress: goal.value > 0 ? Math.min(1, log.lastValue / goal.value) : 0

    Item {
        id: ring
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        readonly property real stroke: Math.round(tile.height * 0.03)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: "#33ffffff"
                strokeWidth: ring.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.stroke) / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: 270
                }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: tile.accent
                strokeWidth: ring.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2; centerY: ring.height / 2
                    radiusX: (ring.width - ring.stroke) / 2; radiusY: radiusX
                    startAngle: 135; sweepAngle: Math.max(0.5, 270 * tile.progress)
                }
            }
        }

        Column {
            anchors.centerIn: parent
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: log.hasData ? log.lastValue.toLocaleString(Qt.locale(), "f", 0) : "0"
                font.pixelSize: Math.round(tile.height * 0.13)
                font.styleName: "SemiCondensed Medium"
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.7
                font.pixelSize: Math.round(tile.height * 0.05)
                //% "of %1"
                text: qsTrId("id-tile-steps-of").arg(Number(goal.value).toLocaleString(Qt.locale(), "f", 0)) + localeManager.changesObserver
            }
        }
    }
}
