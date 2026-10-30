/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import Nemo.Configuration
import org.asteroid.controls

/*
 * One complication on a watch face, drawn by the launcher in the face's
 * slot (ComplicationSources.attach). A face declares a slot as
 *
 *     Item {
 *         objectName: "eosComplication"
 *         property string slotId: "bottom"       // unique in the face
 *         property string shape: "circle"        // circle | text | long
 *         property string defaultSource: "steps" // see ComplicationSources.all
 *         property color tint: "white"           // the face's colour
 *         property string fontFamily: "Roboto"
 *         x: ...; y: ...; width: ...; height: ...
 *     }
 *
 * and nothing else: without the launcher (a preview elsewhere) the slot
 * stays empty. The shapes are the stock ones: "circle" a small round
 * complication (icon over a short value, a ring for a value towards a
 * goal: steps, battery), "text" one line (icon and short value), "long"
 * two lines (the next event's time over its title).
 *
 * In always-on only the date shows, as on the faces: the sensor hub keeps
 * the always-on picture until midnight, so a value that changes before
 * then (steps, heart rate, battery...) is not drawn there; nor on the
 * nightstand face.
 */
Item {
    id: view
    objectName: "eosComplicationView"

    property Item slotItem
    property string faceName
    property QtObject sources

    anchors.fill: parent

    ConfigurationValue {
        id: config
        key: view.sources.configKey(view.faceName)
        defaultValue: []
    }
    readonly property string source: slotItem ? sources.sourceOf(config.value, slotItem.slotId, slotItem.defaultSource || "empty")
                                              : "empty"
    onSourceChanged: sources.register(view)
    Component.onCompleted: sources.register(view)
    Component.onDestruction: sources.unregister(view)

    readonly property var info: sources.info(source)
    readonly property string shape: slotItem && slotItem.shape ? slotItem.shape : "circle"
    readonly property color tint: slotItem && slotItem.tint !== undefined ? slotItem.tint : "white"
    readonly property string family: slotItem && slotItem.fontFamily ? slotItem.fontFamily : "Noto Sans"
    readonly property bool isDate: source === "date"

    visible: source !== "empty" && source !== "" && !sources.nightstand && (!sources.ambient || isDate)

    MouseArea {
        anchors.fill: parent
        enabled: !view.sources.ambient
        pressAndHoldInterval: 500
        onClicked: {
            Haptics.click()
            view.sources.open(view.source, view)
        }
        // a long press on a complication is a long press on the face
        onPressAndHold: {
            Haptics.longPress()
            if (typeof desktop !== "undefined" && desktop.openFacePicker)
                desktop.openFacePicker()
        }
    }

    // ---- circle: a ring (towards a goal) round an icon over the value ----
    Item {
        id: circle
        visible: view.shape === "circle"
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        readonly property real stroke: Math.max(2, Math.round(width * 0.06))

        Shape {
            anchors.fill: parent
            visible: !view.sources.ambient
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(view.tint.r, view.tint.g, view.tint.b, 0.25)
                strokeWidth: circle.stroke
                PathAngleArc {
                    centerX: circle.width / 2; centerY: circle.height / 2
                    radiusX: (circle.width - circle.stroke) / 2; radiusY: radiusX
                    startAngle: 0; sweepAngle: 360
                }
            }
        }
        Shape {
            anchors.fill: parent
            visible: view.info.progress >= 0 && !view.sources.ambient
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: view.tint
                strokeWidth: circle.stroke
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: circle.width / 2; centerY: circle.height / 2
                    radiusX: (circle.width - circle.stroke) / 2; radiusY: radiusX
                    startAngle: -90; sweepAngle: Math.max(0.5, 360 * Math.max(0, view.info.progress))
                }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 0
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !view.isDate
                name: view.info.icon
                color: view.tint
                width: Math.round(circle.width * 0.3)
                height: width
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: view.isDate
                text: view.sources.now.toLocaleString(Qt.locale(), "ddd").toUpperCase()
                color: view.tint
                renderType: Text.NativeRendering
                font.family: view.family
                font.pixelSize: Math.round(circle.width * 0.2)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                // inside the ring, whatever the text (stock: 7 characters)
                width: Math.min(implicitWidth, circle.width * 0.8)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: view.isDate ? view.sources.now.getDate() : view.info.short
                color: view.tint
                renderType: Text.NativeRendering
                font.family: view.family
                font.weight: Font.Medium
                // a value of five figures still fits inside the ring
                font.pixelSize: Math.round(circle.width * (view.isDate ? 0.32 : view.info.short.length > 5 ? 0.19 : 0.23))
            }
        }
    }

    // ---- text: one line, icon and value ----------------------------------
    Row {
        id: line
        visible: view.shape === "text"
        anchors.centerIn: parent
        spacing: Math.round(parent.height * 0.2)
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: !view.isDate
            name: view.info.icon
            color: view.tint
            width: Math.round(view.height * 0.8)
            height: width
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, view.width - (view.isDate ? 0 : view.height * 1.0))
            elide: Text.ElideRight
            text: view.isDate ? view.sources.now.toLocaleString(Qt.locale(), "ddd d").toUpperCase() : view.info.text
            color: view.tint
            renderType: Text.NativeRendering
            font.family: view.family
            font.weight: Font.Medium
            font.pixelSize: Math.round(view.height * 0.72)
        }
    }

    // ---- long: two lines (the next event's time over its title) ----------
    Column {
        visible: view.shape === "long"
        anchors.centerIn: parent
        width: parent.width
        spacing: 0
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(view.height * 0.08)
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: !view.isDate
                name: view.info.icon
                color: view.tint
                width: Math.round(view.height * 0.36)
                height: width
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: view.source === "nextevent" ? view.info.title
                                                  : view.isDate ? view.info.title : view.info.title
                color: view.tint
                opacity: 0.75
                renderType: Text.NativeRendering
                font.family: view.family
                font.pixelSize: Math.round(view.height * 0.3)
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: view.source === "nextevent" ? (view.info.long || "") : view.isDate ? view.sources.now.toLocaleString(Qt.locale(), "d MMMM") : view.info.text
            visible: text !== ""
            color: view.tint
            renderType: Text.NativeRendering
            font.family: view.family
            font.weight: Font.Medium
            font.pixelSize: Math.round(view.height * 0.4)
        }
    }
}
