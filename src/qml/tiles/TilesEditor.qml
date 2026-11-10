/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * Edit the tiles as stock Wear OS does on the watch, opened by a long press
 * on a tile: the tiles shrink into a carousel in their order, the pressed
 * one in the middle; a swipe or the crown moves through them. Under the
 * middle one a minus removes it (a swipe up on it too, as on the Pixel
 * Watch); the arrows beside it move it left or right; after the last tile
 * "Add tile" opens the list of the tiles not shown, and a tap on one adds
 * it there. A tap on the middle tile, the crown button or the screen going
 * off ends the editing on the tile in the middle. Every change is kept at
 * once, as stock: changed(tiles) (MainScreen writes dconf
 * /org/asteroidos/ux/tiles). "registry" maps a tile id to { file, name, icon }.
 */
Item {
    id: editor

    property var registry: ({})
    signal changed(var tiles)
    // the editing ended on this tile (an index of the list, -1: none)
    signal finished(int index)

    property var shown: []
    readonly property var hidden: {
        var all = Object.keys(registry)
        return all.filter(function (t) { return shown.indexOf(t) < 0 })
    }
    readonly property bool adding: addList.visible

    // the carousel's model: the tiles, then "Add tile" (a ListModel, so a
    // removal, a move or an addition keeps the view where it is)
    ListModel { id: cards }

    function open(current, at) {
        shown = current.slice()
        cards.clear()
        for (var i = 0; i < shown.length; i++)
            cards.append({ tileId: shown[i] })
        cards.append({ tileId: "" })
        addList.visible = false
        visible = true
        opacity = 0
        scale = 1.15
        carousel.currentIndex = Math.max(0, Math.min(at, shown.length))
        carousel.positionViewAtIndex(carousel.currentIndex, ListView.Center)
        enter.restart()
    }

    function close() {
        if (!visible || leave.running)
            return
        var i = carousel.currentIndex
        finished(i < shown.length ? i : shown.length - 1)
        leave.restart()
    }

    // the crown button: from the list of tiles to add back to the carousel;
    // false when there is no level to go back to
    function back() {
        if (addList.visible) {
            addList.visible = false
            return true
        }
        return false
    }

    function save(list) {
        shown = list
        changed(list.slice())
    }
    function move(i, by) {
        var j = i + by
        if (j < 0 || j >= shown.length)
            return
        var s = shown.slice()
        var t = s[i]; s[i] = s[j]; s[j] = t
        cards.move(i, j, 1)
        save(s)
        carousel.currentIndex = j
        Haptics.tick()
    }
    function remove(i) {
        if (i < 0 || i >= shown.length)
            return
        var s = shown.slice()
        s.splice(i, 1)
        cards.remove(i)
        save(s)
        carousel.currentIndex = Math.min(i, s.length)
        Haptics.click()
    }
    function add(t) {
        // after the middle tile, as stock adds next to the tile edited
        var at = Math.min(carousel.currentIndex + 1, shown.length)
        var s = shown.slice()
        s.splice(at, 0, t)
        cards.insert(at, { tileId: t })
        save(s)
        addList.visible = false
        carousel.currentIndex = at
        carousel.positionViewAtIndex(at, ListView.Center)
        Haptics.confirm()
    }

    visible: false
    anchors.fill: parent

    readonly property var _easing: [0.4, 0, 0.2, 1, 1, 1]
    ParallelAnimation {
        id: enter
        NumberAnimation { target: editor; property: "opacity"; to: 1; duration: 150; easing.type: Easing.BezierSpline; easing.bezierCurve: editor._easing }
        NumberAnimation { target: editor; property: "scale"; to: 1; duration: 250; easing.type: Easing.BezierSpline; easing.bezierCurve: editor._easing }
    }
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: editor; property: "opacity"; to: 0; duration: 200 }
            NumberAnimation { target: editor; property: "scale"; to: 1.15; duration: 200 }
        }
        PropertyAction { target: editor; property: "visible"; value: false }
        PropertyAction { target: addList; property: "visible"; value: false }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    // nothing under the editor takes a touch
    MouseArea { anchors.fill: parent }

    // ---- the carousel -------------------------------------------------------
    readonly property real tileSize: Math.round(width * 0.62)

    ListView {
        id: carousel
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - editor.tileSize) / 2
        preferredHighlightEnd: (width + editor.tileSize) / 2
        highlightMoveDuration: 250
        cacheBuffer: width
        visible: !editor.adding
        interactive: !editor.adding
        // the tiles, then "Add tile"
        model: cards
        onCurrentIndexChanged: if (editor.visible) Haptics.tick()

        delegate: Item {
            id: card
            width: editor.tileSize
            height: carousel.height
            readonly property bool isAdd: model.tileId === ""
            readonly property string tileId: model.tileId
            readonly property bool isCurrent: ListView.isCurrentItem
            readonly property real offset: Math.min(1, Math.abs((x - carousel.contentX + width / 2) - carousel.width / 2) / editor.tileSize)

            Item {
                id: frame
                anchors.centerIn: parent
                width: editor.tileSize
                height: width
                scale: 1 - 0.2 * card.offset
                opacity: 1 - 0.5 * card.offset

                // the tile itself, drawn at full size and shrunk
                Loader {
                    id: preview
                    active: !card.isAdd && editor.visible
                    width: editor.width
                    height: editor.height
                    anchors.centerIn: parent
                    scale: editor.tileSize / editor.width
                    source: !card.isAdd && editor.registry[card.tileId] ? Qt.resolvedUrl(editor.registry[card.tileId].file.replace(/^tiles\//, "")) : ""
                    // it is a picture here: no taps reach it
                    enabled: false
                    onLoaded: item.preview = true
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: card.isCurrent && !card.isAdd ? Theme.color.primary : Theme.color.surfaceContainerHigh
                    border.width: Math.max(2, Math.round(editor.width * 0.006))
                }

                // "Add tile"
                Rectangle {
                    visible: card.isAdd
                    anchors.fill: parent
                    radius: width / 2
                    color: "#1a1a1c"
                }
                Column {
                    visible: card.isAdd
                    anchors.centerIn: parent
                    spacing: Math.round(editor.height * 0.02)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(editor.width * 0.17)
                        height: width
                        radius: width / 2
                        color: Theme.color.primary
                        opacity: editor.hidden.length > 0 ? 1 : 0.4
                        Icon {
                            anchors.centerIn: parent
                            width: parent.width * 0.55
                            height: width
                            name: "ios-add"
                            color: Theme.color.onPrimary
                        }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        //% "Add tile"
                        text: qsTrId("id-tiles-add") + localeManager.changesObserver
                        font.pixelSize: Math.round(editor.height * 0.05)
                        font.styleName: "SemiCondensed Medium"
                    }
                }

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    // a swipe up on the middle tile removes it (Pixel Watch)
                    property real startY: 0
                    property bool swiped: false
                    onPressed: (mouse) => { startY = mouse.y; swiped = false }
                    onPositionChanged: (mouse) => {
                        if (card.isCurrent && !card.isAdd && startY - mouse.y > frame.height * 0.3 && !swiped) {
                            swiped = true
                            editor.remove(index)
                        }
                    }
                    onClicked: {
                        if (swiped)
                            return
                        if (!card.isCurrent)
                            carousel.currentIndex = index
                        else if (card.isAdd) {
                            if (editor.hidden.length > 0) {
                                Haptics.click()
                                addView.positionViewAtBeginning()
                                addList.visible = true
                            }
                        } else
                            editor.close()
                    }
                }
            }

            // the tile's name over it
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(editor.height * 0.06)
                visible: card.isCurrent && !card.isAdd
                width: editor.width * 0.5
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.isAdd ? "" : (editor.registry[card.tileId] ? editor.registry[card.tileId].name : card.tileId) + localeManager.changesObserver
                font.pixelSize: Math.round(editor.height * 0.05)
                opacity: 0.8
            }
        }
    }

    // ---- the buttons of the middle tile -------------------------------------
    readonly property bool onTile: carousel.currentIndex >= 0 && carousel.currentIndex < shown.length
    readonly property real buttonSize: Math.round(width * 0.15)

    // remove: the minus under the tile
    MouseArea {
        id: removeButton
        objectName: "removeTileButton"
        visible: editor.onTile && !editor.adding && !carousel.moving
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(editor.height * 0.035)
        width: editor.buttonSize
        height: width
        onClicked: editor.remove(carousel.currentIndex)
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: removeButton.pressed ? "#b3261e" : "#8c1d18"
        }
        // the minus (the icon font's is a hairline at this size)
        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.42)
            height: Math.max(3, Math.round(parent.width * 0.075))
            radius: height / 2
            color: "#f9dedc"
        }
    }

    // move: the arrows beside it
    Repeater {
        model: [-1, 1]
        delegate: MouseArea {
            id: arrow
            readonly property int by: modelData
            readonly property bool can: editor.onTile && carousel.currentIndex + by >= 0 && carousel.currentIndex + by < editor.shown.length
            visible: editor.onTile && !editor.adding && !carousel.moving
            enabled: can
            anchors.verticalCenter: parent.verticalCenter
            x: by < 0 ? Math.round(editor.width * 0.035) : editor.width - width - Math.round(editor.width * 0.035)
            width: Math.round(editor.width * 0.13)
            height: Math.round(editor.height * 0.26)
            onClicked: editor.move(carousel.currentIndex, by)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: width
                radius: width / 2
                color: arrow.pressed ? Theme.color.surfaceContainerHigh : Theme.color.surfaceContainerLow
                opacity: arrow.can ? 1 : 0.35
            }
            Icon {
                anchors.centerIn: parent
                width: parent.width * 0.55
                height: width
                name: arrow.by < 0 ? "ios-arrow-back" : "ios-arrow-forward"
                opacity: arrow.can ? 1 : 0.35
            }
        }
    }

    // ---- the tiles to add -----------------------------------------------------
    Item {
        id: addList
        anchors.fill: parent
        visible: false

        ListView {
            id: addView
            anchors.fill: parent
            readonly property real rowHeight: Math.round(editor.height * 0.2)
            topMargin: Math.round(editor.height * 0.13)
            bottomMargin: Math.round(editor.height * 0.15)
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            model: editor.hidden

            header: Label {
                width: addView.width
                height: Math.round(editor.height * 0.12)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: qsTrId("id-tiles-add") + localeManager.changesObserver
                font.pixelSize: Math.round(editor.height * 0.06)
                font.styleName: "SemiCondensed Medium"
            }

            delegate: Item {
                id: row
                width: addView.width
                height: addView.rowHeight
                readonly property var entry: editor.registry[modelData] || ({})

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
                    opacity: edge.alpha
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: pill
                    onClicked: editor.add(modelData)
                }
                Icon {
                    id: rowIcon
                    anchors.left: pill.left
                    anchors.leftMargin: pill.height * 0.3
                    anchors.verticalCenter: pill.verticalCenter
                    width: pill.height * 0.42
                    height: width
                    name: row.entry.icon || "ios-add"
                    opacity: edge.alpha
                }
                Label {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: pill.height * 0.2
                    anchors.right: pill.right
                    anchors.rightMargin: pill.height * 0.3
                    anchors.verticalCenter: pill.verticalCenter
                    elide: Text.ElideRight
                    text: (row.entry.name || modelData) + localeManager.changesObserver
                    font.pixelSize: Math.round(editor.height * 0.055)
                    font.styleName: "SemiCondensed Medium"
                    opacity: edge.alpha
                }
            }
        }
    }
}
