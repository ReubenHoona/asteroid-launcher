/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import ".."
import "../compositor"
import "../facepicker.js" as FP
import "tileseditor.js" as TE

/*
 * The list of the tiles that are not in the carousel, as stock's (SysUI
 * managementui_all_items, AllItemsView) in the Wear OS 6 emulator's look
 * (S14-d; N61-31): the header "Add" curved along the top, then two columns of
 * cells, each the tile's live preview as a 80 dp circle in a 2 dp #404040
 * ring (the first rings' tops at 88 px) and its name under it (one line,
 * 80 dp wide, white, its capitals 29 px under the ring); no app icon. Opening: scale 0.25 to 1 in 250 ms (0.4, 0, 0.2, 1),
 * alpha 0 to 1 in 75 ms, from a black disc, with a white #12ffffff flash held
 * 75 ms and faded over 750 ms (the same as the face picker's list). Back by
 * the crown is the reverse. A swipe right is stock's SwipeDismissFrameLayout
 * around managementui_all_items (management_ui_root_layout.xml:66-71; R5
 * B-16, motion B8; the face picker's list does the same, facepicker.js
 * ADD_DISMISS_*): the list follows the finger, squeezed about its centre
 * with its right edge pinned (scale 1 - 0.3 p, at least 0.7) and dimmed
 * (min(0.3, p / 2)); past 0.33 of the width (not moving back) or on a fling
 * right of 500 dp/s it goes right on a spring 1.0/600 and the carousel is
 * back, else it springs back. A tap on a cell emits picked(id, cx, cy,
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
    readonly property real u: width / 384

    readonly property bool isOpen: visible && !leaving
    property bool leaving: false

    signal picked(string tileId, real cx, real cy, real size)
    signal closed()

    // the swipe to dismiss: the list's move right (px), its scale, the progress its dim follows; it is
    // swiping from the first move of the finger to the end of its spring
    property real swipeX: 0
    property real swipeScale: 1
    property real swipeP: 0
    property bool swiping: false
    property bool dismissing: false
    readonly property real swipeDim: FP.addDismissDim(swipeP)

    function dismissCommits(dx, vx, vy, movingBack) {
        return FP.addDismissCommits(dx, vx, vy, movingBack, width, 2 * u)
    }
    // the finger has moved it dx px
    function dragTo(dx) {
        if (!visible || leaving)
            return
        dismissSpring.stop()
        swiping = true
        swipeP = Math.max(0, dx) / width
        swipeScale = FP.addDismissDragScale(swipeP)
        swipeX = Math.max(0, 1 - swipeScale) * width / 2
    }
    // the finger let go at vx, vy px/s
    function release(dx, vx, vy, movingBack) {
        if (!swiping || leaving)
            return
        dismissing = dismissCommits(dx, vx, vy, movingBack)
        if (dismissing)
            leaving = true
        dismissSpring.snapTo(swipeX)
        dismissSpring.animateTo(dismissing ? width : 0, vx)
    }
    function springMoved(x) {
        if (!swiping)
            return
        swipeX = Math.max(0, Math.min(width, x))
        swipeScale = FP.addDismissSpringScale(swipeX, width)
        swipeP = Math.max(swipeP, (swipeScale - 1) / -FP.ADD_DISMISS_SCALE)
    }
    function springDone() {
        var gone = dismissing
        resetSwipe()
        if (gone) {
            // as back() ends, without its reverse zoom (the carousel is back, iax.java:15-26)
            leaving = false
            visible = false
            closed()
        }
    }
    function resetSwipe() {
        dismissSpring.stop()
        swiping = false
        dismissing = false
        swipeX = 0
        swipeScale = 1
        swipeP = 0
    }
    WearSpring {
        id: dismissSpring
        objectName: "eosTileListDismissSpring"
        stiffness: FP.ADD_DISMISS_STIFFNESS
        dampingRatio: FP.ADD_DISMISS_DAMPING
        visibilityThreshold: FP.ADD_DISMISS_MIN_CHANGE
        onValueChanged: list.springMoved(value)
        onFinished: list.springDone()
    }

    readonly property alias grid: grid
    readonly property real previewSize: TE.LIST_PREVIEW * u
    readonly property real ringWidth: TE.LIST_RING * u
    readonly property real captionSize: Theme.type.bodySmall.pixelSize
    readonly property real captionLine: captionSize * Theme.type.bodySmall.lineHeight / Theme.type.bodySmall.pixelSize
    readonly property var cellGeo: TE.cell(width, captionLine)
    // the first rings' tops (S14-d: 88 px)
    readonly property real gridTop: TE.LIST_TOP * u
    readonly property real bottomPadding: TE.LIST_BOTTOM * height

    function open() {
        leaveAnim.stop()
        fadeAnimRun.stop()
        resetSwipe()
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
        resetSwipe()
        leaving = true
        leaveAnim.restart()
    }

    // gone at once (the editor closes, the display went off)
    function closeNow() {
        enterAnim.stop()
        leaveAnim.stop()
        fadeAnimRun.stop()
        resetSwipe()
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
        // the swipe: scaled about the centre, then moved right
        transform: [
            Scale {
                origin.x: panel.width / 2
                origin.y: panel.height / 2
                xScale: list.swipeScale
                yScale: list.swipeScale
            },
            Translate { x: list.swipeX }
        ]
        // stock clips the moving frame to the round outline (gax.java:96-98); a layer only while it moves
        layer.enabled: list.swiping
        layer.effect: CircleMaskShader { }

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
            // the tile picker is an M3 screen in stock (the Wear OS 6 emulator S14-d: #C6C6C6 thumb,
            // +-16 degrees): the app style of the scroll indicator, not the launcher's system style
            property bool m3Indicator: true
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

                // the preview's ring and the tile (no app icon over it since N61-31)
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
                    color: Theme.color.onBackground
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
            //% "Add"
            text: qsTrId("id-tiles-add-title") + localeManager.changesObserver
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

        // the dim of the swipe (stock: a SRC_ATOP black on the frame's layer, gax.java:116-127)
        Rectangle {
            objectName: "eosTileListDim"
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            opacity: list.swipeDim
            visible: opacity > 0
        }

        // swipe right: the list follows the finger, then goes or comes back (SwipeDismissFrameLayout)
        DragHandler {
            id: swipe
            target: null
            yAxis.enabled: false
            // the finger's x at its last move: stock's gaq.i, the raw X of the last MOVE (gar.java:150-152)
            property real lastMoveX: 0
            property real dx: 0
            property real vx: 0
            property real vy: 0
            onTranslationChanged: {
                dx = translation.x
                lastMoveX = centroid.scenePosition.x
                vx = centroid.velocity.x
                vy = centroid.velocity.y
                if (active)
                    list.dragTo(dx)
            }
            onActiveChanged: {
                if (active) {
                    dx = 0
                    lastMoveX = centroid.scenePosition.x
                    vx = 0
                    vy = 0
                } else {
                    // moving back is the UP left of the last MOVE (gar.java:192)
                    list.release(dx, vx, vy, centroid.scenePosition.x < lastMoveX)
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
