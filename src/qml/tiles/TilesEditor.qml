/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import ".."
import "../facepicker.js" as FP
import "tileseditor.js" as TE

/*
 * Edit the tiles as stock Wear OS does (CP3A SysUI managementui, the view the
 * watch face picker is made on, so numbers and motion match FacePicker),
 * opened by a long press on a tile: the tile shrinks into a carousel of the
 * tiles in their order with "Add new" last, the pressed one in the middle; a
 * swipe or the crown moves through them. Every change is kept at once:
 * changed(tiles) (HomeOverlays writes dconf /org/asteroidos/ux/tiles).
 *
 * - Open: the whole editor starts at scale 384 / 238 = 1.613, where the
 *   middle card (a live copy of the tile) is exactly the tile, and settles
 *   to 1 in 266 ms (0.4, 0, 0.2, 1) with no fade; names and delete buttons
 *   stay hidden for 166 ms, then fade in over 100 ms (gap tiles-framework-08).
 * - Cards: 238 px preview in a 4 px #202124 ring, 278 px apart, side cards
 *   fade by 1 - 0.5 x distance / width and are not scaled (-09); the tile's
 *   name curves along the top edge, 30 px, at most 90 degrees (-10).
 * - Remove: a 64 px round button (surfaceContainer, a 32 x 4 px minus) at the
 *   top-right of every card, hidden while the cards scroll; no swipe removal
 *   (-11). Under the cards two 64 px arrows move the middle tile left or
 *   right, wrapping round the ends, hidden with one tile (-12); between them
 *   a slot for an "Edit widget" chip, shown only for a tile whose registry
 *   entry has `configure` (-13).
 * - Add new: a 120 px primary circle with a 28 px plus (-14). It opens the
 *   add list (TileAddList, -18); an added tile goes last and is centred
 *   (-15) with its preview flying from its cell (-19). With no tile left to
 *   add, or 15 on the carousel, a one button dialog says so (-16, -17).
 * - A tap on a card ends the editing on it, a side card first scrolls to
 *   the middle and waits 200 ms (-22). 15 s without a touch end it on the
 *   middle tile (-20). The crown cancels to the watch face (-21): the
 *   editor shrinks to 0.25 and fades.
 * "registry" maps a tile id to { file, name, icon, configure }.
 */
Item {
    id: editor

    //% "Widget Management"
    Accessible.name: qsTrId("id-tiles-management")
    property var registry: ({})
    // the app icon of a tile for the add list: function(id) -> icon name
    // (TilesRing.appIcon); without it the registry's icon
    property var iconOf: null
    // the inactivity timeout runs (stock does not run it with accessibility on)
    property bool idleEnabled: true
    signal changed(var tiles)
    // the editing ended on this tile (an index of the list, -1: none)
    signal finished(int index)
    // the crown cancelled it: back to the watch face
    signal cancelled()
    // the "Edit widget" chip of the middle tile was pressed
    signal configureRequested(string tileId)

    property var shown: []
    readonly property var hidden: TE.hiddenOf(Object.keys(registry), shown)
    readonly property bool adding: addList.visible
    readonly property int maxTiles: TE.MAX_TILES

    // 0: the tile's size (scale 1.613) .. 1: the settled carousel
    property real zoom: 0
    readonly property real progress: zoom
    property bool closing: false
    property bool cancelling: false
    // the middle card is not a tile (Add new): the close fades instead of growing
    property bool fadeOut: false
    // names and delete buttons hide for 166 ms, then fade in over 100 ms
    property real namesOpacity: 1
    property bool touching: false

    readonly property real u: width / 384
    readonly property real itemSize: FP.itemSize(width)
    readonly property real pitch: FP.pitch(width)
    readonly property real ringWidth: 4 * u
    // as the face picker: the zoom's pivot is 4 dp above the middle and the
    // cards' centre is where the zoom lands it on the screen's middle
    readonly property real pivotY: height / 2 - FP.OFFSET_Y_DP * 2 * u
    readonly property real previewCy: pivotY + (height / 2 - pivotY) / FP.openScale(width)

    // the carousel's model: the tiles, then "Add new" (a ListModel, so a
    // removal, a move or an addition keeps the view where it is)
    ListModel { id: cards }
    readonly property alias carousel: carousel
    readonly property alias addList: addList
    readonly property alias dialog: dialog
    readonly property alias flyer: flyer
    readonly property alias bottomRow: bottomRow
    readonly property int centred: carousel.currentIndex
    readonly property bool onTile: centred >= 0 && centred < shown.length
    readonly property string centredId: onTile ? shown[centred] : ""
    readonly property bool centredConfigurable: onTile && registry[centredId] !== undefined && !!registry[centredId].configure
    readonly property bool arrowsOn: onTile && TE.arrowsVisible(shown.length)
    // while the cards scroll: no delete buttons
    readonly property bool scrolling: carousel.moving || carousel.flicking

    visible: false
    anchors.fill: parent

    function open(current, at) {
        stopAll()
        shown = current.slice()
        cards.clear()
        for (var i = 0; i < shown.length; i++)
            cards.append({ tileId: shown[i] })
        cards.append({ tileId: "" })
        addList.closeNow()
        dialog.close()
        closing = false
        cancelling = false
        fadeOut = false
        stage.opacity = 1
        stage.scale = 1
        flyId = ""
        flyer.visible = false
        bottomRow.shift = 0
        bottomRow.opacity = 1
        carousel.currentIndex = Math.max(0, Math.min(at, shown.length))
        carousel.positionViewAtIndex(carousel.currentIndex, ListView.Center)
        zoom = 0
        namesOpacity = 0
        visible = true
        openAnim.restart()
    }

    function stopAll() {
        openAnim.stop()
        exitAnim.stop()
        cancelAnim.stop()
        flyAnim.stop()
        tapTimer.stop()
    }

    /* End the editing on the middle tile: the editor grows to 1.613 in 300 ms
     * (0.4, 0, 0.2, 1) into the tile; names and buttons fade out in 150 ms. On
     * "Add new" there is no tile to grow into: it fades out. */
    function close() {
        if (!visible || closing)
            return
        tapTimer.stop()
        openAnim.stop()
        closing = true
        fadeOut = !onTile
        finished(TE.endIndex(carousel.currentIndex, shown.length))
        exitAnim.restart()
    }

    /* The crown button: cancel to the watch face (jif.java:196-209), from the
     * carousel, its dialog and the add list. false: the editor is not shown. */
    function crownPressed() {
        if (!visible)
            return false
        if (TE.crownAction() === "cancel")
            cancel()
        return true
    }

    function cancel() {
        if (!visible || cancelling)
            return
        openAnim.stop()
        exitAnim.stop()
        flyAnim.stop()
        tapTimer.stop()
        closing = true
        cancelling = true
        cancelled()
        cancelAnim.restart()
    }

    function finish() {
        stopAll()
        visible = false
        closing = false
        cancelling = false
        fadeOut = false
        zoom = 0
        stage.opacity = 1
        stage.scale = 1
        addList.closeNow()
        dialog.close()
        flyer.visible = false
        flyId = ""
    }

    // the add list's back (a swipe): true when there was a list to leave
    function back() {
        if (addList.visible) {
            addList.back()
            return true
        }
        return false
    }

    function save(list) {
        shown = list
        changed(list.slice())
    }

    // an arrow: the middle tile swaps with its neighbour, the first moved
    // left becomes the last (and the reverse); kept at once
    function moveCentred(by) {
        var i = carousel.currentIndex
        if (!onTile)
            return false
        var j = TE.moveTarget(i, by, shown.length)
        if (j === i)
            return false
        tapTimer.stop()
        var s = shown.slice()
        s.splice(j, 0, s.splice(i, 1)[0])
        cards.move(i, j, 1)
        save(s)
        carousel.currentIndex = j
        if (Math.abs(j - i) > 1)
            carousel.positionViewAtIndex(j, ListView.Center)
        Haptics.tick()
        return true
    }
    function remove(i) {
        if (i < 0 || i >= shown.length || closing)
            return false
        tapTimer.stop()
        var cur = carousel.currentIndex
        var s = shown.slice()
        s.splice(i, 1)
        cards.remove(i)
        save(s)
        carousel.currentIndex = TE.indexAfterRemove(cur, i, s.length)
        return true
    }

    // ---- the first frames ---------------------------------------------------
    ParallelAnimation {
        id: openAnim
        objectName: "eosTilesOpenAnim"
        NumberAnimation {
            target: editor; property: "zoom"; from: 0; to: 1
            duration: Motion.duration(FP.OPEN_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.duration(FP.NAMES_HIDDEN_MS) }
            NumberAnimation { target: editor; property: "namesOpacity"; to: 1; duration: Motion.duration(FP.NAMES_FADE_MS) }
        }
        onFinished: editor.namesOpacity = 1
    }
    // the way to a tile: the zoom back to 1.613 in 300 ms, names out in 150 ms
    ParallelAnimation {
        id: exitAnim
        objectName: "eosTilesExitAnim"
        NumberAnimation {
            target: editor; property: "zoom"; to: 0
            duration: Motion.duration(FP.CLOSE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation { target: editor; property: "namesOpacity"; to: 0; duration: Motion.duration(150) }
        NumberAnimation {
            target: stage; property: "opacity"; to: editor.fadeOut ? 0 : 1
            duration: editor.fadeOut ? Motion.duration(FP.CLOSE_MS) : 0
        }
        onFinished: editor.finish()
    }
    // the crown: 1 -> 0.25 in 350 ms (0.2, 0, 0.2, 1), alpha 1 -> 0 in 300 ms (0.4, 0, 1, 1)
    ParallelAnimation {
        id: cancelAnim
        objectName: "eosTilesCancelAnim"
        NumberAnimation {
            target: stage; property: "scale"; to: TE.CANCEL_SCALE
            duration: Motion.duration(TE.CANCEL_SCALE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: TE.CANCEL_SCALE_CURVE
        }
        NumberAnimation {
            target: stage; property: "opacity"; to: 0
            duration: Motion.duration(TE.CANCEL_ALPHA_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: TE.CANCEL_ALPHA_CURVE
        }
        onFinished: editor.finish()
    }

    // ---- the idle timeout: 15 s after the last touch -----------------------------
    Timer {
        id: idleTimer
        objectName: "eosTilesIdle"
        interval: TE.IDLE_MS
        running: editor.visible && !editor.closing && editor.zoom >= 1 && !editor.touching
                 && editor.idleEnabled && !flyAnim.running
        onTriggered: if (TE.idleAction() === "close") editor.close()
    }

    // everything the editor draws, shrunk by the cancel
    Item {
        id: stage
        objectName: "eosTilesStage"
        anchors.fill: parent
        transformOrigin: Item.Center

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
        }
        // nothing under the editor takes a touch
        MouseArea { anchors.fill: parent }

        // what a dialog shrinks: the carousel and the add list
        Item {
            id: behindItem
            anchors.fill: parent
            transformOrigin: Item.Center

            // ---- the carousel and the bottom row: one container that zooms -----
            Item {
                id: container
                objectName: "eosTilesContainer"
                anchors.fill: parent
                transform: Scale {
                    id: zoomScale
                    origin.x: editor.width / 2
                    origin.y: editor.pivotY
                    xScale: FP.zoomScale(editor.width, editor.zoom)
                    yScale: xScale
                }
                readonly property real scaleNow: zoomScale.xScale

                ListView {
                    id: carousel
                    objectName: "eosTilesList"
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - editor.pitch) / 2
                    preferredHighlightEnd: (width + editor.pitch) / 2
                    highlightMoveDuration: FP.SCROLL_MS
                    // the two cards each side are kept ready
                    cacheBuffer: 2.5 * editor.pitch
                    model: cards
                    interactive: editor.visible && editor.zoom >= 1 && !editor.closing && !addList.visible
                    onCurrentIndexChanged: if (editor.visible) Haptics.tick()
                    onMovementStarted: tapTimer.stop()

                    delegate: Item {
                        id: card
                        objectName: "eosTilesCard"
                        width: editor.pitch
                        height: carousel.height

                        readonly property bool isAdd: model.tileId === ""
                        readonly property string tileId: model.tileId
                        readonly property bool isCurrent: ListView.isCurrentItem
                        readonly property var entry: editor.registry[model.tileId]
                        // the distance of this card's middle from the middle of the view, px
                        readonly property real distance: (x - carousel.contentX + width / 2) - carousel.width / 2
                        // stock fades by the distance over the card's width; nothing is scaled
                        readonly property real cardAlpha: FP.itemAlpha(distance, width)
                        readonly property bool flying: editor.flyId !== "" && editor.flyId === tileId

                        // the tile's name along the top edge of the screen, with the card
                        CurvedTopText {
                            objectName: "eosTilesName"
                            width: editor.width
                            height: editor.height
                            x: (card.width - width) / 2
                            y: 0
                            //% "Add new"
                            text: (card.isAdd ? qsTrId("id-tiles-add-new")
                                              : (card.entry ? card.entry.name : card.tileId)) + localeManager.changesObserver
                            pixelSize: Theme.dp(FP.NAME_SIZE_DP)
                            maxSweep: FP.NAME_SWEEP
                            topMargin: Math.round(editor.height * FP.NAME_TOP_PERCENT / 100)
                            shadow: FP.NAME_SHADOW
                            color: Theme.color.onBackground
                            opacity: editor.namesOpacity
                        }

                        // the preview: the ring (4 px, #202124, outside the 238 px preview), the tile
                        Item {
                            id: preview
                            objectName: "eosTilesPreview"
                            width: editor.itemSize + 2 * editor.ringWidth
                            height: width
                            x: (card.width - width) / 2
                            y: editor.previewCy - height / 2
                            visible: !card.isAdd

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: FP.RING_COLOR
                            }
                            // while the tile loads: a disc; if it cannot: the stock text
                            Rectangle {
                                objectName: "eosTilesPlaceholder"
                                anchors.centerIn: parent
                                width: editor.itemSize
                                height: width
                                radius: width / 2
                                color: Theme.color.surfaceContainer
                                visible: tile.status !== Loader.Ready
                                Label {
                                    anchors.centerIn: parent
                                    width: parent.width * 0.7
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    visible: tile.status === Loader.Error
                                    //% "Preview unavailable"
                                    text: qsTrId("id-tiles-preview-unavailable") + localeManager.changesObserver
                                    color: Theme.color.onSurfaceVariant
                                }
                            }
                            // the tile itself, drawn at full size and shrunk; the cards beside the
                            // middle one load without stopping the frames
                            Loader {
                                id: tile
                                objectName: "eosTilesTile"
                                active: !card.isAdd && editor.visible
                                asynchronous: !card.isCurrent
                                width: editor.width
                                height: editor.height
                                anchors.centerIn: parent
                                scale: editor.itemSize / editor.width
                                visible: status === Loader.Ready && !card.flying
                                source: card.entry && card.entry.file ? Qt.resolvedUrl(card.entry.file.replace(/^tiles\//, "")) : ""
                                // it is a picture here: no taps reach it
                                enabled: false
                                onLoaded: if (item && item.preview !== undefined) item.preview = true
                            }
                            // the corners of the square tile, outside the round preview
                            RoundMask {
                                anchors.centerIn: parent
                                width: editor.itemSize
                                height: width
                                color: "#000000"
                                visible: tile.status === Loader.Ready && !card.flying
                            }
                            // a ring over the mask's edge (stock's border is outside the picture)
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: editor.ringWidth
                                border.color: FP.RING_COLOR
                            }
                        }

                        // Add new: a 60 dp colorPrimary round button with a 14 dp plus, no ring
                        Rectangle {
                            id: plus
                            objectName: "eosTilesAdd"
                            visible: card.isAdd
                            width: TE.ADD_BUTTON * editor.u
                            height: width
                            radius: width / 2
                            x: (card.width - width) / 2
                            y: editor.previewCy - height / 2
                            color: Theme.color.primary
                            Accessible.role: Accessible.Button
                            //% "Add widgets"
                            Accessible.name: qsTrId("id-tiles-add-widgets") + localeManager.changesObserver
                            // ic_management_ui_plus.xml: two 14 x 2 dp bars
                            Rectangle {
                                objectName: "eosTilesPlusH"
                                anchors.centerIn: parent
                                width: TE.PLUS * editor.u
                                height: TE.PLUS_BAR * editor.u
                                color: Theme.color.onPrimary
                            }
                            Rectangle {
                                objectName: "eosTilesPlusV"
                                anchors.centerIn: parent
                                width: TE.PLUS_BAR * editor.u
                                height: TE.PLUS * editor.u
                                color: Theme.color.onPrimary
                            }
                        }

                        // a tap: the middle tile ends the editing on it, a side tile scrolls to
                        // the middle first, "Add new" opens the list
                        MouseArea {
                            objectName: "eosTilesTap"
                            x: (card.width - width) / 2
                            y: editor.previewCy - height / 2
                            width: editor.itemSize + 2 * editor.ringWidth
                            height: width
                            onClicked: editor.tapItem(index)
                        }

                        // remove: a 32 dp round button at the preview's top-end corner, 4 dp in;
                        // hidden while the cards scroll
                        Rectangle {
                            id: del
                            objectName: "eosTilesDelete"
                            visible: !card.isAdd
                            width: TE.BUTTON * editor.u
                            height: width
                            radius: width / 2
                            x: preview.x + preview.width - TE.DELETE_INSET * editor.u - width
                            y: preview.y + TE.DELETE_INSET * editor.u
                            color: Theme.color.surfaceContainer
                            opacity: editor.scrolling ? 0 : editor.namesOpacity
                            Accessible.role: Accessible.Button
                            //% "Delete"
                            Accessible.name: qsTrId("id-tiles-delete") + localeManager.changesObserver
                            // ic_management_ui_delete.xml: a 16 x 2 dp minus
                            Rectangle {
                                objectName: "eosTilesMinus"
                                anchors.centerIn: parent
                                width: TE.MINUS_W * editor.u
                                height: TE.MINUS_H * editor.u
                                color: Theme.color.onSurfaceVariant
                            }
                            MouseArea {
                                objectName: "eosTilesDeleteArea"
                                anchors.centerIn: parent
                                // a finger-sized target (the 52 dp tap target of stock)
                                width: Math.max(parent.width, TE.BUTTON_TAP * editor.u)
                                height: width
                                enabled: del.visible && del.opacity > 0 && editor.zoom >= 1 && !editor.closing
                                onClicked: editor.remove(index)
                            }
                        }

                        // the cards beside the middle one fade towards the black (alpha 1 - 0.5 x distance / width)
                        Rectangle {
                            objectName: "eosTilesDim"
                            anchors.fill: parent
                            color: "#000000"
                            opacity: 1 - card.cardAlpha
                            visible: opacity > 0
                        }
                    }
                }

                // the bottom row: arrow, the chip's slot, arrow
                Item {
                    id: bottomRow
                    objectName: "eosTilesRow"
                    anchors.fill: parent
                    // the row slides up from 15 % of the height after a tile was added
                    property real shift: 0
                    y: shift

                    readonly property var geo: TE.row(editor.width, editor.height, editor.centredConfigurable, editor.arrowsOn)

                    Rectangle {
                        id: leftArrow
                        objectName: "eosTilesLeft"
                        width: TE.BUTTON * editor.u
                        height: width
                        radius: width / 2
                        x: bottomRow.geo.left.x
                        y: bottomRow.geo.arrowY
                        opacity: editor.arrowsOn ? 1 : 0
                        visible: opacity > 0
                        color: Theme.color.surfaceContainer
                        Behavior on x { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                        Behavior on y { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                        Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                        Accessible.role: Accessible.Button
                        //% "Move widget left"
                        Accessible.name: qsTrId("id-tiles-move-left") + localeManager.changesObserver
                        Icon {
                            anchors.centerIn: parent
                            name: "ios-arrow-back"
                            color: Theme.color.primary
                            width: parent.width * 0.6
                            height: width
                        }
                        MouseArea {
                            objectName: "eosTilesLeftArea"
                            anchors.centerIn: parent
                            // the two targets never overlap (the arrows are 94 px apart)
                            width: parent.width * 1.375
                            height: TE.BUTTON_TAP * editor.u
                            enabled: editor.arrowsOn && editor.zoom >= 1 && !editor.closing
                            onClicked: editor.moveCentred(-1)
                        }
                    }
                    // the chip's slot: always there, invisible unless the middle tile has settings
                    Rectangle {
                        id: chip
                        objectName: "eosTilesChip"
                        width: bottomRow.geo.chip.w
                        height: bottomRow.geo.chip.h
                        radius: height / 2
                        x: bottomRow.geo.chip.x
                        y: bottomRow.geo.chip.y
                        opacity: editor.centredConfigurable ? 1 : 0
                        visible: opacity > 0
                        color: Theme.color.primary
                        Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                        Accessible.role: Accessible.Button
                        //% "Edit widget"
                        Accessible.name: qsTrId("id-tiles-edit-widget") + localeManager.changesObserver
                        Icon {
                            anchors.centerIn: parent
                            name: "ios-create"
                            color: Theme.color.onPrimary
                            width: 48 * editor.u
                            height: width
                        }
                        MouseArea {
                            id: chipArea
                            objectName: "eosTilesChipArea"
                            anchors.fill: parent
                            enabled: editor.centredConfigurable && editor.zoom >= 1 && !editor.closing
                            onClicked: editor.configureRequested(editor.centredId)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "#000000"
                            opacity: chipArea.pressed ? 0.25 : 0
                        }
                    }
                    Rectangle {
                        id: rightArrow
                        objectName: "eosTilesRight"
                        width: TE.BUTTON * editor.u
                        height: width
                        radius: width / 2
                        x: bottomRow.geo.right.x
                        y: bottomRow.geo.arrowY
                        opacity: editor.arrowsOn ? 1 : 0
                        visible: opacity > 0
                        color: Theme.color.surfaceContainer
                        Behavior on x { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                        Behavior on y { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                        Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                        Accessible.role: Accessible.Button
                        //% "Move widget right"
                        Accessible.name: qsTrId("id-tiles-move-right") + localeManager.changesObserver
                        Icon {
                            anchors.centerIn: parent
                            name: "ios-arrow-forward"
                            color: Theme.color.primary
                            width: parent.width * 0.6
                            height: width
                        }
                        MouseArea {
                            objectName: "eosTilesRightArea"
                            anchors.centerIn: parent
                            width: parent.width * 1.375
                            height: TE.BUTTON_TAP * editor.u
                            enabled: editor.arrowsOn && editor.zoom >= 1 && !editor.closing
                            onClicked: editor.moveCentred(1)
                        }
                    }
                }
            }

            // the preview that flies from its cell in the add list to its card
            Item {
                id: flyer
                objectName: "eosTilesFlyer"
                visible: false
                z: 2
                property string file: ""
                Rectangle { anchors.fill: parent; radius: width / 2; color: FP.RING_COLOR }
                Loader {
                    id: flyTile
                    active: flyer.visible && flyer.file !== ""
                    width: editor.width
                    height: editor.height
                    anchors.centerIn: parent
                    scale: (flyer.width - 2 * editor.ringWidth) / editor.width
                    source: flyer.file === "" ? "" : Qt.resolvedUrl(flyer.file.replace(/^tiles\//, ""))
                    enabled: false
                    onLoaded: if (item && item.preview !== undefined) item.preview = true
                }
                RoundMask {
                    anchors.centerIn: parent
                    width: parent.width - 2 * editor.ringWidth
                    height: width
                    color: "#000000"
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: editor.ringWidth
                    border.color: FP.RING_COLOR
                }
            }

            TileAddList {
                id: addList
                objectName: "eosTilesAddList"
                z: 1
                registry: editor.registry
                tiles: editor.hidden
                iconOf: editor.iconOf
                onPicked: (id, cx, cy, size) => editor.addTile(id, cx, cy, size)
            }
        }

        // the dialog of a full or an exhausted carousel: one button with a check
        AlertDialog {
            id: dialog
            objectName: "eosTilesDialog"
            behind: behindItem
            buttons: "edge"
        }

        // the idle timeout's eyes: above everything and passive (the touch goes on
        // to the item under it)
        Item {
            anchors.fill: parent
            z: 2000
            PointHandler {
                acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
                onActiveChanged: editor.touching = active
            }
        }
    }

    // ---- taps and the add flow ----------------------------------------------
    function tapItem(index) {
        if (!visible || closing || zoom < 1 || index < 0 || index >= cards.count)
            return
        if (cards.get(index).tileId === "") {
            tapTimer.stop()
            addTapped()
            return
        }
        // the middle tile: now. A side tile scrolls to the middle, waits 200 ms, then goes on
        if (index === carousel.currentIndex) {
            close()
            return
        }
        carousel.currentIndex = index
        tapTimer.restart()
    }
    Timer {
        id: tapTimer
        objectName: "eosTilesTapTimer"
        interval: TE.TAP_SCROLL_MS + TE.TAP_WAIT_MS
        onTriggered: editor.close()
    }

    // "Add new": the list of the tiles left, or a dialog saying there are none / no room
    function addTapped() {
        switch (TE.addAction(shown.length, hidden.length)) {
        case "none":
            //% "All widgets in use"
            dialog.title = qsTrId("id-tiles-none-title")
            //% "All available widgets are in your carousel."
            dialog.text = qsTrId("id-tiles-none")
            dialog.open()
            break
        case "full":
            //% "Carousel is full"
            dialog.title = qsTrId("id-tiles-full-title")
            //% "To add a widget, please remove an existing one first."
            dialog.text = qsTrId("id-tiles-full")
            dialog.open()
            break
        default:
            addList.open()
        }
    }

    /* A tile picked in the add list goes last and is centred; its preview flies
     * from its cell to its card in 300 ms (0.4, 0, 0.2, 1), the list fades out
     * in 300 ms, the bottom row rises from 15 % of the height and fades in over
     * 300 ms after 150 ms. */
    property string flyId: ""
    function addTile(id, cx, cy, size) {
        if (!registry[id] || shown.indexOf(id) >= 0 || shown.length >= TE.MAX_TILES)
            return false
        var at = TE.addIndex(shown.length)
        var s = shown.slice()
        s.splice(at, 0, id)
        cards.insert(at, { tileId: id })
        save(s)
        carousel.currentIndex = at
        carousel.positionViewAtIndex(at, ListView.Center)
        Haptics.confirm()
        flyId = id
        flyer.file = registry[id].file
        flyer.x = cx - size / 2 - ringWidth
        flyer.y = cy - size / 2 - ringWidth
        flyer.width = size + 2 * ringWidth
        flyer.height = flyer.width
        flyer.visible = true
        bottomRow.shift = FP.ADD_ROW_FROM * height
        bottomRow.opacity = 0
        addList.fadeOut(Motion.duration(FP.ADD_LIST_FADE_MS))
        flyAnim.restart()
        return true
    }
    ParallelAnimation {
        id: flyAnim
        objectName: "eosTilesFlyAnim"
        NumberAnimation {
            target: flyer; property: "x"
            to: (editor.width - editor.itemSize) / 2 - editor.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "y"
            to: editor.previewCy - editor.itemSize / 2 - editor.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "width"; to: editor.itemSize + 2 * editor.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "height"; to: editor.itemSize + 2 * editor.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.duration(FP.ADD_ROW_DELAY_MS) }
            ParallelAnimation {
                NumberAnimation {
                    target: bottomRow; property: "shift"; to: 0
                    duration: Motion.duration(FP.ADD_ROW_MS)
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
                }
                NumberAnimation { target: bottomRow; property: "opacity"; to: 1; duration: Motion.duration(FP.ADD_ROW_MS) }
            }
        }
        onFinished: {
            flyer.visible = false
            editor.flyId = ""
            bottomRow.shift = 0
            bottomRow.opacity = 1
        }
    }
}
