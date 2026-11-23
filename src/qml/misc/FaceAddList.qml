/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "facepicker.js" as FP
import "compositor"

/*
 * The add-face list of the watch face picker (face-interaction-18), as stock
 * (managementui_all_items / AllItemsView / ManagementView.H()): full screen,
 * black, the curved title "Add new" (15 dp, colorOnSurface, top 8 px), a
 * two-column grid of 80 dp (160 px) round previews with a 2 dp #404040 ring
 * and the face's name under each (Caption2, one line, 6 dp above, 16 dp
 * below), 36.46 % of the height of padding at the bottom.
 *
 * Opening: scale 0.25 to 1 in 250 ms (the standard easing), alpha 0 to 1 in
 * 75 ms, from a black disc (the circular reveal), a white #12ffffff flash held
 * 75 ms and faded over 750 ms. Back by the crown: the same in reverse. A swipe
 * right is stock's SwipeDismissFrameLayout (facepicker.js ADD_DISMISS_*): the
 * list follows the finger, squeezed with its right edge pinned and dimmed, and
 * goes right on a spring, or springs back. A tap on a face emits picked(), with
 * where the preview is; the picker adds the face and flies the preview into the
 * carousel.
 */
Item {
    id: list
    anchors.fill: parent
    visible: false

    // every installed face, as file URLs
    property var faces: []
    property string previewFolder: "file:///usr/share/asteroid-launcher/watchfaces-preview/182/"
    readonly property real u: width / 384

    readonly property bool isOpen: visible && !leaving
    property bool leaving: false

    signal picked(string file, real cx, real cy, real size)
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
            // as back() ends, without its reverse zoom
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
        stiffness: FP.ADD_DISMISS_STIFFNESS
        dampingRatio: FP.ADD_DISMISS_DAMPING
        visibilityThreshold: FP.ADD_DISMISS_MIN_CHANGE
        onValueChanged: list.springMoved(value)
        onFinished: list.springDone()
    }

    readonly property real previewSize: 160 * u
    readonly property real ringWidth: 4 * u
    readonly property real nameTop: 12 * u
    readonly property real nameBottom: 32 * u
    readonly property real captionSize: Theme.type.bodySmall.pixelSize
    readonly property real cellH: previewSize + 2 * ringWidth + nameTop + captionSize * 1.3 + nameBottom
    // the grid starts under the title (the header of stock's list; inferred)
    readonly property real gridTop: 64 * u
    readonly property real bottomPadding: 0.3646 * height

    function open() {
        leaveAnim.stop()
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

    // gone at once (the picker closes, the display went off)
    function closeNow() {
        enterAnim.stop()
        leaveAnim.stop()
        resetSwipe()
        leaving = false
        visible = false
    }

    // the list fades out (the face was picked: the picker flies the preview away first)
    function fadeOut(ms) {
        fadeAnim.duration = ms
        fadeAnimRun.restart()
    }

    Item {
        id: panel
        objectName: "eosAddPanel"
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
            objectName: "eosAddGrid"
            anchors.fill: parent
            topMargin: list.gridTop
            bottomMargin: list.bottomPadding
            cellWidth: width / 2
            cellHeight: list.cellH
            model: list.faces
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: cell
                objectName: "eosAddCell"
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property string file: modelData
                readonly property string name: FP.displayName(modelData)

                // the preview's ring and image
                Rectangle {
                    id: ring
                    objectName: "eosAddRing"
                    width: list.previewSize + 2 * list.ringWidth
                    height: width
                    radius: width / 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: FP.PLACEHOLDER
                    border.color: FP.ALL_RING_COLOR
                    border.width: list.ringWidth
                    Image {
                        anchors.centerIn: parent
                        width: list.previewSize
                        height: width
                        sourceSize.width: 182
                        sourceSize.height: 182
                        source: list.previewFolder + FP.stemOf(cell.file) + ".png"
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
                Label {
                    objectName: "eosAddName"
                    anchors.top: ring.bottom
                    anchors.topMargin: list.nameTop
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: list.previewSize + 2 * list.ringWidth
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: cell.name
                    color: Theme.color.onSurface
                    font.pixelSize: list.captionSize
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        var p = ring.mapToItem(list, ring.width / 2, ring.height / 2)
                        list.picked(cell.file, p.x, p.y, list.previewSize)
                    }
                }
            }
        }

        // the title along the top edge
        CurvedTopText {
            objectName: "eosAddTitle"
            anchors.fill: parent
            //% "Add new"
            text: qsTrId("id-face-add-new") + localeManager.changesObserver
            color: Theme.color.onSurface
            role: "arcMedium"
            pixelSize: Theme.dp(15)
            maxSweep: 90
            topMargin: Math.round(list.height * 0.0208)
            shadow: "transparent"
        }

        // a white flash held 75 ms, then faded over 750 ms
        Rectangle {
            id: flash
            objectName: "eosAddFlash"
            anchors.fill: parent
            radius: width / 2
            color: FP.ADD_FLASH_COLOR
            opacity: 0
            visible: opacity > 0
        }

        // the dim of the swipe (stock: a SRC_ATOP black on the frame's layer, gax.java:116-127)
        Rectangle {
            objectName: "eosAddDim"
            anchors.fill: parent
            radius: width / 2
            color: "#000000"
            opacity: list.swipeDim
            visible: opacity > 0
        }

        // swipe right: the list follows the finger, then goes or comes back
        DragHandler {
            id: swipe
            target: null
            yAxis.enabled: false
            property real lastDx: 0
            property real dx: 0
            property real vx: 0
            property real vy: 0
            onTranslationChanged: {
                lastDx = translation.x - dx
                dx = translation.x
                vx = centroid.velocity.x
                vy = centroid.velocity.y
                if (active)
                    list.dragTo(dx)
            }
            onActiveChanged: {
                if (active) {
                    dx = 0
                    lastDx = 0
                    vx = 0
                    vy = 0
                } else {
                    list.release(dx, vx, vy, lastDx < 0)
                }
            }
        }
    }

    // the entry
    ParallelAnimation {
        id: enterAnim
        objectName: "eosAddEnter"
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
        objectName: "eosAddLeave"
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
    // the list fades out after a face was picked
    SequentialAnimation {
        id: fadeAnimRun
        objectName: "eosAddFade"
        NumberAnimation {
            id: fadeAnim
            target: panel; property: "opacity"; to: 0; duration: FP.ADD_LIST_FADE_MS
        }
        ScriptAction { script: { list.visible = false; list.closed() } }
    }
}
