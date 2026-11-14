/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import ".."
import "../facepicker.js" as FP
import "tileseditor.js" as TE

/*
 * The list of the tiles that are not in the carousel, as stock's "Widgets"
 * (SysUI managementui_all_items, AllItemsView): a header curved along the top,
 * then two columns of cells, each the app's icon (16 dp), the tile's live
 * preview as a 80 dp circle in a 2 dp ring, and its name (one line, 80 dp wide,
 * 6 dp under the preview). Opening: scale 0.25 to 1 in 250 ms (0.4, 0, 0.2, 1),
 * alpha 0 to 1 in 75 ms, from a black disc, with a white #12ffffff flash held
 * 75 ms and faded over 750 ms (the same as the face picker's list). Back (a
 * swipe right) is the reverse. A tap on a cell emits picked(id, cx, cy,
 * size) with where the preview is; the editor adds the tile and flies the
 * preview into its card. Gap tiles-framework-18.
 */
Item {
    id: list
    anchors.fill: parent
    visible: false

    // id -> { file, name, icon }, and the ids to list
    property var registry: ({})
    property var tiles: []
    // function(id) -> the app icon's name, or null for the registry's
    property var iconOf: null
    readonly property real u: width / 384

    readonly property bool isOpen: visible && !leaving
    property bool leaving: false

    signal picked(string tileId, real cx, real cy, real size)
    signal closed()

    readonly property alias grid: grid
    readonly property real previewSize: TE.LIST_PREVIEW * u
    readonly property real ringWidth: TE.LIST_RING * u
    readonly property real captionSize: Theme.type.bodySmall.pixelSize
    readonly property real captionLine: captionSize * Theme.type.bodySmall.lineHeight / Theme.type.bodySmall.pixelSize
    readonly property var cellGeo: TE.cell(width, captionLine)
    // the grid starts under the header (inferred, as the face list)
    readonly property real gridTop: TE.LIST_TOP * u
    readonly property real bottomPadding: TE.LIST_BOTTOM * height

    function open() {
        leaveAnim.stop()
        fadeAnimRun.stop()
        leaving = false
        panel.scale = FP.ADD_SCALE_FROM
        panel.opacity = 0
        flash.opacity = 0
        grid.contentY = -grid.topMargin
        visible = true
        enterAnim.restart()
    }

    // back: the reverse of the entry (not when the list is not there)
    function back() {
        if (!visible || leaving)
            return
        enterAnim.stop()
        leaving = true
        leaveAnim.restart()
    }

    // gone at once (the editor closes, the display went off)
    function closeNow() {
        enterAnim.stop()
        leaveAnim.stop()
        fadeAnimRun.stop()
        leaving = false
        visible = false
    }

    // the list fades out (a tile was picked: the editor flies the preview away first)
    function fadeOut(ms) {
        fadeAnim.duration = ms
        fadeAnimRun.restart()
    }

    Item {
        id: panel
        objectName: "eosTileListPanel"
        anchors.fill: parent
        transformOrigin: Item.Center

        // the circular reveal: a black disc that grows with the list
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
        }

        // a tap and a swipe: nothing under the list takes a touch
        MouseArea { anchors.fill: parent }

        GridView {
            id: grid
            objectName: "eosTileListGrid"
            anchors.fill: parent
            topMargin: list.gridTop
            bottomMargin: list.bottomPadding
            cellWidth: width / TE.LIST_COLUMNS
            cellHeight: list.cellGeo.height
            model: list.tiles
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: cell
                objectName: "eosTileListCell"
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property string tileId: modelData
                readonly property var entry: list.registry[modelData] || ({})

                // the app's icon above the preview
                Icon {
                    objectName: "eosTileListIcon"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: list.cellGeo.icon
                    height: width
                    name: list.iconOf ? list.iconOf(cell.tileId) : (cell.entry.icon || "ios-help")
                }
                // the preview's ring and the tile
                Rectangle {
                    id: ring
                    objectName: "eosTileListRing"
                    y: list.cellGeo.icon
                    width: list.cellGeo.ring
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Theme.color.surfaceContainer
                    border.color: TE.LIST_RING_COLOR
                    border.width: list.ringWidth

                    Loader {
                        id: tile
                        objectName: "eosTileListTile"
                        active: list.visible && !!cell.entry.file
                        asynchronous: true
                        width: list.width
                        height: list.height
                        anchors.centerIn: parent
                        scale: list.previewSize / list.width
                        visible: status === Loader.Ready
                        source: cell.entry.file ? Qt.resolvedUrl(cell.entry.file.replace(/^tiles\//, "")) : ""
                        enabled: false
                        onLoaded: if (item && item.preview !== undefined) item.preview = true
                    }
                    RoundMask {
                        anchors.centerIn: parent
                        width: list.previewSize
                        height: width
                        color: "#000000"
                        visible: tile.status === Loader.Ready
                    }
                    // the ring over the mask's edge
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: TE.LIST_RING_COLOR
                        border.width: list.ringWidth
                    }
                    Label {
                        objectName: "eosTileListUnavailable"
                        anchors.centerIn: parent
                        width: parent.width * 0.7
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: tile.status === Loader.Error
                        //% "Preview unavailable"
                        text: qsTrId("id-tiles-preview-unavailable") + localeManager.changesObserver
                        color: Theme.color.onSurfaceVariant
                        font.pixelSize: list.captionSize
                    }
                }
                Label {
                    objectName: "eosTileListName"
                    anchors.top: ring.bottom
                    anchors.topMargin: list.cellGeo.nameTop
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: list.previewSize
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: (cell.entry.name || cell.tileId) + localeManager.changesObserver
                    color: Theme.color.onSurface
                    font.pixelSize: list.captionSize
                }
                MouseArea {
                    objectName: "eosTileListTap"
                    anchors.fill: parent
                    onClicked: {
                        var p = ring.mapToItem(list, ring.width / 2, ring.height / 2)
                        list.picked(cell.tileId, p.x, p.y, list.previewSize)
                    }
                }
            }
        }

        // the header along the top edge
        CurvedTopText {
            objectName: "eosTileListTitle"
            anchors.fill: parent
            //% "Widgets"
            text: qsTrId("id-tiles-add-header") + localeManager.changesObserver
            color: Theme.color.onSurface
            role: "arcMedium"
            pixelSize: Theme.dp(15)
            maxSweep: FP.NAME_SWEEP
            topMargin: Math.round(list.height * TE.LIST_TITLE_TOP / 100)
            shadow: "transparent"
        }

        // a white flash held 75 ms, then faded over 750 ms
        Rectangle {
            id: flash
            objectName: "eosTileListFlash"
            anchors.fill: parent
            radius: width / 2
            color: FP.ADD_FLASH_COLOR
            opacity: 0
            visible: opacity > 0
        }

        // swipe right: back (the stock decision rule of the back swipe)
        DragHandler {
            id: swipe
            target: null
            yAxis.enabled: false
            property real lastDx: 0
            property real dx: 0
            property real v: 0
            onTranslationChanged: {
                lastDx = translation.x - dx
                dx = translation.x
                v = centroid.velocity.x
            }
            onActiveChanged: {
                if (active) {
                    dx = 0
                    lastDx = 0
                    v = 0
                } else if (Motion.backShouldCommit(dx, v, lastDx, list.width, Theme.dp(1))) {
                    list.back()
                }
            }
        }
    }

    // the entry
    ParallelAnimation {
        id: enterAnim
        objectName: "eosTileListEnter"
        NumberAnimation {
            target: panel; property: "scale"; from: FP.ADD_SCALE_FROM; to: 1
            duration: Motion.duration(FP.ADD_SCALE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation { target: panel; property: "opacity"; from: 0; to: 1; duration: Motion.duration(FP.ADD_ALPHA_MS) }
        SequentialAnimation {
            PropertyAction { target: flash; property: "opacity"; value: 1 }
            PauseAnimation { duration: Motion.duration(FP.ADD_FLASH_HOLD_MS) }
            NumberAnimation { target: flash; property: "opacity"; to: 0; duration: Motion.duration(FP.ADD_FLASH_FADE_MS) }
        }
    }
    // the way back
    SequentialAnimation {
        id: leaveAnim
        objectName: "eosTileListLeave"
        ParallelAnimation {
            NumberAnimation {
                target: panel; property: "scale"; to: FP.ADD_SCALE_FROM
                duration: Motion.duration(FP.ADD_SCALE_MS)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
            }
            NumberAnimation { target: panel; property: "opacity"; to: 0; duration: Motion.duration(FP.ADD_SCALE_MS) }
        }
        ScriptAction { script: { list.leaving = false; list.visible = false; list.closed() } }
    }
    // the list fades out after a tile was picked
    SequentialAnimation {
        id: fadeAnimRun
        objectName: "eosTileListFade"
        NumberAnimation {
            id: fadeAnim
            target: panel; property: "opacity"; to: 0; duration: FP.ADD_LIST_FADE_MS
        }
        ScriptAction { script: { list.visible = false; list.closed() } }
    }
}
