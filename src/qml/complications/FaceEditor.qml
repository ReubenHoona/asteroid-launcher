/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls

/*
 * The complications page of the face editor, as stock Wear OS's (long
 * press on the face, Customize, swipe to the data page): the face on
 * screen, smaller, with its complication slots outlined; a tap on a slot
 * opens the list of data sources (Empty first, the current one ticked); a
 * tap on one puts it in the slot and comes back here. The face is the live
 * one (a ShaderEffectSource of it), so the choice shows at once.
 */
Item {
    id: editor

    // the face item on screen, its file, the home screen's sources
    property Item face: null
    property string faceUrl: ""
    property QtObject sources: null

    readonly property string faceName: sources ? sources.faceName(faceUrl) : ""
    property var slots: []
    function refresh() { slots = sources && face ? sources.slotsOf(face) : [] }
    onFaceChanged: refresh()
    Component.onCompleted: refresh()

    readonly property real scaleBy: 0.7
    property Item chosenSlot: null
    readonly property bool choosing: chosenSlot !== null

    ConfigurationValue {
        id: config
        key: editor.sources ? editor.sources.configKey(editor.faceName) : ""
        defaultValue: []
    }
    function sourceOf(slot) {
        return slot ? sources.sourceOf(config.value, slot.slotId, slot.defaultSource || "empty") : "empty"
    }
    function choose(source) {
        if (chosenSlot)
            config.value = sources.withSource(config.value, chosenSlot.slotId, source)
        Haptics.confirm()
        chosenSlot = null
    }

    // ---- the face with its slots ------------------------------------------
    Item {
        id: page
        anchors.fill: parent
        visible: !editor.choosing

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(editor.height * 0.035)
            //% "Complications"
            text: qsTrId("id-face-complications") + localeManager.changesObserver
            font.pixelSize: Math.round(editor.height * 0.05)
            font.styleName: "SemiCondensed Medium"
        }

        Item {
            id: preview
            width: Math.round(editor.width * editor.scaleBy)
            height: width
            anchors.centerIn: parent

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#000000"
                border.color: Theme.color.surfaceContainerHigh
                border.width: 2
            }
            ShaderEffectSource {
                anchors.fill: parent
                sourceItem: editor.face
                live: true
                hideSource: false
                smooth: true
                visible: editor.face !== null
            }

            // the slots: an outline each, the source's name on the chosen one
            Repeater {
                model: editor.slots
                delegate: Item {
                    id: slotOutline
                    readonly property Item slot: modelData
                    readonly property rect r: editor.face ? slot.mapToItem(editor.face, 0, 0, slot.width, slot.height) : Qt.rect(0, 0, 0, 0)
                    readonly property real k: preview.width / Math.max(1, editor.face ? editor.face.width : 1)
                    readonly property real pad: Math.round(editor.width * 0.008)
                    x: r.x * k - pad
                    y: r.y * k - pad
                    width: r.width * k + 2 * pad
                    height: r.height * k + 2 * pad

                    Rectangle {
                        anchors.fill: parent
                        radius: slot.shape === "circle" ? width / 2 : height / 2
                        color: area.pressed ? Qt.alpha(Theme.color.primary, 0.25) : "transparent"
                        border.color: Theme.color.primary
                        border.width: Math.max(2, Math.round(editor.width * 0.006))
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: editor.sourceOf(slotOutline.slot) === "empty"
                        name: "ios-add"
                        color: Theme.color.primary
                        width: Math.min(parent.width, parent.height) * 0.6
                        height: width
                    }
                    MouseArea {
                        id: area
                        // a finger-sized target round a small slot
                        anchors.centerIn: parent
                        width: Math.max(parent.width, editor.width * 0.16)
                        height: Math.max(parent.height, editor.width * 0.16)
                        onClicked: {
                            list.positionViewAtBeginning()
                            editor.chosenSlot = slotOutline.slot
                        }
                    }
                }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(editor.height * 0.06)
            width: Math.round(editor.width * 0.6)
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
            visible: editor.slots.length > 0
            //% "Tap to change"
            text: qsTrId("id-face-tap-to-change") + localeManager.changesObserver
            font.pixelSize: Math.round(editor.height * 0.045)
        }
    }

    // ---- the data sources of a slot ---------------------------------------
    Item {
        id: chooser
        anchors.fill: parent
        visible: editor.choosing

        Rectangle { anchors.fill: parent; color: "#000000" }
        MouseArea { anchors.fill: parent }

        ListView {
            id: list
            anchors.fill: parent
            readonly property real rowHeight: Math.round(editor.height * 0.19)
            topMargin: Math.round(editor.height * 0.13)
            bottomMargin: Math.round(editor.height * 0.2)
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            model: editor.sources ? editor.sources.all : []

            header: Label {
                width: list.width
                height: Math.round(editor.height * 0.12)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                //% "Data"
                text: qsTrId("id-face-data") + localeManager.changesObserver
                font.pixelSize: Math.round(editor.height * 0.06)
                font.styleName: "SemiCondensed Medium"
            }

            delegate: Item {
                id: row
                width: list.width
                height: list.rowHeight
                readonly property bool current: editor.chosenSlot !== null && editor.sourceOf(editor.chosenSlot) === modelData

                EdgeEffect { id: edge; item: row }
                transform: Scale {
                    origin.x: row.width / 2; origin.y: row.height / 2
                    xScale: edge.scale; yScale: edge.scale
                }

                Rectangle {
                    id: pill
                    anchors.fill: parent
                    anchors.leftMargin: Math.round(editor.width * 0.1)
                    anchors.rightMargin: Math.round(editor.width * 0.1)
                    anchors.topMargin: Math.round(parent.height * 0.07)
                    anchors.bottomMargin: Math.round(parent.height * 0.07)
                    radius: height / 2
                    color: rowArea.pressed ? Theme.color.surfaceContainerHigh : Theme.color.surfaceContainerLow
                    border.color: row.current ? Theme.color.primary : "transparent"
                    border.width: Math.max(2, Math.round(editor.width * 0.006))
                    opacity: edge.alpha
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: pill
                    onClicked: editor.choose(modelData)
                }
                Icon {
                    id: rowIcon
                    anchors.left: pill.left
                    anchors.leftMargin: pill.height * 0.3
                    anchors.verticalCenter: pill.verticalCenter
                    width: pill.height * 0.42
                    height: width
                    opacity: edge.alpha
                    name: modelData === "empty" ? "ios-remove-circle-outline" : editor.sources.info(modelData).icon
                }
                Label {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: pill.height * 0.2
                    anchors.right: check.left
                    anchors.verticalCenter: pill.verticalCenter
                    elide: Text.ElideRight
                    opacity: edge.alpha
                    text: editor.sources.name(modelData) + localeManager.changesObserver
                    font.pixelSize: Math.round(editor.height * 0.055)
                    font.styleName: "SemiCondensed Medium"
                }
                Icon {
                    id: check
                    anchors.right: pill.right
                    anchors.rightMargin: pill.height * 0.3
                    anchors.verticalCenter: pill.verticalCenter
                    visible: row.current
                    width: visible ? pill.height * 0.4 : 0
                    height: width
                    name: "ios-checkmark"
                    color: Theme.color.primary
                    opacity: edge.alpha
                }
            }
        }
    }
}
