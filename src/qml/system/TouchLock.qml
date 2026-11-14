/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.utils
import "system.js" as Sys

/* Touch lock (wake-sleep-display-03, wrist-orientation-13), as stock CP3A
 * (TouchLockUiComposer, TouchLockAnimationController, TouchDisabledState
 * Policy): the touch screen is off in every display state; the crown still
 * scrolls and wakes, tilt still wakes (the modes engine holds mce's touch
 * wake off while it is on). Instantiated once in compositor.qml as
 * `touchLock` at z `arbiter.layers.touchLock`: the quick settings tile
 * calls touchLock.lock(), the Settings page writes the dconf key
 * /org/asteroidos/settings/touch-lock = true and the lock takes it from
 * there (it puts the key back to false when it is turned off).
 *
 *  - On: every touch stops here. The crown short press, the crown hold and
 *    the side button's short press are filtered (keymap.js) and show the
 *    exit view: black, a row centred vertically with 7.4 % at the sides,
 *    the text "Press & hold crown 2 sec to exit touch lock" and a 60 x 44
 *    dp crown motif on the side of the physical crown, 8 dp apart; the view
 *    hides itself 2000 ms after it appeared.
 *  - Holding the crown (mce's down and up edges, crownDown()/crownUp())
 *    fills an 8 dp edge ring from 12 o'clock clockwise, linear over 2000
 *    ms; letting go early springs it back (damping 1.0, stiffness 260); a
 *    full ring turns the lock off. mce without the edge triggers sends only
 *    the 3 s hold: KeyRouter then calls unlock() from it.
 *  - The status icon "Touch lock on" (36 px disc, top centre) shows on the
 *    watch face while it is on.
 * Nothing here polls or runs a timer while the lock is off; the hint's
 * timer runs only while the view is up with the display on. */
Item {
    id: touchLock
    objectName: "touchLock"
    anchors.fill: parent

    /* the display is on; the lock's view goes with it */
    property bool displayOn: true
    /* the watch face is what shows (not an app, not an overlay): the status icon */
    property bool onFace: false
    /* the launcher turns its screen over 180 degrees for a crown on the left
     * (none does today): the crown is on the right again then */
    property bool displayRotated: false
    // a clock in ms (tests replace it)
    property var clock: function () { return Date.now() }

    readonly property bool locked: store.value === true || store.value === "true"
    readonly property bool hintShown: hintOn
    property bool hintOn: false
    property real ring: 0
    readonly property bool holding: downAt >= 0
    property real downAt: -1
    // when the lock was last turned off by the crown (KeyRouter: the rest of that hold is not a press)
    property real exitedAt: -1e9
    readonly property bool crownOnRight: Sys.crownOnRight(wrist.value, displayRotated)
    readonly property alias statusIcon: statusDisc
    readonly property alias exitView: hintView

    // turned on, by any way
    signal engaged()
    // turned off (the ring completed, or the 3 s hold)
    signal exited()

    ConfigurationValue {
        id: store
        key: "/org/asteroidos/settings/touch-lock"
        defaultValue: false
    }
    ConfigurationValue {
        id: wrist
        key: "/org/asteroidos/settings/wrist-orientation-mode"
        defaultValue: 0
    }

    /* Turn it on (the quick settings tile, the power menu, Settings). */
    function lock() {
        if (!locked)
            store.value = true
    }

    /* Turn it off: the key goes back to false. */
    function unlock() {
        if (!locked)
            return
        fill.stop()
        spring.stop()
        downAt = -1
        ring = 0
        hintOn = false
        hideTimer.stop()
        exitedAt = clock()
        store.value = false
        exited()
    }

    /* The exit view: a filtered key was pressed */
    function showHint() {
        if (!locked || !displayOn)
            return
        hintOn = true
        if (!holding)
            hideTimer.restart()
    }
    function hideHint() {
        hintOn = false
        hideTimer.stop()
        if (!holding) {
            spring.stop()
            ring = 0
        }
    }

    /* The crown went down (mce "asteroid-crown-down", every display state):
     * the ring starts to fill. */
    function crownDown() {
        if (!locked || holding)
            return
        displayOn = true
        downAt = clock()
        hintOn = true
        hideTimer.stop()
        spring.stop()
        fill.stop()
        fill.from = ring
        fill.to = 1
        fill.duration = Math.max(1, Math.round((1 - ring) * Sys.TOUCH_EXIT_HOLD_MS))
        fill.start()
    }

    /* The crown came up: the ring springs back, the view hides 2 s later. */
    function crownUp() {
        if (!holding)
            return
        downAt = -1
        fill.stop()
        if (ring > 0)
            spring.animateTo(0)
        hideTimer.restart()
    }

    onLockedChanged: {
        if (locked) {
            ring = 0
            engaged()
        } else {
            fill.stop()
            spring.stop()
            downAt = -1
            ring = 0
            hintOn = false
            hideTimer.stop()
        }
    }
    onDisplayOnChanged: {
        if (!displayOn)
            hideHint()
    }

    NumberAnimation {
        id: fill
        target: touchLock
        property: "ring"
        easing.type: Easing.Linear
        onFinished: {
            if (touchLock.holding && touchLock.ring >= 1)
                touchLock.unlock()
        }
    }
    WearSpring {
        id: spring
        target: touchLock
        property: "ring"
        to: 0
        stiffness: Sys.TOUCH_SPRING_STIFFNESS
        dampingRatio: Sys.TOUCH_SPRING_DAMPING
        visibilityThreshold: 0.002
    }
    Timer {
        id: hideTimer
        interval: Sys.TOUCH_HINT_MS
        onTriggered: touchLock.hideHint()
    }

    /* every touch stops here while it is on: nothing below sees it (the crown's wheel is
     * not a touch, so lists still scroll) */
    MultiPointTouchArea {
        anchors.fill: parent
        enabled: touchLock.locked
        visible: touchLock.locked
        mouseEnabled: true
    }

    /* the status icon, as the other status indicators (36 px black disc at 85 %, top centre) */
    Rectangle {
        id: statusDisc
        objectName: "touchLockStatus"
        width: Theme.size.statusIcon
        height: width
        radius: width / 2
        color: "#000000"
        opacity: 0.85
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.dp(3)
        visible: touchLock.locked && touchLock.onFace && !hintView.visible
        Icon {
            anchors.centerIn: parent
            width: parent.width * 0.6
            height: width
            name: "ms-screen_lock_portrait"
            color: Theme.color.onSurface
        }
        Accessible.role: Accessible.StaticText
        //% "Touch lock on"
        Accessible.name: qsTrId("id-touch-lock-on")
    }

    /* the exit view */
    Rectangle {
        id: hintView
        objectName: "touchLockExitView"
        anchors.fill: parent
        color: "#000000"
        opacity: touchLock.hintOn && touchLock.locked ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 100 } }

        readonly property real sidePadding: Math.round(Sys.TOUCH_SIDE_FRACTION * width)

        // the edge ring: track and fill, 8 dp, from 12 o'clock clockwise
        ProgressArc {
            objectName: "touchLockTrack"
            anchors.fill: parent
            strokeWidth: Sys.TOUCH_RING_WIDTH
            color: Theme.color.surfaceContainer
            startAngle: 270
            sweepAngle: touchLock.holding || touchLock.ring > 0 ? 360 : 0
        }
        ProgressArc {
            id: ringFill
            objectName: "touchLockRing"
            anchors.fill: parent
            strokeWidth: Sys.TOUCH_RING_WIDTH
            color: Theme.color.primary
            startAngle: 270
            sweepAngle: 360 * touchLock.ring
        }

        Item {
            id: row
            x: hintView.sidePadding
            width: parent.width - 2 * hintView.sidePadding
            height: Math.max(label.height, Sys.TOUCH_MOTIF_H)
            anchors.verticalCenter: parent.verticalCenter

            Label {
                id: label
                objectName: "touchLockText"
                role: "titleSmall"
                color: Theme.color.onSurface
                wrapMode: Text.WordWrap
                width: row.width - Sys.TOUCH_MOTIF_W - Sys.TOUCH_MOTIF_GAP
                anchors.verticalCenter: parent.verticalCenter
                x: touchLock.crownOnRight ? 0 : row.width - width
                horizontalAlignment: touchLock.crownOnRight ? Text.AlignLeft : Text.AlignRight
                // stock touch_lock_exit_text_without_ejection
                //% "Press & hold crown 2 sec to exit touch lock"
                text: qsTrId("id-touch-lock-exit") + localeManager.changesObserver
            }

            /* the crown motif (original drawing): the edge of the case, the
             * crown, and a fingertip that presses toward it */
            Item {
                id: motif
                objectName: "touchLockMotif"
                width: Sys.TOUCH_MOTIF_W
                height: Sys.TOUCH_MOTIF_H
                anchors.verticalCenter: parent.verticalCenter
                x: touchLock.crownOnRight ? row.width - width : 0
                readonly property bool toRight: touchLock.crownOnRight

                Rectangle {
                    id: caseEdge
                    width: 14
                    height: parent.height
                    radius: 7
                    color: Theme.color.surfaceContainerHigh
                    x: motif.toRight ? parent.width - width : 0
                }
                Rectangle {
                    id: crown
                    width: 20
                    height: Math.round(parent.height * 0.5)
                    radius: 6
                    color: Theme.color.onSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                    x: motif.toRight ? caseEdge.x - width + 4 : caseEdge.width - 4
                }
                Rectangle {
                    id: finger
                    width: 36
                    height: 36
                    radius: 18
                    color: Theme.color.primary
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real farX: motif.toRight ? 0 : motif.width - width
                    readonly property real nearX: motif.toRight ? crown.x - width - 4 : crown.x + crown.width + 4
                    x: farX
                    SequentialAnimation on x {
                        running: hintView.visible && touchLock.displayOn
                        loops: Animation.Infinite
                        NumberAnimation { to: finger.nearX; duration: 700; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 300 }
                        NumberAnimation { to: finger.farX; duration: 400; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }
    }
}
