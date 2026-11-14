/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQml.Models
import "complications"
import org.asteroid.controls
import org.asteroid.utils
import Nemo.Configuration
import "facepicker.js" as FP

/*
 * The watchface picker, as stock Wear OS (CP3A, SysUI managementui), opened
 * by a long press on the watchface: the face shrinks into a carousel of the
 * user's favourites (FaceFavourites) with an "Add new" item at the end, the
 * face on the watch in the middle; a swipe or the crown moves through them;
 * a tap on a face, the crown button or 15 s without a touch puts the centred
 * face on and the picker grows back into it. Under the faces a pencil chip
 * (apply, then edit) and two arrows that move the face in the list; each face
 * has a delete button; "Add new" opens the list of every installed face
 * (FaceAddList). Numbers are stock's (facepicker.js), on the 384 px screen.
 *
 * The picker covers the face from the first frame (nothing fades): the whole
 * carousel starts at scale 384 / 238 = 1.613, where the centre preview, a
 * snapshot of the live face, is exactly the face, and shrinks to 1 in 266 ms.
 */
Item {
    id: picker
    anchors.fill: parent

    // the favourites (FaceLayer's FaceFavourites) and the home screen's face
    property QtObject store: null
    property Item liveFace: null
    property QtObject sources: null
    // the face file on the home screen (kept for callers of the old picker)
    property string current: ""
    // the display is on (not asleep, not the always-on screen)
    property bool awake: true

    readonly property real u: width / 384
    readonly property string previewFolder: "file:///usr/share/asteroid-launcher/watchfaces-preview/182/"
    // the cached previews (facePreviews, launcher C++), or none
    readonly property var cache: typeof facePreviews !== "undefined" ? facePreviews : null

    // 0: the face's size (scale 1.613) .. 1: the settled carousel
    property real zoom: 0
    readonly property real progress: zoom
    property bool shown: false
    property bool closing: false
    // the face is being snapshotted before the picker shows
    property bool opening: false
    visible: shown

    signal opened()
    signal closed()

    // the display went off before the snapshot came back: this opening is over (a wake-up is a new long press)
    onAwakeChanged: if (!awake && opening) opening = false

    // sizes (px)
    readonly property real itemSize: FP.itemSize(width)
    readonly property real pitch: FP.pitch(width)
    readonly property real ringWidth: 4 * u
    // the centre of the previews: the pivot of the zoom is 4 dp above the middle (184), and the
    // preview's centre is where the zoom brings it exactly onto the face's centre (192 - 8 / 1.613)
    readonly property real pivotY: height / 2 - FP.OFFSET_Y_DP * 2 * u
    readonly property real previewCy: pivotY + (height / 2 - pivotY) / FP.openScale(width)
    readonly property real chipY: height - 10 * u - 64 * u
    readonly property real arrowY: chipY - 26 * u

    // names and delete buttons hide for 166 ms, then fade in over 100 ms
    property real namesOpacity: 1

    // the snapshot of the live face the picker opened over
    property string liveUrl: ""
    property var liveResult: null
    // a preview file was written
    property int previewVersion: 0

    // ---- the list of the carousel (ListModel: a move keeps the delegates) ------
    ListModel { id: faceModel }
    property int count: faceModel.count
    property int centredIndex: -1
    property string centredFid: ""
    property bool centredAdd: false
    readonly property bool centredIsCurrent: store !== null && centredFid !== "" && centredFid === store.currentId

    function updateCentred() {
        var i = faces.currentIndex
        centredIndex = i
        if (i < 0 || i >= faceModel.count) {
            centredFid = ""
            centredAdd = false
            return
        }
        var e = faceModel.get(i)
        centredFid = e.isAdd ? "" : e.fid
        centredAdd = e.isAdd
    }

    // the ListModel follows the store's favourites (then the Add new item): moves, inserts, removes
    function sync() {
        var want = []
        if (store)
            for (var k = 0; k < store.entries.length; k++)
                want.push(store.entries[k])
        want.push({ id: "", file: "", add: true })
        for (var i = 0; i < want.length; i++) {
            var w = want[i]
            var wid = w.add ? "" : w.id
            if (i < faceModel.count && faceModel.get(i).fid === wid && faceModel.get(i).isAdd === (w.add === true))
                continue
            var at = -1
            for (var j = i + 1; j < faceModel.count; j++)
                if (faceModel.get(j).fid === wid && faceModel.get(j).isAdd === (w.add === true)) {
                    at = j
                    break
                }
            if (at >= 0)
                faceModel.move(at, i, 1)
            else
                faceModel.insert(i, { fid: wid, file: w.file, isAdd: w.add === true })
        }
        while (faceModel.count > want.length)
            faceModel.remove(faceModel.count - 1)
        updateCentred()
    }
    Connections {
        target: picker.store
        function onEntriesChanged() { picker.sync() }
    }
    Component.onCompleted: sync()

    function indexOfFid(id) {
        for (var i = 0; i < faceModel.count; i++)
            if (!faceModel.get(i).isAdd && faceModel.get(i).fid === id)
                return i
        return -1
    }
    function positionAt(id) {
        var i = indexOfFid(id)
        if (i < 0)
            i = 0
        faces.currentIndex = i
        faces.positionViewAtIndex(i, ListView.Center)
        updateCentred()
    }

    // ---- opening and closing ---------------------------------------------------
    // the view the crown and the idle timer act on
    readonly property string view: options.visible ? "editor" : (addList.visible ? "add" : "carousel")

    function open() {
        if (!store || shown || opening)
            return
        sync()
        options.visible = false
        addList.closeNow()
        exitAnim.stop()
        closing = false
        picker.opacity = 1
        positionAt(store.currentId)
        // a snapshot of the face the carousel opens over: the centre preview, exactly the face
        liveUrl = ""
        liveResult = null
        opening = true
        var started = false
        if (liveFace && liveFace.grabToImage)
            started = liveFace.grabToImage(function (r) {
                if (!picker.opening)
                    return
                picker.liveResult = r
                picker.liveUrl = r.url
                picker.begin()
            })
        if (!started)
            begin()
    }
    function begin() {
        opening = false
        zoom = 0
        namesOpacity = 0
        shown = true
        openAnim.restart()
    }

    ParallelAnimation {
        id: openAnim
        objectName: "eosFaceOpenAnim"
        NumberAnimation {
            target: picker; property: "zoom"; from: 0; to: 1
            duration: Motion.duration(FP.OPEN_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        SequentialAnimation {
            PauseAnimation { duration: Motion.duration(FP.NAMES_HIDDEN_MS) }
            NumberAnimation { target: picker; property: "namesOpacity"; to: 1; duration: Motion.duration(FP.NAMES_FADE_MS) }
        }
        onFinished: {
            picker.namesOpacity = 1
            picker.opened()
            picker.saveCurrent()
        }
    }

    // the face on the watch, snapshotted at the preview size, for the next time (a file per favourite)
    function saveCurrent() {
        if (!cache || !liveFace || !liveFace.grabToImage || !store || store.currentId === "")
            return
        var p = cache.path(store.currentId)
        if (p === "")
            return
        liveFace.grabToImage(function (r) {
            r.saveToFile(p)
            picker.previewVersion++
        }, Qt.size(itemSize, itemSize))
    }

    // the exit: the carousel grows to 1.613 in 300 ms, the centre preview becomes the face, then the
    // picker goes. `fade` when the centred preview is not the face on the watch (nothing to grow into).
    function exit(fade) {
        openAnim.stop()
        opening = false
        closing = true
        fadeOut = fade
        exitAnim.restart()
    }
    property bool fadeOut: false
    ParallelAnimation {
        id: exitAnim
        objectName: "eosFaceExitAnim"
        NumberAnimation {
            target: picker; property: "zoom"; to: 0
            duration: Motion.duration(FP.CLOSE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: picker; property: "opacity"; to: picker.fadeOut ? 0 : 1
            duration: picker.fadeOut ? Motion.duration(FP.CLOSE_MS) : 0
        }
        onFinished: picker.finish()
    }
    function finish() {
        shown = false
        closing = false
        opening = false
        zoom = 0
        picker.opacity = 1
        liveResult = null
        liveUrl = ""
        addList.closeNow()
        options.visible = false
        flyer.visible = false
        flyId = ""
        closed()
        // the face on the watch, as it looks now (a face just put on, or edited): its picture for the next time
        if (awake)
            Qt.callLater(saveCurrent)
    }

    // gone at once (the display went off, an application came up)
    function closeNow() {
        openAnim.stop()
        exitAnim.stop()
        tapTimer.stop()
        flyAnim.stop()
        opening = false
        if (shown || closing)
            finish()
    }

    // closed without a change (the side button, the crown on "Add new", the picker's own timeout over the add list)
    function dismiss() {
        if (opening) {
            opening = false
            return
        }
        if (!shown || closing)
            return
        tapTimer.stop()
        addList.closeNow()
        options.visible = false
        exit(!centredIsCurrent)
    }
    function close() { dismiss() }

    // a face is chosen: it goes on the watch now, the picker grows into it
    function choose(id) {
        if (!shown || closing || !store || store.indexOf(id) < 0)
            return
        tapTimer.stop()
        Haptics.confirm()
        store.choose(id)
        exit(false)
    }

    // the crown button; false when the picker leaves it to the home screen (it then closes the picker)
    function crownPressed() {
        if (!shown || closing)
            return true
        switch (FP.crownAction(view, centredAdd ? "add" : centredFid)) {
        case "back":
            addList.back()
            return true
        case "editor":
            return back()
        case "apply":
            choose(centredFid)
            return true
        default:
            dismiss()
            return true
        }
    }

    // ---- the idle timer: 15 s after the last finger lift (not while touching, not in the editor) ----
    property bool touching: false
    // (above everything and passive: the touch goes on to the item under it. A handler of the picker's own
    // item would see nothing that a MouseArea below has taken.)
    Item {
        anchors.fill: parent
        z: 100
        PointHandler {
            acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
            onActiveChanged: picker.touching = active
        }
    }
    Timer {
        id: idleTimer
        objectName: "eosFaceIdle"
        interval: FP.IDLE_MS
        running: picker.shown && !picker.closing && picker.zoom >= 1 && !picker.touching && picker.awake
                 && !options.visible && !flyAnim.running
        onTriggered: picker.idleExpired()
    }
    function idleExpired() {
        var a = FP.idleAction(view, centredAdd ? "add" : centredFid)
        if (a === "apply")
            choose(centredFid)
        else if (a === "close")
            dismiss()
    }

    // ---- what is under the picker ------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }
    // nothing under the picker takes a touch
    MouseArea {
        anchors.fill: parent
    }

    // ---- the carousel and the bottom row, one container that zooms ---------------
    Item {
        id: container
        objectName: "eosFaceContainer"
        anchors.fill: parent
        transform: Scale {
            id: zoomScale
            origin.x: picker.width / 2
            origin.y: picker.pivotY
            xScale: FP.zoomScale(picker.width, picker.zoom)
            yScale: xScale
        }
        readonly property real scaleNow: zoomScale.xScale

        ListView {
            id: faces
            objectName: "eosFaceList"
            anchors.fill: parent
            orientation: ListView.Horizontal
            // one face at a time, the current one in the middle; the crown steps through them (RotaryInput)
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - picker.pitch) / 2
            preferredHighlightEnd: (width + picker.pitch) / 2
            highlightMoveDuration: FP.SCROLL_MS
            // the two faces each side are kept ready (Qt makes an item once its start is inside the buffer)
            cacheBuffer: 2.5 * picker.pitch
            model: faceModel
            interactive: picker.shown && picker.zoom >= 1 && !picker.closing && !addList.visible && !options.visible
            onCurrentIndexChanged: picker.updateCentred()
            onMovementStarted: tapTimer.stop()

            delegate: Item {
                id: cell
                objectName: "eosFaceCell"
                width: picker.pitch
                height: faces.height

                readonly property string fid: model.fid
                readonly property string file: model.file
                readonly property bool isAdd: model.isAdd
                // the distance of the middle of this item from the middle of the view, px
                readonly property real distance: (x - faces.contentX + width / 2) - faces.width / 2
                // stock fades by the distance over the item's width; nothing is scaled
                readonly property real itemAlpha: FP.itemAlpha(distance, width)
                // the move of the arrows (the lift) and the name that fades back in after it
                property real lift: 1
                property real nameLift: 1
                readonly property bool flying: picker.flyId !== "" && picker.flyId === fid
                function runLift() { liftAnim.restart() }

                SequentialAnimation {
                    id: liftAnim
                    objectName: "eosFaceLiftAnim"
                    ParallelAnimation {
                        NumberAnimation {
                            target: cell; property: "lift"; to: FP.LIFT_SCALE
                            duration: Motion.duration(FP.LIFT_MS)
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.4, 0, 1, 1, 1, 1]
                        }
                        SequentialAnimation {
                            PropertyAction { target: cell; property: "nameLift"; value: 0 }
                            PauseAnimation { duration: Motion.duration(FP.LIFT_MS) }
                            PropertyAction { target: cell; property: "nameLift"; value: 1 }
                        }
                    }
                    NumberAnimation {
                        target: cell; property: "lift"; to: 1
                        duration: Motion.duration(FP.SETTLE_MS)
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.linearOutSlowIn
                    }
                }

                // the name along the top edge of the screen, with the item
                CurvedTopText {
                    objectName: "eosFaceName"
                    width: picker.width
                    height: picker.height
                    x: (cell.width - width) / 2
                    y: 0
                    //% "Add new"
                    text: cell.isAdd ? qsTrId("id-face-add-new") + localeManager.changesObserver : FP.displayName(cell.file)
                    pixelSize: Theme.dp(FP.NAME_SIZE_DP)
                    maxSweep: FP.NAME_SWEEP
                    topMargin: Math.round(picker.height * FP.NAME_TOP_PERCENT / 100)
                    shadow: FP.NAME_SHADOW
                    color: Theme.color.onBackground
                    opacity: picker.namesOpacity * cell.nameLift
                }

                // the preview: a ring (4 px, #202124, outside the 238 px preview), the face's picture
                Item {
                    id: preview
                    objectName: "eosFacePreview"
                    width: picker.itemSize + 2 * picker.ringWidth
                    height: width
                    x: (cell.width - width) / 2
                    y: picker.previewCy - height / 2
                    scale: cell.lift
                    visible: !cell.isAdd

                    Rectangle {
                        objectName: "eosFaceRing"
                        anchors.fill: parent
                        radius: width / 2
                        color: FP.RING_COLOR
                    }
                    // while a picture loads: a #32000000 disc
                    Rectangle {
                        objectName: "eosFacePlaceholder"
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        radius: width / 2
                        color: FP.PLACEHOLDER
                        visible: !shipped.ready && !shot.ready
                    }
                    // the shipped picture, then how the face last looked on this watch over it
                    Image {
                        id: shipped
                        objectName: "eosFaceShipped"
                        readonly property bool ready: status === Image.Ready
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        sourceSize.width: 182
                        sourceSize.height: 182
                        source: cell.isAdd ? "" : picker.previewFolder + FP.stemOf(cell.file) + ".png"
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: cell.flying ? 0 : 1
                    }
                    Image {
                        id: shot
                        objectName: "eosFaceShot"
                        readonly property bool ready: status === Image.Ready
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        // the face on the watch: the snapshot taken at open; the others: the cached file
                        source: {
                            if (cell.isAdd)
                                return ""
                            if (picker.store && cell.fid === picker.store.currentId && picker.liveUrl !== "")
                                return picker.liveUrl
                            picker.previewVersion
                            return picker.cache ? picker.cache.url(cell.fid) : ""
                        }
                        sourceSize.width: 384
                        sourceSize.height: 384
                        cache: false
                        asynchronous: false
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        opacity: cell.flying ? 0 : 1
                    }
                    // the corners of the square snapshot, outside the round preview
                    RoundMask {
                        objectName: "eosFaceMask"
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        color: "#000000"
                        visible: shot.ready && !cell.flying
                    }
                    // a ring over the mask's edge (stock's border is outside the picture)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: picker.ringWidth
                        border.color: FP.RING_COLOR
                    }
                }

                // Add new: a 60 dp colorPrimary round button with a plus
                Rectangle {
                    id: plus
                    objectName: "eosFaceAdd"
                    visible: cell.isAdd
                    width: 120 * picker.u
                    height: width
                    radius: width / 2
                    x: (cell.width - width) / 2
                    y: picker.previewCy - height / 2
                    color: Theme.color.primary
                    Accessible.role: Accessible.Button
                    //% "Add watch face"
                    Accessible.name: qsTrId("id-face-add-more") + localeManager.changesObserver
                    Icon {
                        anchors.centerIn: parent
                        name: "ios-add"
                        color: Theme.color.onPrimary
                        width: parent.width * 0.5
                        height: width
                    }
                }

                // a tap: a face puts itself on (a side face scrolls to the middle first); Add new opens the list
                MouseArea {
                    objectName: "eosFaceTap"
                    x: (cell.width - width) / 2
                    y: picker.previewCy - height / 2
                    width: picker.itemSize + 2 * picker.ringWidth
                    height: width
                    onClicked: picker.tapItem(index)
                }

                // delete: 32 dp round button at the preview's top-end corner, 4 dp in
                Rectangle {
                    id: del
                    objectName: "eosFaceDelete"
                    visible: !cell.isAdd && picker.count > 2
                    width: 64 * picker.u
                    height: width
                    radius: width / 2
                    x: preview.x + preview.width - 8 * picker.u - width
                    y: preview.y + 8 * picker.u
                    color: Theme.color.surfaceContainer
                    opacity: picker.namesOpacity
                    Accessible.role: Accessible.Button
                    //% "Delete"
                    Accessible.name: qsTrId("id-face-delete") + localeManager.changesObserver
                    Icon {
                        anchors.centerIn: parent
                        name: "ios-trash-outline"
                        color: Theme.color.onSurfaceVariant
                        width: parent.width * 0.55
                        height: width
                    }
                    MouseArea {
                        anchors.centerIn: parent
                        // a finger-sized target (52 dp tap target of stock)
                        width: Math.max(parent.width, 104 * picker.u)
                        height: width
                        enabled: del.visible && picker.zoom >= 1
                        onClicked: picker.deleteFace(cell.fid)
                    }
                }

                // the faces beside the middle one fade towards the black (alpha 1 - 0.5 x distance / width)
                Rectangle {
                    objectName: "eosFaceDim"
                    anchors.fill: parent
                    color: "#000000"
                    opacity: 1 - cell.itemAlpha
                    visible: opacity > 0
                }
            }
        }

        // the bottom row: arrow, chip, arrow
        Item {
            id: bottomRow
            objectName: "eosFaceRow"
            anchors.fill: parent
            // the row slides up from 15 % of the height after a face was added
            property real shift: 0
            y: shift
            opacity: 1

            readonly property bool onFace: picker.centredFid !== "" && !picker.centredAdd
            readonly property bool leftOn: onFace && picker.centredIndex > 0
            readonly property bool rightOn: onFace && store !== null && picker.centredIndex < store.entries.length - 1
            readonly property real step: 72 * picker.u
            readonly property real rowW: (leftOn ? step : 0) + 104 * picker.u + (rightOn ? step : 0)
            readonly property real chipX: (picker.width - rowW) / 2 + (leftOn ? step : 0)
            property QtObject store: picker.store

            Rectangle {
                id: leftArrow
                objectName: "eosFaceLeft"
                width: 64 * picker.u
                height: width
                radius: width / 2
                y: picker.arrowY
                x: bottomRow.leftOn ? bottomRow.chipX - bottomRow.step : bottomRow.chipX + 20 * picker.u
                opacity: bottomRow.leftOn ? 1 : 0
                visible: opacity > 0
                color: Theme.color.surfaceContainer
                Behavior on x { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                Accessible.role: Accessible.Button
                //% "Move watchface position left in the list"
                Accessible.name: qsTrId("id-face-move-left") + localeManager.changesObserver
                Icon {
                    anchors.centerIn: parent
                    name: "ios-arrow-back"
                    color: Theme.color.primary
                    width: parent.width * 0.6
                    height: width
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: bottomRow.leftOn && picker.zoom >= 1
                    onClicked: picker.moveCentred(-1)
                }
            }
            Rectangle {
                id: chip
                objectName: "eosFaceChip"
                width: 104 * picker.u
                height: 64 * picker.u
                radius: height / 2
                y: picker.chipY
                x: bottomRow.chipX
                opacity: bottomRow.onFace ? 1 : 0
                visible: opacity > 0
                color: Theme.color.primary
                Behavior on x { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                Accessible.role: Accessible.Button
                //% "Edit watch face"
                Accessible.name: qsTrId("id-face-edit") + localeManager.changesObserver
                Icon {
                    anchors.centerIn: parent
                    name: "ios-create"
                    color: Theme.color.onPrimary
                    width: 48 * picker.u
                    height: width
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    enabled: bottomRow.onFace && picker.zoom >= 1
                    onClicked: picker.customize()
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
                objectName: "eosFaceRight"
                width: 64 * picker.u
                height: width
                radius: width / 2
                y: picker.arrowY
                x: bottomRow.rightOn ? bottomRow.chipX + 104 * picker.u + 8 * picker.u : bottomRow.chipX + 20 * picker.u
                opacity: bottomRow.rightOn ? 1 : 0
                visible: opacity > 0
                color: Theme.color.surfaceContainer
                Behavior on x { NumberAnimation { duration: Motion.duration(FP.BUTTONS_CHANGE_MS); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy } }
                Behavior on opacity { NumberAnimation { duration: Motion.duration(FP.BUTTONS_FADE_MS) } }
                Accessible.role: Accessible.Button
                //% "Move watchface position right in the list"
                Accessible.name: qsTrId("id-face-move-right") + localeManager.changesObserver
                Icon {
                    anchors.centerIn: parent
                    name: "ios-arrow-forward"
                    color: Theme.color.primary
                    width: parent.width * 0.6
                    height: width
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: bottomRow.rightOn && picker.zoom >= 1
                    onClicked: picker.moveCentred(1)
                }
            }
        }
    }

    // ---- taps, delete, move -------------------------------------------------------
    property string tapId: ""
    function tapItem(index) {
        if (!shown || closing || zoom < 1 || index < 0 || index >= faceModel.count)
            return
        var e = faceModel.get(index)
        if (e.isAdd) {
            tapTimer.stop()
            addList.open()
            return
        }
        // the middle face: now. A side face scrolls to the middle (250 ms), waits 200 ms, then goes on
        if (index === faces.currentIndex) {
            choose(e.fid)
            return
        }
        tapId = e.fid
        faces.currentIndex = index
        tapTimer.restart()
    }
    Timer {
        id: tapTimer
        objectName: "eosFaceTapTimer"
        interval: FP.SCROLL_MS + FP.TAP_WAIT_MS
        onTriggered: picker.choose(picker.tapId)
    }

    function deleteFace(id) {
        if (!store || !shown || closing)
            return false
        tapTimer.stop()
        return store.remove(id)
    }

    // an arrow: the centred face swaps with its neighbour, saved at once; it lifts and settles
    function moveCentred(dir) {
        var id = centredFid
        if (id === "" || !store || !store.move(id, dir))
            return false
        tapTimer.stop()
        sync()
        // the delegate that shows the face, by its id: the view's own index lags a move by a turn
        var kids = faces.contentItem.children
        for (var k = 0; k < kids.length; k++)
            if (kids[k].objectName === "eosFaceCell" && !kids[k].isAdd && kids[k].fid === id)
                kids[k].runLift()
        return true
    }

    // ---- Add new: the list of every installed face --------------------------------
    // a face picked in the list becomes the last favourite and is focused, not put on; its preview
    // flies into the slot (300 ms), the list fades out (300 ms), the bottom row slides up from 15 % of
    // the height (150 ms later, 300 ms)
    property string flyId: ""
    function addFace(file, cx, cy, size) {
        if (!store)
            return
        var id = store.add(file)
        sync()
        var i = indexOfFid(id)
        faces.currentIndex = i
        faces.positionViewAtIndex(i, ListView.Center)
        updateCentred()
        flyId = id
        flyer.file = file
        flyer.x = cx - size / 2 - ringWidth
        flyer.y = cy - size / 2 - ringWidth
        flyer.width = size + 2 * ringWidth
        flyer.height = flyer.width
        flyer.visible = true
        bottomRow.shift = FP.ADD_ROW_FROM * height
        bottomRow.opacity = 0
        addList.fadeOut(Motion.duration(FP.ADD_LIST_FADE_MS))
        flyAnim.restart()
    }
    Item {
        id: flyer
        objectName: "eosFaceFlyer"
        visible: false
        z: 2
        property string file: ""
        Rectangle { anchors.fill: parent; radius: width / 2; color: FP.RING_COLOR }
        Image {
            anchors.centerIn: parent
            width: parent.width - 2 * picker.ringWidth
            height: width
            sourceSize.width: 182
            sourceSize.height: 182
            source: flyer.file === "" ? "" : picker.previewFolder + FP.stemOf(flyer.file) + ".png"
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }
    ParallelAnimation {
        id: flyAnim
        objectName: "eosFaceFlyAnim"
        NumberAnimation {
            target: flyer; property: "x"
            to: (picker.width - picker.itemSize) / 2 - picker.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "y"
            to: picker.previewCy - picker.itemSize / 2 - picker.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "width"; to: picker.itemSize + 2 * picker.ringWidth
            duration: Motion.duration(FP.ADD_FLY_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: flyer; property: "height"; to: picker.itemSize + 2 * picker.ringWidth
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
            picker.flyId = ""
            bottomRow.shift = 0
            bottomRow.opacity = 1
        }
    }

    FaceAddList {
        id: addList
        objectName: "eosFaceAddList"
        z: 1
        faces: picker.store ? picker.store.installed : []
        previewFolder: picker.previewFolder
        onPicked: (file, cx, cy, size) => picker.addFace(file, cx, cy, size)
    }

    // ---- the editor: Customize of stock's picker, a chip that applies, then edits --------
    /* Wear OS's face editor: under the faces the pencil chip. Its pages,
     * swiped through as stock's: the options every bundled face follows
     * (the launcher applies them by the faces' item names, see
     * WatchfaceReloader.applyFaceOptions), then the face's complications
     * when it has slots (FaceEditor). The chip on another face than the
     * one worn puts it on first, as stock edits the face it applies. The
     * options are the favourite's own (FaceStyle). */
    FaceStyle {
        id: pickerStyle
        faceId: picker.store ? picker.store.currentId : ""
    }

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
        var id = centredFid
        if (id !== "" && store && id !== store.currentId)
            store.choose(id)
        pages.currentIndex = 0
        pages.positionViewAtBeginning()
        options.visible = true
    }

    Item {
        id: options
        objectName: "eosFaceEditor"
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
                                objectName: "eosFaceOptDate"
                                width: parent.width
                                height: options.rowHeight
                                //% "Date"
                                text: qsTrId("id-face-show-date")
                                checked: pickerStyle.showDate
                                onCheckedChanged: if (pickerStyle.showDate !== checked) pickerStyle.set("show-date", checked)
                            }
                            LabeledSwitch {
                                objectName: "eosFaceOptSeconds"
                                width: parent.width
                                height: options.rowHeight
                                //% "Seconds"
                                text: qsTrId("id-face-show-seconds")
                                checked: pickerStyle.showSeconds
                                onCheckedChanged: if (pickerStyle.showSeconds !== checked) pickerStyle.set("show-seconds", checked)
                            }
                            OptionCycler {
                                objectName: "eosFaceOptAmbient"
                                width: parent.width
                                height: options.rowHeight
                                //% "Always-on"
                                text: qsTrId("id-face-ambient")
                                valueArray: options.styleLabels
                                currentValue: options.styleLabels[Math.max(0, options.styleValues.indexOf(pickerStyle.ambientStyle))]
                                onValueChanged: (value) => pickerStyle.set("ambient-style", options.styleValues[options.styleLabels.indexOf(value)])
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
                                    color: Theme.color.primary
                                    opacity: done.pressed ? 0.75 : 1
                                }
                                Label {
                                    anchors.centerIn: parent
                                    //% "Done"
                                    text: qsTrId("id-tiles-done") + localeManager.changesObserver
                                    color: Theme.color.onPrimary
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
                    // the favourite's id: its complications' key (ComplicationSources.faceName of a bare id)
                    faceUrl: picker.store ? picker.store.currentId : ""
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
