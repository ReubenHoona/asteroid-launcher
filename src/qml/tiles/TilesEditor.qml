/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * Edit the tiles, opened by a long press on a tile: the tiles in their
 * order, each with up, down and remove; under them the tiles not shown yet,
 * with add; Done saves. The rows are Wear OS sized (52 dp), the crown
 * scrolls the list. "names" maps a tile id to its name.
 */
Item {
    id: editor

    property var tiles: []
    property var names: ({})
    signal done(var tiles)

    // working copy
    property var shown: []
    readonly property var hidden: {
        var all = Object.keys(names)
        return all.filter(function (t) { return shown.indexOf(t) < 0 })
    }

    function open(current) {
        shown = current.slice()
        list.positionViewAtBeginning()
        visible = true
        opacity = 0
        scale = 0.85
        enter.restart()
    }

    function close(save) {
        if (save)
            done(shown.slice())
        leave.restart()
    }

    function move(i, by) {
        var j = i + by
        if (j < 0 || j >= shown.length)
            return
        var s = shown.slice()
        var t = s[i]; s[i] = s[j]; s[j] = t
        shown = s
        Haptics.tick()
    }
    function remove(i) {
        var s = shown.slice()
        s.splice(i, 1)
        shown = s
        Haptics.click()
    }
    function add(t) {
        shown = shown.concat([t])
        Haptics.click()
    }

    visible: false
    anchors.fill: parent

    ParallelAnimation {
        id: enter
        NumberAnimation { target: editor; property: "opacity"; to: 1; duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] }
        NumberAnimation { target: editor; property: "scale"; to: 1; duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1] }
    }
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: editor; property: "opacity"; to: 0; duration: 200 }
            NumberAnimation { target: editor; property: "scale"; to: 0.85; duration: 200 }
        }
        PropertyAction { target: editor; property: "visible"; value: false }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    // nothing under the editor takes a touch
    MouseArea { anchors.fill: parent }

    ListView {
        id: list
        anchors.fill: parent
        readonly property real rowHeight: Math.round(editor.height * 0.24)
        topMargin: Math.round(editor.height * 0.12)
        bottomMargin: Math.round(editor.height * 0.12)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        header: Label {
            width: list.width
            height: Math.round(editor.height * 0.13)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            //% "Tiles"
            text: qsTrId("id-tiles-editor") + localeManager.changesObserver
            font.pixelSize: Math.round(editor.height * 0.07)
            font.styleName: "SemiCondensed Medium"
        }

        model: editor.shown.length + editor.hidden.length + 1
        delegate: Item {
            id: row
            width: list.width
            height: list.rowHeight
            readonly property int rowIndex: index
            readonly property bool isShown: index < editor.shown.length
            readonly property bool isDone: index === editor.shown.length + editor.hidden.length
            readonly property string tileId: isShown ? editor.shown[index]
                                                     : isDone ? "" : editor.hidden[index - editor.shown.length]

            EdgeEffect { id: edge; item: row }
            transform: Scale {
                origin.x: row.width / 2; origin.y: row.height / 2
                xScale: edge.scale; yScale: edge.scale
            }

            Rectangle {
                id: pill
                anchors.fill: parent
                anchors.leftMargin: Math.round(editor.width * 0.09)
                anchors.rightMargin: Math.round(editor.width * 0.09)
                anchors.topMargin: Math.round(parent.height * 0.06)
                anchors.bottomMargin: Math.round(parent.height * 0.06)
                radius: height / 2
                color: row.isDone ? "#a8c7fa" : row.isShown ? "#2d2d30" : "#1a1a1c"
                opacity: edge.alpha
            }

            MouseArea {
                anchors.fill: pill
                enabled: row.isDone || !row.isShown
                onClicked: row.isDone ? editor.close(true) : editor.add(row.tileId)
            }

            Icon {
                id: addIcon
                visible: !row.isShown && !row.isDone
                name: "ios-add"
                anchors.left: pill.left
                anchors.leftMargin: pill.height * 0.3
                anchors.verticalCenter: pill.verticalCenter
                width: pill.height * 0.42
                height: width
                opacity: edge.alpha
            }

            Label {
                anchors.left: row.isShown ? pill.left : addIcon.right
                anchors.leftMargin: row.isShown ? pill.height * 0.4 : pill.height * 0.15
                anchors.right: buttons.left
                anchors.verticalCenter: pill.verticalCenter
                horizontalAlignment: row.isDone ? Text.AlignHCenter : Text.AlignLeft
                elide: Text.ElideRight
                color: row.isDone ? "#000000" : "#ffffff"
                opacity: edge.alpha * (row.isShown || row.isDone ? 1 : 0.75)
                //% "Done"
                text: (row.isDone ? qsTrId("id-tiles-done") : editor.names[row.tileId] || row.tileId) + localeManager.changesObserver
                font.pixelSize: Math.round(editor.height * 0.06)
                font.styleName: "SemiCondensed Medium"
            }

            Row {
                id: buttons
                anchors.right: pill.right
                anchors.rightMargin: pill.height * 0.15
                anchors.verticalCenter: pill.verticalCenter
                visible: row.isShown
                width: visible ? implicitWidth : 0
                opacity: edge.alpha
                Repeater {
                    model: [["ios-arrow-up", -1], ["ios-arrow-down", 1], ["ios-close", 0]]
                    delegate: MouseArea {
                        width: pill.height * 0.72
                        height: pill.height
                        onClicked: modelData[1] === 0 ? editor.remove(row.rowIndex) : editor.move(row.rowIndex, modelData[1])
                        Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.6
                            height: width
                            name: modelData[0]
                            opacity: (modelData[1] === -1 && row.rowIndex === 0)
                                     || (modelData[1] === 1 && row.rowIndex === editor.shown.length - 1) ? 0.3 : 1
                        }
                    }
                }
            }
        }
    }
}
