/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQml.Models
import QtQuick.Shapes
import "complications/faceeditor.js" as FE
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
 * carousel starts at scale 384 / 238 = 1.613, where the centre preview covers
 * the screen, and settles as the Wear OS 6 emulator's (M11, N61-36) on two
 * underdamped springs: the scale to 1 (zeta 0.67, k 627) and the previews'
 * centre from the middle up to y 171 (zeta 0.53, k 700). Leaving without a
 * change is a cut to the live face. Every preview, the face on the watch
 * included, is the face drawn at 10:09 (N61-35): an eos face's picture drawn
 * for the favourite by FacePreviewRenderer (its style and complications), an
 * upstream face's shipped picture (watchfaces-preview/384); there is no
 * snapshot of the live face, so the open starts at once.
 */
Item {
    id: picker
    anchors.fill: parent

    // the favourites (FaceLayer's FaceFavourites) and the home screen's face (where the wallpaper lies against it)
    property QtObject store: null
    property Item liveFace: null
    property QtObject sources: null
    // the face file on the home screen (kept for callers of the old picker)
    property string current: ""
    // the display is on (not asleep, not the always-on screen)
    property bool awake: true

    readonly property real u: width / 384
    // the shipped 10:09 pictures: 182 px for the Add new list, 384 px for the carousel (sharp in the open's
    // first frame, where the centre preview covers the screen)
    property string previewFolder: "file:///usr/share/asteroid-launcher/watchfaces-preview/182/"
    property string pictureFolder: "file:///usr/share/asteroid-launcher/watchfaces-preview/384/"
    // the cached pictures (facePreviews, launcher C++, written by FacePreviewRenderer), or none
    readonly property var cache: typeof facePreviews !== "undefined" ? facePreviews : null

    /* The open's two driven values (N61-36): the previews' scale, FP.openScale (the face's size) .. 1 (the
     * carousel), on scaleSpring, and the y of their centre, the middle of the screen .. previewCy, on ySpring.
     * Choosing a face drives them back (growAnim). */
    property real previewScale: 1
    property real previewY: 0
    // 0: the face's size .. 1: the settled carousel (the scale spring's normalised value: above 1 while it
    // overshoots)
    readonly property real zoom: FP.openProgress(width, previewScale)
    // the open came to the carousel's size: the carousel takes touches and the crown, the idle timer runs
    property bool arrived: false
    // for the home screen: 1 while the picker covers the face (from the open's first crossing of 1), 0 when
    // gone; the grow into a chosen face takes it down with the scale
    readonly property real progress: !shown ? 0 : arrived ? 1 : Math.max(0, Math.min(1, zoom))
    onZoomChanged: if (shown && !closing && !arrived && zoom >= 1) arrived = true
    property bool shown: false
    property bool closing: false
    visible: shown

    signal opened()
    signal closed()

    // sizes (px)
    readonly property real itemSize: FP.itemSize(width)
    readonly property real pitch: FP.pitch(width)
    readonly property real ringWidth: 4 * u
    // the centre of the previews at rest: y 171 (the emulator's ring y 48-294, S15)
    readonly property real previewCy: FP.previewCy(height)
    readonly property real chipY: height - 10 * u - 64 * u
    readonly property real arrowY: chipY - 26 * u

    // the names, the chip and the arrows (and the delete buttons) hide for 100 ms after the cut, then fade in
    // over 50 ms
    property real namesOpacity: 1

    // the wallpaper the faces are drawn over (MainScreen's), its snapshot taken at the open (the only grab: the
    // picker does not wait for it), and where it lies against the face (fractions of the face's size:
    // MainScreen's is 110 %, centred)
    property Item background: null
    property string backgroundUrl: ""
    property var backgroundResult: null
    property rect backgroundRect: Qt.rect(0, 0, 1, 1)
    // a picture was written (FacePreviewRenderer.version): the pictures are read again
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
    Component.onCompleted: {
        rowInstant = true
        sync()
        rowInstant = false
        ySpring.snapTo(previewCy)
    }

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
    // the view the crown and the idle timer act on ("editor" is gone: the editor is its own layer, FaceEditor)
    readonly property string view: addList.visible ? "add" : "carousel"

    function open() {
        if (!store || shown)
            return
        rowInstant = true
        sync()
        rowInstant = false
        editing = false
        hideTimer.stop()
        addList.closeNow()
        growAnim.stop()
        closing = false
        rowInstant = true
        positionAt(store.currentId)
        bottomRow.applyRow()
        rowInstant = false
        // the pictures are there already (drawn at 10:09, not at the open): the carousel shows at once, and the
        // wallpaper under them comes with its snapshot
        grabBackground()
        // the cut: the centre preview at the face's size, on the face; 30 ms later the two springs (Reduce
        // animations: at rest at once)
        arrived = false
        scaleSpring.snapTo(FP.openScale(width))
        ySpring.snapTo(height / 2)
        namesOpacity = 0
        shown = true
        if (Motion.animationScale > 0)
            openHold.restart()
        else
            startSprings()
        openAnim.restart()
    }
    function startSprings() {
        scaleSpring.animateTo(1, 0)
        ySpring.animateTo(previewCy, 0)
    }
    // the cut's frame stays 30 ms before the springs move (M11)
    Timer {
        id: openHold
        objectName: "eosFaceOpenHold"
        interval: Motion.duration(FP.OPEN_HOLD_MS)
        onTriggered: picker.startSprings()
    }
    // the wallpaper under the pictures (an eos face is drawn over it): snapshotted now, shown when it comes
    function grabBackground() {
        backgroundUrl = ""
        backgroundResult = null
        if (!liveFace || liveFace.width <= 0 || !background || !background.visible || !background.grabToImage)
            return
        var tl = background.mapToItem(liveFace, 0, 0)
        var br = background.mapToItem(liveFace, background.width, background.height)
        backgroundRect = Qt.rect(tl.x / liveFace.width, tl.y / liveFace.height,
                                 (br.x - tl.x) / liveFace.width, (br.y - tl.y) / liveFace.height)
        background.grabToImage(function (r) {
            if (!picker.shown || picker.closing)
                return
            picker.backgroundResult = r
            picker.backgroundUrl = r.url
        })
    }

    // the open: the scale 1.613 -> 1 (screen 1 -> 0.69, dipping to 0.66: 6 % overshoot, about 259 ms) and the
    // centre 192 -> 171 (13-14 % overshoot, about 330 ms), Wear OS 6 emulator, motion M11
    WearSpring {
        id: scaleSpring
        objectName: "eosFaceScaleSpring"
        target: picker
        property: "previewScale"
        stiffness: FP.OPEN_SCALE_STIFFNESS
        dampingRatio: FP.OPEN_SCALE_DAMPING
        visibilityThreshold: FP.OPEN_SCALE_THRESHOLD
        onFinished: if (picker.shown && !picker.closing) picker.arrived = true
    }
    WearSpring {
        id: ySpring
        objectName: "eosFaceYSpring"
        target: picker
        property: "previewY"
        stiffness: FP.OPEN_Y_STIFFNESS
        dampingRatio: FP.OPEN_Y_DAMPING
        visibilityThreshold: FP.OPEN_Y_THRESHOLD
    }
    // the names, the chip and the arrows: hidden 100 ms after the cut, then 0 -> 1 in 50 ms (the emulator's
    // M11 frames 100-126). Stock sets no interpolator on these ValueAnimators (only the scale set has one), so
    // they run on the ValueAnimator default, AccelerateDecelerate, (cos((t + 1) pi) + 1) / 2 = InOutSine
    // (ManagementView.java:580-587)
    SequentialAnimation {
        id: openAnim
        objectName: "eosFaceOpenAnim"
        PauseAnimation { objectName: "eosFaceNamesHidden"; duration: Motion.duration(FP.NAMES_HIDDEN_MS) }
        NumberAnimation {
            objectName: "eosFaceNamesFade"
            target: picker; property: "namesOpacity"; to: 1
            duration: Motion.duration(FP.NAMES_FADE_MS)
            easing.type: Easing.InOutSine
        }
        onFinished: {
            picker.namesOpacity = 1
            picker.opened()
        }
    }

    // a face chosen: the carousel grows back to 1.613 in 300 ms on the centre preview, which becomes the face,
    // then the picker goes (CP3A; not captured on the emulator)
    ParallelAnimation {
        id: growAnim
        objectName: "eosFaceGrowAnim"
        NumberAnimation {
            target: picker; property: "previewScale"; to: FP.openScale(picker.width)
            duration: Motion.duration(FP.CLOSE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        NumberAnimation {
            target: picker; property: "previewY"; to: picker.height / 2
            duration: Motion.duration(FP.CLOSE_MS)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easing.legacy
        }
        onFinished: picker.finish()
    }
    function stopMotion() {
        openHold.stop()
        openAnim.stop()
        growAnim.stop()
        scaleSpring.stop()
        ySpring.stop()
    }
    function finish() {
        stopMotion()
        shown = false
        closing = false
        arrived = false
        scaleSpring.snapTo(1)
        ySpring.snapTo(previewCy)
        backgroundResult = null
        backgroundUrl = ""
        addList.closeNow()
        editing = false
        hideTimer.stop()
        flyer.visible = false
        flyId = ""
        closed()
    }

    // gone at once (the display went off, an application came up)
        function closeNow() {
        stopMotion()
        tapTimer.stop()
        flyAnim.stop()
        if (shown || closing)
            finish()
    }

    // closed without a change (the side button, the crown on "Add new", the picker's own timeout over the add
    // list): the Wear OS 6 emulator cuts to the live face (M11, BACK: 1-2 black frames at either animation
    // speed), no zoom and no fade, the springs stopped where they are
    function dismiss() {
        if (!shown || closing)
            return
        tapTimer.stop()
        flyAnim.stop()
        finish()
    }
    function close() { dismiss() }

    // a face is chosen: it goes on the watch now, the picker grows into it
    function choose(id) {
        if (!shown || closing || !store || store.indexOf(id) < 0)
            return
        tapTimer.stop()
        Haptics.confirm()
        store.choose(id)
        grow()
    }
    // the grow into the chosen face, from where the open's springs are
    function grow() {
        stopMotion()
        closing = true
        arrived = false
        growAnim.restart()
    }

    // the crown button; false when the picker leaves it to the home screen (it then closes the picker)
    function crownPressed() {
        if (!shown || closing)
            return true
        switch (FP.crownAction(view, centredAdd ? "add" : centredFid)) {
        case "back":
            addList.back()
            return true
        case "apply":
            choose(centredFid)
            return true
        default:
            dismiss()
            return true
        }
    }

    // ---- the idle timer: 15 s after the last finger lift (not while touching, not once the editor is open) ----
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
        running: picker.shown && !picker.closing && picker.arrived && !picker.touching && picker.awake
                 && !picker.editing && !flyAnim.running
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

    // ---- a button of the bottom row --------------------------------------------------
    /* Each change of the row runs stock's transition set ibk (ibk.java:13-27, begun by X(),
     * ManagementView.java:180-191) on the settings area: a Slide of 375 ms with the propagation ibj, a Fade of
     * MODE_IN only (450 ms) and a ChangeBounds (nothing moves: a hidden button keeps its place). The arrows and
     * the chip of one centred item are set together (kdu.java:221-240, iaf.java:188-199), one transition, and
     * the Slide starts each button that changes at its ibj delay (the chip 75 ms, the arrows 150 ms) less the
     * smallest delay among them (Transition.createAnimators; FP.rowWaits): an arrow that shows or hides on its
     * own slides at once, the chip with an arrow waits 0 ms and the arrow 75 ms (bottomRow.applyRow). A button
     * that hides stays as it is for its wait, slides down by the height of the area (Slide's bottom edge, the
     * scene root: 8 + 13 + 32 + 5 = 58 dp) on Accelerate (t^2) and is gone at the end, not faded; one that
     * shows starts down there, fades in at once on the ValueAnimator default (AccelerateDecelerate) and slides
     * up after its wait on Decelerate. */
    component RowButton: Rectangle {
        id: rowButton
        // shown (VISIBLE) or hidden (INVISIBLE): set by bottomRow.applyRow (hidden while nothing is centred)
        property bool on: false
        // the wait of its slide in the change it is in, ms (bottomRow.applyRow)
        property int waitMs: 0
        // the button's place in the row, and how far down it is slid
        property real rowY: 0
        property real drop: 0
        y: rowY + drop
        visible: opacity > 0
        states: State {
            name: "hidden"
            when: !rowButton.on
            PropertyChanges { target: rowButton; opacity: 0; drop: FP.ROW_HEIGHT_DP * 2 * picker.u }
        }
        transitions: [
            Transition {
                objectName: "eosRowHide"
                to: "hidden"
                enabled: !picker.rowInstant
                SequentialAnimation {
                    PauseAnimation { objectName: "eosRowHideWait"; duration: Motion.duration(rowButton.waitMs) }
                    NumberAnimation {
                        objectName: "eosRowHideSlide"
                        property: "drop"
                        duration: Motion.duration(FP.BUTTONS_CHANGE_MS)
                        easing.type: Easing.InQuad
                    }
                    PropertyAction { property: "opacity" }
                }
            },
            Transition {
                objectName: "eosRowShow"
                from: "hidden"
                enabled: !picker.rowInstant
                // (a Transition runs its animations together)
                NumberAnimation {
                    objectName: "eosRowShowFade"
                    property: "opacity"
                    duration: Motion.duration(FP.BUTTONS_FADE_MS)
                    easing.type: Easing.InOutSine
                }
                SequentialAnimation {
                    PauseAnimation { objectName: "eosRowShowWait"; duration: Motion.duration(rowButton.waitMs) }
                    NumberAnimation {
                        objectName: "eosRowShowSlide"
                        property: "drop"
                        duration: Motion.duration(FP.BUTTONS_CHANGE_MS)
                        easing.type: Easing.OutQuad
                    }
                }
            }
        ]
    }
    // the row takes the state of the face it opens on at once (a fresh view in stock), and animates after
    property bool rowInstant: false

    // ---- the carousel and the bottom row, one container that zooms ---------------
    Item {
        id: container
        objectName: "eosFaceContainer"
        anchors.fill: parent
        // the previews' scale about their centre at rest, then that centre to previewY
        transform: [
            Scale {
                id: zoomScale
                origin.x: picker.width / 2
                origin.y: picker.previewCy
                xScale: picker.previewScale
                yScale: xScale
            },
            Translate {
                y: picker.previewY - picker.previewCy
            }
        ]
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
            interactive: picker.shown && picker.arrived && !picker.closing && !addList.visible && !picker.editing
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

                // the name along the top edge of the screen, with the item, in onSurface #E8E7EE (the curved
                // title of stock's carousel item)
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
                    color: Theme.color.onSurface
                    opacity: picker.namesOpacity * cell.nameLift
                }

                /* the preview: the face's picture inside a ring of 4 px #202124 (managementui_border_color,
                 * managementui_items_border_width 2 dp, outside the 238 px picture), black inside. The Wear OS 6
                 * emulator draws every item, the face on the watch too, as the face at 10:09 on Thursday 24 May
                 * (S15, S15-b; N61-35): an eos face's picture drawn for the favourite (its style, its
                 * complications) by FacePreviewRenderer into the cache, or, until it is there and for the
                 * upstream faces, the shipped picture at 384 px. Either is the face drawn on nothing; an eos face
                 * is drawn over the wallpaper, so the wallpaper of the open goes under it, where it lies on the
                 * screen (a face that is a cut-out over the wallpaper, 016, would be black on black otherwise). */
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
                        color: "#000000"
                        border.width: picker.ringWidth
                        border.color: FP.RING_COLOR
                    }
                    // while a picture loads: a #32000000 disc
                    Rectangle {
                        objectName: "eosFacePlaceholder"
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        radius: width / 2
                        color: FP.PLACEHOLDER
                        visible: !shipped.ready && !rendered.ready
                    }
                    Item {
                        objectName: "eosFacePicture"
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        clip: true
                        // the wallpaper under the picture
                        Image {
                            id: faceBg
                            objectName: "eosFaceBackground"
                            readonly property bool wanted: (rendered.ready || shipped.ready) && !cell.flying
                                                           && picker.backgroundUrl !== ""
                            x: picker.backgroundRect.x * picker.itemSize
                            y: picker.backgroundRect.y * picker.itemSize
                            width: picker.backgroundRect.width * picker.itemSize
                            height: picker.backgroundRect.height * picker.itemSize
                            source: wanted ? picker.backgroundUrl : ""
                            visible: wanted
                            cache: false
                            asynchronous: false
                            smooth: true
                        }
                        // the shipped picture: only while the favourite has no picture of its own (never two sets
                        // of digits). The face on the watch loads at once: it is the open's first frame
                        Image {
                            id: shipped
                            objectName: "eosFaceShipped"
                            readonly property bool ready: status === Image.Ready
                            anchors.fill: parent
                            sourceSize.width: 384
                            sourceSize.height: 384
                            source: cell.isAdd ? "" : picker.pictureFolder + FP.stemOf(cell.file) + ".png"
                            asynchronous: !(picker.store && cell.fid === picker.store.currentId)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            opacity: cell.flying || rendered.ready ? 0 : 1
                        }
                        // the favourite's own picture (an eos face): the file FacePreviewRenderer wrote, read again
                        // when it writes one (previewVersion)
                        Image {
                            id: rendered
                            objectName: "eosFaceRender"
                            readonly property bool ready: status === Image.Ready
                            anchors.fill: parent
                            source: {
                                if (cell.isAdd || !picker.cache || FP.upstreamFace(cell.file))
                                    return ""
                                var v = picker.previewVersion
                                var u = String(picker.cache.url(FP.renderKey(cell.fid)))
                                return u === "" ? "" : u + "?v=" + v
                            }
                            sourceSize.width: 384
                            sourceSize.height: 384
                            cache: false
                            asynchronous: false
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            opacity: cell.flying ? 0 : 1
                        }
                    }
                    // the corners of the square picture or wallpaper, outside the round preview
                    RoundMask {
                        objectName: "eosFaceMask"
                        anchors.centerIn: parent
                        width: picker.itemSize
                        height: width
                        color: "#000000"
                        visible: (rendered.ready || faceBg.wanted) && !cell.flying
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
                        enabled: del.visible && picker.arrived
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

        // the bottom row: arrow, chip, arrow. Stock's settings area is a centred horizontal LinearLayout whose
        // buttons are hidden INVISIBLE, never GONE (ibk.a(), ibk.java:30-31; ManagementView.java:213-219,
        // 1153-1159, 1107-1139): a hidden button keeps its slot, so the chip stays in the middle
        // (x 140-244) and the arrows at x 68 and 252, 4 dp from it, whichever are shown
        Item {
            id: bottomRow
            objectName: "eosFaceRow"
            anchors.fill: parent
            // the row slides up from 15 % of the height after a face was added, fading in (addFade); at the open
            // it shows with the names (N61-36: hidden 100 ms after the cut, in 50 ms later)
            property real shift: 0
            property real addFade: 1
            y: shift
            opacity: addFade * picker.namesOpacity

            readonly property bool onFace: picker.centredFid !== "" && !picker.centredAdd
            readonly property bool leftOn: onFace && picker.centredIndex > 0
            readonly property bool rightOn: onFace && store !== null && picker.centredIndex < store.entries.length - 1
            readonly property real chipW: 104 * picker.u
            readonly property real arrowW: 64 * picker.u
            readonly property real gap: FP.ROW_GAP_DP * 2 * picker.u
            readonly property real chipX: (picker.width - chipW) / 2
            property QtObject store: picker.store

            // what the buttons go to; they follow together, one change (stock's X() calls of a frame are one
            // beginDelayedTransition), at once while the picker sets itself up (rowInstant)
            onOnFaceChanged: scheduleRow()
            onLeftOnChanged: scheduleRow()
            onRightOnChanged: scheduleRow()
            function scheduleRow() {
                if (picker.rowInstant)
                    applyRow()
                else
                    Qt.callLater(applyRow)
            }
            function applyRow() {
                var to = { left: leftOn, chip: onFace, right: rightOn }
                var w = FP.rowWaits({ left: leftArrow.on, chip: chip.on, right: rightArrow.on }, to)
                if (w.left >= 0)
                    leftArrow.waitMs = w.left
                if (w.chip >= 0)
                    chip.waitMs = w.chip
                if (w.right >= 0)
                    rightArrow.waitMs = w.right
                leftArrow.on = to.left
                chip.on = to.chip
                rightArrow.on = to.right
            }

            RowButton {
                id: leftArrow
                objectName: "eosFaceLeft"
                width: bottomRow.arrowW
                height: width
                radius: width / 2
                rowY: picker.arrowY
                x: bottomRow.chipX - bottomRow.gap - width
                color: Theme.color.surfaceContainer
                Accessible.role: Accessible.Button
                //% "Move watchface position left in the list"
                Accessible.name: qsTrId("id-face-move-left") + localeManager.changesObserver
                // CP3A's quantum_gm_ic_arrow_left_vd_theme_24: a filled caret in a 24 dp box
                Shape {
                    objectName: "eosFaceLeftGlyph"
                    anchors.centerIn: parent
                    width: FP.GLYPH_BOX_DP
                    height: FP.GLYPH_BOX_DP
                    scale: 2 * picker.u
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.color.primary
                        strokeColor: "transparent"
                        strokeWidth: -1
                        PathSvg { path: FP.GLYPH_ARROW_LEFT }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: bottomRow.leftOn && picker.arrived
                    onClicked: picker.moveCentred(-1)
                }
            }
            RowButton {
                id: chip
                objectName: "eosFaceChip"
                width: bottomRow.chipW
                height: 64 * picker.u
                radius: height / 2
                rowY: picker.chipY
                x: bottomRow.chipX
                color: Theme.color.primary
                Accessible.role: Accessible.Button
                //% "Edit watch face"
                Accessible.name: qsTrId("id-face-edit") + localeManager.changesObserver
                // CP3A's pencil_icon.xml: the outlined pencil, 20 x 18 dp, centred in its 24 dp box (inset 2 and
                // 3 dp), tinted onPrimary
                Shape {
                    objectName: "eosFaceChipGlyph"
                    anchors.centerIn: parent
                    width: FP.PENCIL_W_DP
                    height: FP.PENCIL_H_DP
                    scale: 2 * picker.u
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.color.onPrimary
                        fillRule: ShapePath.OddEvenFill
                        strokeColor: "transparent"
                        strokeWidth: -1
                        PathSvg { path: FP.GLYPH_PENCIL }
                    }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    enabled: bottomRow.onFace && picker.arrived
                    onClicked: picker.customize()
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "#000000"
                    opacity: chipArea.pressed ? 0.25 : 0
                }
            }
            RowButton {
                id: rightArrow
                objectName: "eosFaceRight"
                width: bottomRow.arrowW
                height: width
                radius: width / 2
                rowY: picker.arrowY
                x: bottomRow.chipX + bottomRow.chipW + bottomRow.gap
                color: Theme.color.surfaceContainer
                Accessible.role: Accessible.Button
                //% "Move watchface position right in the list"
                Accessible.name: qsTrId("id-face-move-right") + localeManager.changesObserver
                // CP3A's quantum_gm_ic_arrow_right_vd_theme_24
                Shape {
                    objectName: "eosFaceRightGlyph"
                    anchors.centerIn: parent
                    width: FP.GLYPH_BOX_DP
                    height: FP.GLYPH_BOX_DP
                    scale: 2 * picker.u
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Theme.color.primary
                        strokeColor: "transparent"
                        strokeWidth: -1
                        PathSvg { path: FP.GLYPH_ARROW_RIGHT }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: bottomRow.rightOn && picker.arrived
                    onClicked: picker.moveCentred(1)
                }
            }
        }
    }

    // ---- taps, delete, move -------------------------------------------------------
    property string tapId: ""
    function tapItem(index) {
        if (!shown || closing || !arrived || index < 0 || index >= faceModel.count)
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
        if (!shown || closing)
            return false
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
    // the flyer's round cut (facepicker.js roundCut): out to 3 px past the picture at the slot, inside the
    // 4 px ring (its outer pixel antialiased)
    readonly property var flyerCut: FP.roundCut((ringWidth - u) / itemSize)
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
        bottomRow.addFade = 0
        addList.fadeOut(Motion.duration(FP.ADD_LIST_FADE_MS))
        flyAnim.restart()
    }
    /* The preview in flight is drawn as the carousel item it lands in (a new favourite, with no picture of its
     * own yet): black inside the 4 px #202124 ring, the shipped 384 px picture on the wallpaper of the open, so
     * it lands without a change. It is round, as stock's flyer: the wallpaper and the picture are cut round by flyerCut (no
     * black corners over the delete button and the arrows). Without the wallpaper the picture is drawn as
     * the item draws it, on black. */
    Item {
        id: flyer
        objectName: "eosFaceFlyer"
        visible: false
        z: 2
        property string file: ""
        readonly property url picture: file === "" ? "" : picker.pictureFolder + FP.stemOf(file) + ".png"
        readonly property real side: width - 2 * picker.ringWidth
        // the shipped picture is there and so is the wallpaper's snapshot (the item's eosFaceBackground)
        readonly property bool backed: flyerShipped.ready && picker.backgroundUrl !== ""
        Rectangle {
            objectName: "eosFlyerRing"
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            border.width: picker.ringWidth
            border.color: FP.RING_COLOR
        }
        // while the picture loads: the item's #32000000 disc
        Rectangle {
            objectName: "eosFlyerPlaceholder"
            anchors.centerIn: parent
            width: flyer.side
            height: width
            radius: width / 2
            color: FP.PLACEHOLDER
            visible: !flyerShipped.ready
        }
        Image {
            id: flyerShipped
            objectName: "eosFlyerShipped"
            readonly property bool ready: status === Image.Ready
            anchors.centerIn: parent
            width: flyer.side
            height: width
            sourceSize.width: 384
            sourceSize.height: 384
            source: flyer.picture
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: flyer.backed ? 0 : 1
        }
        Item {
            id: flyerPicture
            objectName: "eosFlyerPicture"
            anchors.centerIn: parent
            width: flyer.side
            height: width
            Repeater {
                model: flyer.visible && flyer.backed ? picker.flyerCut : []
                Item {
                    objectName: "eosFlyerCut"
                    clip: true
                    width: modelData.width * flyerPicture.width
                    height: modelData.height * flyerPicture.height
                    x: (flyerPicture.width - width) / 2
                    y: (flyerPicture.height - height) / 2
                    // the wallpaper where it lies against the face (as the item's eosFaceBackground)
                    Image {
                        x: picker.backgroundRect.x * flyerPicture.width - parent.x
                        y: picker.backgroundRect.y * flyerPicture.height - parent.y
                        width: picker.backgroundRect.width * flyerPicture.width
                        height: picker.backgroundRect.height * flyerPicture.height
                        source: picker.backgroundUrl
                        smooth: true
                    }
                    Image {
                        x: -parent.x
                        y: -parent.y
                        width: flyerPicture.width
                        height: width
                        sourceSize.width: 384
                        sourceSize.height: 384
                        source: flyer.picture
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
            }
        }
        // the ring over the cut's edge
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: picker.ringWidth
            border.color: FP.RING_COLOR
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
                NumberAnimation { target: bottomRow; property: "addFade"; to: 1; duration: Motion.duration(FP.ADD_ROW_MS) }
            }
        }
        onFinished: {
            flyer.visible = false
            picker.flyId = ""
            bottomRow.shift = 0
            bottomRow.addFade = 1
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

    // ---- the editor: the pencil chip applies the face, then opens the editor over the picker ----
    /* W3-launcher-face-editor: the editor is its own layer (FaceEditor, placed above the picker by
     * HomeOverlays). The chip on another face than the one worn puts it on first, as stock edits the
     * face it applies. Stock hides the picker 500 ms after the editor opens (kdn.java:28-32), so
     * leaving the editor shows the face, not the carousel. */
    property bool editing: false
    signal editRequested()

    function customize() {
        if (!shown || closing || !store)
            return
        var id = centredFid
        if (id !== "" && id !== store.currentId)
            store.choose(id)
        tapTimer.stop()
        editing = true
        hideTimer.restart()
        editRequested()
    }
    Timer {
        id: hideTimer
        objectName: "eosFaceEditHide"
        interval: FE.PICKER_HIDE_MS
        onTriggered: picker.closeNow()
    }
}
