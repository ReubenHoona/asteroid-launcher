/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import Qt5Compat.GraphicalEffects
import Nemo.Configuration
import org.asteroid.controls
import "complications.js" as C

/*
 * One complication on a watch face, drawn by the launcher in the face's
 * slot (ComplicationSources.attach). A face declares a slot as
 *
 *     Item {
 *         objectName: "eosComplication"
 *         property string slotId: "bottom"       // unique in the face
 *         property string shape: "bulb"          // bulb | circle | text | long | arc
 *         property string defaultSource: "steps" // see ComplicationSources.all
 *         property color tint: "white"           // the face's colour
 *         property string fontFamily: "Roboto"
 *         x: ...; y: ...; width: ...; height: ...
 *     }
 *
 * and nothing else: without the launcher (a preview elsewhere) the slot
 * stays empty. The shapes are the stock ones (the rwf watch face
 * renderers; the numbers are in complications.js):
 *  - "bulb": the round slot of the Wear OS faces, 86 px: a ring (track in
 *    the tint at alpha 30/255, the value as a progress arc with round caps
 *    and an end dot) with a 61.3 degree gap at 6 o'clock holding the
 *    24 px icon, the value in white in the middle (28/22/18/16/14 px by
 *    length), or an icon alone on a disc, or a small image in the circle;
 *    sizes scale with the slot (diameter / 86);
 *  - "circle": the older small round complication of the launcher's own
 *    faces (icon over a short value, a thin ring for a goal);
 *  - "text": one line, 28 px high: icon and value, or the weekday in the
 *    tint and the date in white (touch area 48 px wider each side and
 *    10 px higher each side);
 *  - "long": 280 x 100 px: icon, then two lines of 26 px (accent title,
 *    white text) 33.3 px apart;
 *  - "arc": on the rim, from the slot's arcStart over arcSweep (degrees,
 *    clockwise from 3 o'clock; the slot is the whole face): a ring segment
 *    of radius 170 px and 12 px stroke for a ranged value, the text along
 *    the arc.
 *
 * In always-on every complication shows (ambient-aod-11; the nightstand
 * face has none): the value and icon in the face's dimmed look, the ring's
 * track only, no progress, no touch. Where the sensor hub draws the always-on
 * face, what would go stale there shows '--' (ComplicationSources.info).
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
    // the first part of a line's text that the tint colours (the weekday), and the rest
    readonly property string rest: info.lead !== "" && info.text.indexOf(info.lead) === 0 ? info.text.slice(info.lead.length + 1)
                                                                                            : info.text

    visible: source !== "empty" && source !== "" && !sources.nightstand && (!sources.ambient || info.ambient)

    // a line slot has a larger touch area than it shows (24 dp, 5 dp)
    MouseArea {
        objectName: "eosTouch"
        anchors.fill: parent
        anchors.leftMargin: view.shape === "text" ? -C.LINE.marginX : 0
        anchors.rightMargin: view.shape === "text" ? -C.LINE.marginX : 0
        anchors.topMargin: view.shape === "text" ? -C.LINE.marginY : 0
        anchors.bottomMargin: view.shape === "text" ? -C.LINE.marginY : 0
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

    // ---- bulb: the stock round slot ----------------------------------------
    Item {
        id: bulb
        objectName: "eosBulb"
        visible: view.shape === "bulb"
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width

        // one stock px
        readonly property real u: width / C.BULB
        readonly property string type: view.info.type
        readonly property bool iconOnly: type === "icon"
        readonly property bool imageOnly: type === "smallimage"
        readonly property bool ring: !iconOnly && !imageOnly
        // the icon sits in a gap at 6 o'clock, unless it is the date's (above the text)
        readonly property bool hasGap: ring && view.info.icon !== "" && !view.info.iconTop
        readonly property real strokeW: C.RING_STROKE * u
        readonly property real radius: (width - strokeW) / 2
        readonly property real start: C.ringStart(hasGap)
        readonly property real sweep: C.ringSweep(hasGap)
        readonly property real progress: view.info.progress
        readonly property bool ranged: ring && type !== "weighted" && progress >= 0
        readonly property color accent: view.info.color !== "" ? view.info.color : view.tint
        readonly property real endAngle: C.progressEnd(hasGap, progress)
        readonly property real valueSize: C.valueSize(view.info.short.length) * u

        // the track: the colour at alpha 30/255
        Shape {
            objectName: "eosTrack"
            anchors.fill: parent
            visible: bulb.ring
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(bulb.accent.r, bulb.accent.g, bulb.accent.b, C.DISC_ALPHA)
                strokeWidth: bulb.strokeW
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: bulb.width / 2; centerY: bulb.height / 2
                    radiusX: bulb.radius; radiusY: bulb.radius
                    startAngle: bulb.start; sweepAngle: bulb.sweep
                }
            }
        }
        // the progress, from the gap's edge, round caps
        Shape {
            objectName: "eosProgress"
            anchors.fill: parent
            visible: bulb.ranged && bulb.progress > 0 && !view.sources.ambient
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: bulb.accent
                strokeWidth: bulb.strokeW
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: bulb.width / 2; centerY: bulb.height / 2
                    radiusX: bulb.radius; radiusY: bulb.radius
                    startAngle: bulb.start; sweepAngle: Math.max(0.5, bulb.sweep * Math.min(1, bulb.progress))
                }
            }
        }
        // the segments of a weighted element ring, 2 px apart
        readonly property var elements: view.info.elements || []
        readonly property real elementsTotal: {
            var t = 0
            for (var i = 0; i < elements.length; i++)
                t += elements[i].weight
            return t
        }
        readonly property real gapDegrees: 2 * u / radius * 180 / Math.PI
        function segmentStart(i) {
            var c = 0
            for (var k = 0; k < i; k++)
                c += elements[k].weight
            return start + sweep * c / elementsTotal + gapDegrees / 2
        }
        function segmentSweep(i) {
            return Math.max(0.5, sweep * elements[i].weight / elementsTotal - gapDegrees)
        }
        Repeater {
            model: bulb.type === "weighted" && bulb.elementsTotal > 0 && !view.sources.ambient ? bulb.elements.length : 0
            delegate: Shape {
                objectName: "eosSegment"
                anchors.fill: bulb
                preferredRendererType: Shape.CurveRenderer
                readonly property real startAngle: bulb.segmentStart(index)
                readonly property real sweepAngle: bulb.segmentSweep(index)
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: bulb.elements[index].color
                    strokeWidth: bulb.strokeW
                    capStyle: ShapePath.FlatCap
                    PathAngleArc {
                        centerX: bulb.width / 2; centerY: bulb.height / 2
                        radiusX: bulb.radius; radiusY: bulb.radius
                        startAngle: bulb.segmentStart(index); sweepAngle: bulb.segmentSweep(index)
                    }
                }
            }
        }
        // the end dot: white, 4 px black outline, at the progress end (not at 0)
        Rectangle {
            objectName: "eosDot"
            visible: bulb.ranged && bulb.progress > 0 && !view.sources.ambient
            width: C.DOT * bulb.u
            height: width
            radius: width / 2
            color: "white"
            border.width: C.DOT_STROKE * bulb.u
            border.color: "black"
            x: bulb.width / 2 + bulb.radius * Math.cos(bulb.endAngle * Math.PI / 180) - width / 2
            y: bulb.height / 2 + bulb.radius * Math.sin(bulb.endAngle * Math.PI / 180) - height / 2
        }

        // an icon alone: a disc in the colour at alpha 30/255, the icon in the middle
        Rectangle {
            objectName: "eosDisc"
            visible: bulb.iconOnly && !view.sources.ambient
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(bulb.accent.r, bulb.accent.g, bulb.accent.b, C.DISC_ALPHA)
        }
        Icon {
            objectName: "eosDiscIcon"
            visible: bulb.iconOnly
            anchors.centerIn: parent
            width: C.DISC_ICON * bulb.u
            height: width
            name: view.info.icon
            color: view.tint
        }

        // a small image, clipped to the circle (the software renderer draws no shader: square there)
        Item {
            id: frame
            objectName: "eosImage"
            visible: bulb.imageOnly && view.info.image !== ""
            anchors.fill: parent
            layer.enabled: visible && frame.GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: OpacityMask {
                maskSource: Rectangle { width: frame.width; height: frame.height; radius: width / 2 }
            }
            Image {
                anchors.fill: parent
                source: view.info.image
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: width
                sourceSize.height: height
                asynchronous: true
            }
        }

        // the icon in the ring's gap, at 74/86 of the height
        Icon {
            objectName: "eosGapIcon"
            visible: bulb.hasGap
            width: C.RING_ICON * bulb.u
            height: width
            x: (bulb.width - width) / 2
            y: C.RING_ICON_Y * bulb.u - height / 2
            name: view.info.icon
            color: view.tint
        }
        // the date's calendar icon, the month and the day under it; else the value alone
        Column {
            objectName: "eosStack"
            visible: bulb.ring
            anchors.centerIn: parent
            spacing: 0
            Icon {
                objectName: "eosTopIcon"
                visible: view.info.iconTop
                anchors.horizontalCenter: parent.horizontalCenter
                width: C.DATE_ICON * bulb.u
                height: visible ? width : 0
                name: view.info.icon
                color: view.tint
            }
            Text {
                objectName: "eosCaption"
                visible: view.info.caption !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                width: C.TEXT_WIDTH * bulb.u
                height: visible ? Math.round(C.TITLE_SIZE * bulb.u * 0.92) : 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8 * bulb.u
                text: view.info.caption
                color: "white"
                renderType: Text.NativeRendering
                font.family: view.family
                font.pixelSize: Math.round(C.TITLE_SIZE * bulb.u)
            }
            Text {
                objectName: "eosValue"
                anchors.horizontalCenter: parent.horizontalCenter
                // the box is 40 units wide: a long value shrinks to fit
                width: C.TEXT_WIDTH * bulb.u
                height: Math.round(bulb.valueSize)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8 * bulb.u
                text: view.info.short
                color: "white"
                renderType: Text.NativeRendering
                font.family: view.family
                font.weight: Font.Medium
                font.pixelSize: Math.round(bulb.valueSize)
            }
        }
    }

    // ---- circle: the older round slot: a thin ring (towards a goal) round an icon over the value ----
    Item {
        id: circle
        visible: view.shape === "circle"
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        readonly property real stroke: Math.max(2, Math.round(width * 0.06))

        Shape {
            anchors.fill: parent
            visible: true
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
                visible: !view.isDate && view.info.icon !== ""
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

    // ---- text: one line, icon and value; the date as the weekday in the tint and the day in white ----
    Row {
        id: line
        objectName: "eosLine"
        visible: view.shape === "text"
        anchors.centerIn: parent
        readonly property real size: Math.round(view.height * C.LINE.fontRatio)
        spacing: Math.round(view.height * 0.2)
        Icon {
            objectName: "eosLineIcon"
            anchors.verticalCenter: parent.verticalCenter
            visible: view.info.lead === "" && view.info.icon !== ""
            name: view.info.icon
            color: view.tint
            width: Math.round(view.height * 0.8)
            height: width
        }
        Text {
            objectName: "eosLead"
            anchors.verticalCenter: parent.verticalCenter
            visible: view.info.lead !== ""
            text: view.info.lead
            color: view.tint
            renderType: Text.NativeRendering
            font.family: view.family
            font.weight: Font.Medium
            font.pixelSize: line.size
        }
        Text {
            objectName: "eosLineText"
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, view.width - (view.info.lead === "" ? view.height * 1.0 : 0))
            elide: Text.ElideRight
            text: view.info.lead !== "" ? view.rest : view.info.text
            color: view.info.lead !== "" ? "white" : view.tint
            renderType: Text.NativeRendering
            font.family: view.family
            font.weight: Font.Medium
            font.pixelSize: line.size
        }
    }

    // ---- long: icon, then the accent title over the white text, left aligned, two lines ----
    Item {
        id: longSlot
        objectName: "eosLong"
        visible: view.shape === "long"
        anchors.centerIn: parent
        // 280 x 100 px, scaled down when the slot is smaller
        readonly property real u: Math.min(view.width / C.LONG.width, view.height / C.LONG.height)
        width: C.LONG.width * u
        height: C.LONG.height * u
        readonly property bool hasIcon: view.info.icon !== ""
        readonly property real textX: hasIcon ? (C.LONG.icon + C.LONG.gap) * u : 0
        Icon {
            objectName: "eosLongIcon"
            visible: longSlot.hasIcon
            x: 0
            y: (parent.height - height) / 2
            width: C.LONG.icon * longSlot.u
            height: width
            name: view.info.icon
            color: view.tint
        }
        Column {
            objectName: "eosLongText"
            x: longSlot.textX
            y: (parent.height - height) / 2
            width: longSlot.width - longSlot.textX
            spacing: 0
            Text {
                objectName: "eosLongTitle"
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                maximumLineCount: 1
                lineHeightMode: Text.FixedHeight
                lineHeight: C.LONG.line * longSlot.u
                text: view.info.title
                color: view.tint
                renderType: Text.NativeRendering
                font.family: view.family
                font.pixelSize: Math.round(C.LONG.text * longSlot.u)
            }
            Text {
                objectName: "eosLongBody"
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                maximumLineCount: 1
                lineHeightMode: Text.FixedHeight
                lineHeight: C.LONG.line * longSlot.u
                text: view.info.long !== "" ? view.info.long : view.info.text
                color: "white"
                renderType: Text.NativeRendering
                font.family: view.family
                font.weight: Font.Medium
                font.pixelSize: Math.round(C.LONG.text * longSlot.u)
            }
        }
    }

    // ---- arc: on the rim, from the slot's arcStart over arcSweep (the slot is the whole face) ----
    Item {
        id: rim
        objectName: "eosArc"
        visible: view.shape === "arc"
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        // a 384 px face
        readonly property real k: width / 384
        readonly property real arcStart: view.slotItem && view.slotItem.arcStart !== undefined ? view.slotItem.arcStart : 20
        readonly property real arcSweep: view.slotItem && view.slotItem.arcSweep !== undefined ? view.slotItem.arcSweep : 50
        readonly property real progress: view.info.progress
        readonly property bool ranged: progress >= 0
        readonly property real strokeW: C.ARC.stroke * k
        readonly property real ringRadius: C.ARC.radius * k
        readonly property color accent: view.info.color !== "" ? view.info.color : view.tint
        // the text sits outside the ring's inside edge when there is a ring, else 3 px from the screen edge
        readonly property real textSize: C.ARC.text * k
        readonly property real textRadius: ranged ? ringRadius - strokeW / 2 - 4 * k - textSize / 2
                                                  : width / 2 - C.ARC.edge * k - textSize / 2
        readonly property real mid: arcStart + arcSweep / 2
        // the bottom half reads from the left (anticlockwise), the top half clockwise
        readonly property bool lowerHalf: Math.sin(mid * Math.PI / 180) > 0
        readonly property string label: view.info.short !== "" ? view.info.short : view.info.text

        FontMetrics {
            id: metrics
            font.family: view.family
            font.weight: Font.Medium
            font.pixelSize: Math.round(rim.textSize)
        }
        readonly property var chars: label.split("")
        readonly property var advances: {
            var a = []
            for (var i = 0; i < chars.length; i++)
                a.push(metrics.advanceWidth(chars[i]))
            return a
        }
        readonly property real length: {
            var t = 0
            for (var i = 0; i < advances.length; i++)
                t += advances[i]
            return t
        }
        // the angle the text spans, degrees
        readonly property real textSweep: textRadius > 0 ? length / textRadius * 180 / Math.PI : 0
        function along(i) {
            var x = -length / 2
            for (var k2 = 0; k2 < i; k2++)
                x += advances[k2]
            return x + advances[i] / 2
        }

        Shape {
            objectName: "eosArcTrack"
            anchors.fill: parent
            visible: rim.ranged
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(rim.accent.r, rim.accent.g, rim.accent.b, C.DISC_ALPHA)
                strokeWidth: rim.strokeW
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rim.width / 2; centerY: rim.height / 2
                    radiusX: rim.ringRadius; radiusY: rim.ringRadius
                    startAngle: rim.arcStart; sweepAngle: rim.arcSweep
                }
            }
        }
        Shape {
            objectName: "eosArcProgress"
            anchors.fill: parent
            visible: rim.ranged && rim.progress > 0 && !view.sources.ambient
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: rim.accent
                strokeWidth: rim.strokeW
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: rim.width / 2; centerY: rim.height / 2
                    radiusX: rim.ringRadius; radiusY: rim.ringRadius
                    startAngle: rim.arcStart; sweepAngle: Math.max(0.5, rim.arcSweep * Math.min(1, rim.progress))
                }
            }
        }
        // the range dot: a 6 px white disc in a 10 px black one
        Rectangle {
            objectName: "eosArcDot"
            visible: rim.ranged && rim.progress > 0 && !view.sources.ambient
            width: 2 * C.ARC.dotRing * rim.k
            height: width
            radius: width / 2
            color: "black"
            readonly property real angle: (rim.arcStart + rim.arcSweep * Math.min(1, rim.progress)) * Math.PI / 180
            x: rim.width / 2 + rim.ringRadius * Math.cos(angle) - width / 2
            y: rim.height / 2 + rim.ringRadius * Math.sin(angle) - height / 2
            Rectangle {
                anchors.centerIn: parent
                width: 2 * C.ARC.dotRadius * rim.k
                height: width
                radius: width / 2
                color: "white"
            }
        }
        // an icon alone, 24 px, in the middle of the arc
        Icon {
            objectName: "eosArcIcon"
            visible: view.info.type === "icon" && view.info.icon !== ""
            width: C.ARC.icon * rim.k
            height: width
            name: view.info.icon
            color: view.tint
            x: rim.width / 2 + rim.textRadius * Math.cos(rim.mid * Math.PI / 180) - width / 2
            y: rim.height / 2 + rim.textRadius * Math.sin(rim.mid * Math.PI / 180) - height / 2
            rotation: rim.mid + (rim.lowerHalf ? -90 : 90)
        }
        // the text, letter by letter along the arc
        Repeater {
            model: view.info.type === "icon" ? 0 : rim.chars.length
            delegate: Text {
                objectName: "eosArcLetter"
                readonly property real theta: (rim.mid + (rim.lowerHalf ? -1 : 1) * rim.along(index) / rim.textRadius * 180 / Math.PI) * Math.PI / 180
                text: rim.chars[index]
                color: "white"
                renderType: Text.NativeRendering
                font.family: view.family
                font.weight: Font.Medium
                font.pixelSize: Math.round(rim.textSize)
                x: rim.width / 2 + rim.textRadius * Math.cos(theta) - width / 2
                y: rim.height / 2 + rim.textRadius * Math.sin(theta) - height / 2
                rotation: theta * 180 / Math.PI + (rim.lowerHalf ? -90 : 90)
            }
        }
    }
}
