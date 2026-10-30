/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQml.Models
import QtCore
import "complications"
import Qt.labs.folderlistmodel
import org.asteroid.controls
import org.asteroid.utils
import Nemo.Configuration

/*
 * The watchface picker, opened by a long press on the watchface as on
 * Wear OS: the watchface shrinks into a carousel of the installed faces
 * (their preview images), the current one in the middle; a swipe or the
 * crown moves through them one at a time; a tap on the middle one puts it
 * on and the picker grows back into it. The crown button leaves without
 * changing.
 */
Item {
    id: picker

    property string current: ""
    signal chosen(string face)

    readonly property string systemFolder: "file:///usr/share/asteroid-launcher/watchfaces"
    // the faces of the Settings store (WatchfaceReloader's folder)
    readonly property string userFolder: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/asteroid-launcher/watchfaces"
    readonly property string previewFolder: "file:///usr/share/asteroid-launcher/watchfaces-preview/182/"

    // 0 closed .. 1 open
    property real progress: 0
    visible: progress > 0
    anchors.fill: parent

    readonly property var _easing: [0.4, 0, 0.2, 1, 1, 1]

    function open() {
        options.visible = false
        faces.positionAt(current)
        closeAnim.stop()
        openAnim.restart()
    }

    function close() {
        openAnim.stop()
        closeAnim.restart()
    }

    function choose(face) {
        if (face !== current)
            chosen(face)
        Haptics.confirm()
        close()
    }

    NumberAnimation {
        id: openAnim
        target: picker; property: "progress"; to: 1; duration: 300
        easing.type: Easing.BezierSpline; easing.bezierCurve: picker._easing
    }
    NumberAnimation {
        id: closeAnim
        target: picker; property: "progress"; to: 0; duration: 250
        easing.type: Easing.BezierSpline; easing.bezierCurve: picker._easing
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: picker.progress
    }

    // nothing under the picker takes a touch
    MouseArea {
        anchors.fill: parent
    }

    // both folders, in one list of file URLs
    property var all: []
    function refresh() {
        var list = []
        for (var i = 0; i < systemFaces.count; i++)
            list.push(systemFaces.get(i, "fileUrl").toString())
        for (var j = 0; j < userFaces.count; j++)
            list.push(userFaces.get(j, "fileUrl").toString())
        all = list
    }
    FolderListModel {
        id: systemFaces
        folder: picker.systemFolder
        nameFilters: ["*.qml"]
        showDirs: false
        onStatusChanged: if (status === FolderListModel.Ready) picker.refresh()
        onCountChanged: picker.refresh()
    }
    FolderListModel {
        id: userFaces
        folder: picker.userFolder
        nameFilters: ["*.qml"]
        showDirs: false
        onCountChanged: picker.refresh()
    }

    ListView {
        id: faces
        anchors.fill: parent
        orientation: ListView.Horizontal
        // one face at a time, the current one in the middle
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - itemSize) / 2
        preferredHighlightEnd: (width + itemSize) / 2
        highlightMoveDuration: 250
        // Wear OS shows the faces at about 70% of the screen
        readonly property real itemSize: Math.round(width * 0.62)
        cacheBuffer: width
        opacity: picker.progress
        scale: 1.4 - 0.4 * picker.progress
        model: picker.all
        // the crown steps through the faces (RotaryInput: a snapping view)
        interactive: picker.progress >= 1

        function positionAt(face) {
            var i = picker.all.indexOf(face)
            currentIndex = i < 0 ? 0 : i
            positionViewAtIndex(currentIndex, ListView.Center)
        }

        onCurrentIndexChanged: if (picker.progress >= 1) Haptics.tick()

        delegate: Item {
            id: faceItem
            width: faces.itemSize
            height: faces.height
            readonly property string name: modelData.split("/").pop().replace(/\.qml$/, "")
            readonly property bool isCurrent: ListView.isCurrentItem
            // the faces beside the middle one are smaller and dimmer
            readonly property real offset: Math.min(1, Math.abs((x - faces.contentX + width / 2) - faces.width / 2) / faces.itemSize)

            Item {
                anchors.centerIn: parent
                width: faces.itemSize
                height: width
                scale: 1 - 0.25 * faceItem.offset
                opacity: 1 - 0.5 * faceItem.offset

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "#202124"
                    border.color: faceItem.name + ".qml" === picker.current.split("/").pop() ? "#a8c7fa" : "#3c4043"
                    border.width: Math.max(2, Math.round(picker.width * 0.008))
                }
                Image {
                    anchors.fill: parent
                    anchors.margins: Math.round(picker.width * 0.012)
                    source: picker.previewFolder + faceItem.name + ".png"
                    sourceSize.width: 182
                    sourceSize.height: 182
                    asynchronous: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (faceItem.isCurrent)
                            picker.choose(modelData)
                        else
                            faces.currentIndex = index
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(picker.height * 0.07)
                visible: faceItem.isCurrent
                width: picker.width * 0.6
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: faceItem.name.replace(/^[0-9]+-/, "").replace(/-/g, " ")
                font.pixelSize: Math.round(picker.height * 0.05)
                opacity: 0.8
            }
        }
    }

    /* Wear OS's face editor: under the faces a Customize button. Its pages,
     * swiped through as stock's: the options every bundled face follows
     * (the launcher applies them by the faces' item names, see
     * WatchfaceReloader.applyFaceOptions), then the face's complications
     * when it has slots (FaceEditor). Customize on another face than the
     * one worn puts it on first, as stock edits the face it applies. */
    ConfigurationValue { id: showDate; key: "/org/asteroidos/watchface/show-date"; defaultValue: true }
    ConfigurationValue { id: showSeconds; key: "/org/asteroidos/watchface/show-seconds"; defaultValue: true }
    ConfigurationValue { id: ambientStyle; key: "/org/asteroidos/watchface/ambient-style"; defaultValue: "dim" }

    // the face on the home screen (MainScreen sets these): the live item the
    // complications page shows, and the home screen's complication sources
    property Item liveFace: null
    property QtObject sources: null
    readonly property bool hasSlots: sources !== null && liveFace !== null && sources.slotsOf(liveFace).length > 0

    // the crown button: from a slot's data sources back to the slots;
    // false when there is no level to go back to
    function back() {
        if (options.visible && complicationsPage.choosing) {
            complicationsPage.chosenSlot = null
            return true
        }
        return false
    }

    function customize() {
        var face = picker.all[faces.currentIndex]
        if (face && face !== current) {
            current = face
            chosen(face)
        }
        pages.currentIndex = 0
        pages.positionViewAtBeginning()
        options.visible = true
    }

    MouseArea {
        id: customize
        visible: !options.visible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(picker.height * 0.06)
        width: Math.round(picker.width * 0.46)
        height: Math.round(picker.height * 0.16)
        opacity: picker.progress
        onClicked: {
            Haptics.click()
            picker.customize()
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: "#a8c7fa"
            opacity: customize.pressed ? 0.75 : 1
        }
        Label {
            anchors.centerIn: parent
            //% "Customize"
            text: qsTrId("id-face-customize") + localeManager.changesObserver
            color: "#000000"
            font.pixelSize: Math.round(picker.height * 0.055)
            font.styleName: "SemiCondensed Medium"
        }
    }

    Item {
        id: options
        anchors.fill: parent
        visible: false
        onVisibleChanged: {
            if (!visible) {
                optionsFlick.contentY = 0
                complicationsPage.chosenSlot = null
            }
        }

        Rectangle { anchors.fill: parent; color: "#000000" }
        MouseArea { anchors.fill: parent }

        readonly property var styleLabels: [
            //% "Dimmed"
            qsTrId("id-face-ambient-dim"),
            //% "Outline"
            qsTrId("id-face-ambient-outline")
        ]
        readonly property var styleValues: ["dim", "outline"]
        readonly property real rowHeight: Dims.h(25)

        ListView {
            id: pages
            anchors.fill: parent
            orientation: ListView.Horizontal
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: 250
            boundsBehavior: Flickable.StopAtBounds
            // the source list of a slot is a page of its own
            interactive: picker.hasSlots && !complicationsPage.choosing
            clip: true
            model: ObjectModel {
                Item {
                    id: optionsPage
                    width: pages.width
                    height: pages.height
                    Flickable {
                        id: optionsFlick
                        anchors.fill: parent
                        contentHeight: optionsColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        Column {
                            id: optionsColumn
                            width: parent.width
                            Item { width: parent.width; height: Dims.h(16) }
                            LabeledSwitch {
                                width: parent.width
                                height: options.rowHeight
                                //% "Date"
                                text: qsTrId("id-face-show-date")
                                checked: showDate.value
                                onCheckedChanged: if (showDate.value !== checked) showDate.value = checked
                            }
                            LabeledSwitch {
                                width: parent.width
                                height: options.rowHeight
                                //% "Seconds"
                                text: qsTrId("id-face-show-seconds")
                                checked: showSeconds.value
                                onCheckedChanged: if (showSeconds.value !== checked) showSeconds.value = checked
                            }
                            OptionCycler {
                                width: parent.width
                                height: options.rowHeight
                                //% "Always-on"
                                text: qsTrId("id-face-ambient")
                                valueArray: options.styleLabels
                                currentValue: options.styleLabels[Math.max(0, options.styleValues.indexOf(ambientStyle.value))]
                                onValueChanged: (value) => ambientStyle.value = options.styleValues[options.styleLabels.indexOf(value)]
                            }
                            Item { width: parent.width; height: Dims.h(4) }
                            MouseArea {
                                id: done
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.round(picker.width * 0.4)
                                height: Math.round(picker.height * 0.15)
                                onClicked: options.visible = false
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: "#a8c7fa"
                                    opacity: done.pressed ? 0.75 : 1
                                }
                                Label {
                                    anchors.centerIn: parent
                                    //% "Done"
                                    text: qsTrId("id-tiles-done") + localeManager.changesObserver
                                    color: "#000000"
                                    font.pixelSize: Math.round(picker.height * 0.055)
                                    font.styleName: "SemiCondensed Medium"
                                }
                            }
                            Item { width: parent.width; height: Dims.h(16) }
                        }
                    }
                    PageHeader {
                        //% "Watch face"
                        text: qsTrId("id-face-options")
                    }
                }
                FaceEditor {
                    id: complicationsPage
                    width: pages.width
                    height: pages.height
                    face: options.visible ? picker.liveFace : null
                    faceUrl: picker.current
                    sources: picker.sources
                }
            }
        }

        // the page dots at the bottom, as stock's editor
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(picker.height * 0.025)
            spacing: Math.round(picker.width * 0.02)
            visible: picker.hasSlots && !complicationsPage.choosing
            Repeater {
                model: 2
                delegate: Rectangle {
                    width: Math.round(picker.width * 0.018)
                    height: width
                    radius: width / 2
                    color: "#ffffff"
                    opacity: pages.currentIndex === index ? 0.9 : 0.35
                }
            }
        }
    }
}
