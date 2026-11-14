/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * One card of the notification stream, as Wear OS CP3A draws it (stock
 * sysui kxr.java:1761-1857, cyj.java:1345-1420): a Material 3 card of the
 * large shape (26 dp), at least 64 dp tall, surfaceContainer; opened in
 * place it is surfaceContainerLow and shows the whole notification inside
 * the list (no page): its height goes on a spring (stiffness 800, damping
 * ratio 0.8, kwm.java inline_stiffness / inline_damping) from the top
 * while the collapsed text fades out and the full text fades in. A
 * collapsed card shows the default template: header, title, body (two
 * lines each at most) and a 60 dp picture strip.
 *
 * The card does not take touches itself: the stream's row puts the tap
 * handler over the swipe-to-reveal (a handler there sees the press while
 * SwipeToReveal's own area keeps the swipe) and says pressed / pressPoint,
 * tapped() and longPressed() here. A swipe to the left is SwipeToReveal's.
 *
 * Opened, the card's own surface holds the header, title, messages or body and
 * the picture; what follows (the input row, the replies, the app's actions,
 * Open on phone: NotificationActions) hangs below it on the list's black, as
 * separate items as in stock (grw.java:2245-2424): the surface ends where the
 * text does, the whole opens and closes on the one spring.
 */
Item {
    id: card

    property QtObject notification
    property string timestamp: ""
    // opened in place (the stream keeps one open at a time)
    property bool expanded: false
    // the finger of the stream's tap handler is on the card (ripple, held)
    property bool pressed: false
    property point pressPoint: Qt.point(width / 2, height / 2)

    signal tapped()
    signal longPressed()
    // the screen reader's "Clear notification"
    signal clearRequested()
    // the stream's phone-action transport and the stack that takes the keyboard layers
    property QtObject remote: null
    property var layerHost: null

    // the finger that pressed the card is still down (after a long press too)
    readonly property bool held: pressed

    /* ---- stock geometry (px at 2 px per dp: 20 / 128 / 52 / 8) -------- */
    readonly property real sidePad: Theme.dp(10)
    readonly property real vPad: Theme.dp(10)
    readonly property real pictureGap: Theme.dp(4)
    // the open card's text items sit 7 dp from its edge, the header 10 dp (grw.java)
    readonly property real textInset: Theme.dp(7)
    readonly property real pictureInset: Theme.dp(4)
    readonly property real pictureHeight: Theme.dp(60)
    readonly property real pictureRadius: Theme.dp(22)
    readonly property real minHeight: Theme.dp(64)
    readonly property real radius: Theme.shape.large
    readonly property int springStiffness: 800
    readonly property real springDamping: 0.8

    readonly property bool hasPicture: collapsedPicture.shown
    readonly property real collapsedHeight: Math.max(minHeight,
        hasPicture ? vPad + collapsedText.height + pictureGap + collapsedPicture.height + pictureGap
                   : vPad + collapsedText.height + vPad)
    // the open card: its surface (header ... picture) and what hangs below it
    readonly property real surfaceFullHeight: fullLoader.item ? fullLoader.item.fullContentHeight : collapsedHeight
    readonly property real actionsFullHeight: actionsLoader.item ? actionsLoader.item.height : 0
    readonly property real fullHeight: surfaceFullHeight + actionsFullHeight

    // the height shown now: the spring's (the card is as tall as this)
    property real shownHeight: 0
    // 0 collapsed .. 1 open, from the height: what fades and mixes
    readonly property real expandProgress: {
        var span = Math.max(1, Math.max(collapsedHeight, fullHeight) - collapsedHeight)
        return Math.max(0, Math.min(1, (shownHeight - collapsedHeight) / span))
    }
    readonly property bool animating: heightSpring.running
    // The surface's height: the whole while nothing hangs below it, else its share
    // of the spring's travel (collapsed .. surface), so the actions slide down with it
    readonly property real surfaceHeight: {
        if (actionsFullHeight <= 0)
            return shownHeight
        var span = Math.max(1, fullHeight - collapsedHeight)
        var surface = Math.max(collapsedHeight, surfaceFullHeight)
        return collapsedHeight + (shownHeight - collapsedHeight) / span * (surface - collapsedHeight)
    }

    // A point of the card (its own coordinates) over what hangs below the surface: the
    // stream's long press is the surface's (the buttons are not)
    function onActions(p) {
        return actionsLoader.item !== null && actionsLoader.visible && p.y >= actionsLoader.y
    }

    height: shownHeight
    // a notification the user is told to touch exists for the screen reader
    Accessible.role: Accessible.Button
    Accessible.name: notification ? (notification.appName + ", " + notification.summary) : ""
    Accessible.description: notification ? notification.body : ""
    Accessible.onPressAction: card.tapped()
    // stock's custom actions "Clear notification" and "Settings" (kxr.java:285-331):
    // the stream maps them (clearRequested / settingsRequested) for the screen reader
    Accessible.onToggleAction: card.longPressed()
    Accessible.onDecreaseAction: card.clearRequested()

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }

    property bool _ready: false
    function fullH() { return surfaceFullHeight + actionsFullHeight }
    function currentTarget() { return expanded ? Math.max(collapsedHeight, fullH()) : collapsedHeight }
    // A height that changed by itself: an open card (or one still moving)
    // follows on the spring, a closed one just takes it (a text that grew)
    function retarget() {
        if (!_ready)
            return
        var t = currentTarget()
        if (Math.abs(t - shownHeight) < 0.5 && !heightSpring.running)
            return
        if (heightSpring.running || expanded)
            heightSpring.animateTo(t)
        else
            heightSpring.snapTo(t)
    }
    onCollapsedHeightChanged: retarget()
    onFullHeightChanged: retarget()
    onExpandedChanged: {
        if (!_ready)
            return
        if (expanded) {
            fullLoader.active = true
            actionsLoader.active = true
        }
        heightSpring.animateTo(currentTarget())
    }
    Component.onCompleted: {
        // created open (a heads-up tap opened it first): no animation
        fullLoader.active = expanded
        actionsLoader.active = expanded
        heightSpring.snapTo(currentTarget())
        _ready = true
    }

    // its settings and state, for the tests and the diagnostics
    readonly property QtObject heightAnimation: heightSpring
    WearSpring {
        id: heightSpring
        target: card
        property: "shownHeight"
        stiffness: card.springStiffness
        dampingRatio: card.springDamping
        onFinished: if (!card.expanded) {
            fullLoader.active = false
            actionsLoader.active = false
        }
    }

    Rectangle {
        id: bg
        width: parent.width
        height: card.surfaceHeight
        radius: card.radius
        color: card.mix(Theme.color.surfaceContainer, Theme.color.surfaceContainerLow, card.expandProgress)
        clip: true

        Ripple {
            anchors.fill: parent
            radius: bg.radius
            color: Theme.color.onSurface
            pressed: card.pressed
            pressX: card.pressPoint.x
            pressY: card.pressPoint.y
        }

        // collapsed: header, title, body, picture strip
        Item {
            id: collapsedLayer
            width: parent.width
            height: parent.height
            opacity: 1 - card.expandProgress
            visible: opacity > 0

            NotificationText {
                id: collapsedText
                x: card.sidePad
                y: card.vPad
                width: card.width - 2 * card.sidePad
                compact: true
                notification: card.notification
                timestamp: card.timestamp
            }

            // The picture strip (kxr.java:1224-1236): 60 dp tall, the card's
            // width less 4 dp each side, corners 22 dp, centre-cropped
            NotificationPicture {
                id: collapsedPicture
                x: card.pictureInset
                y: card.vPad + collapsedText.height + card.pictureGap
                width: card.width - 2 * card.pictureInset
                maxHeight: card.pictureHeight
                radius: card.pictureRadius
                notification: card.notification
            }
        }

        // open: everything of the notification, only while open or moving
        Loader {
            id: fullLoader
            width: parent.width
            active: false
            opacity: card.expandProgress
            visible: active && opacity > 0
            sourceComponent: Item {
                width: fullLoader.width
                readonly property real fullContentHeight: fullColumn.y + fullColumn.height + card.vPad
                height: fullContentHeight

                Column {
                    id: fullColumn
                    y: card.vPad
                    width: parent.width
                    spacing: 0

                    NotificationText {
                        id: fullText
                        width: parent.width
                        compact: false
                        headerInset: card.sidePad
                        textInset: card.textInset
                        notification: card.notification
                        timestamp: card.timestamp
                    }
                    // the notification's own picture: 4 dp above, 16 dp below (the card's
                    // bottom padding is part of it), 22 dp corners, the card's text width
                    Item {
                        width: 1
                        height: bigPicture.shown ? card.pictureGap : 0
                    }
                    NotificationPicture {
                        id: bigPicture
                        objectName: "bigPicture"
                        x: card.textInset
                        width: parent.width - 2 * card.textInset
                        maxHeight: width * 2
                        radius: card.pictureRadius
                        notification: card.notification
                        showError: true
                        // (not a conversation's: its messages show theirs)
                        suppressed: fullText.bubblePictures.length > 0
                    }
                    Item {
                        width: 1
                        height: bigPicture.shown ? Math.max(0, Theme.dp(16) - card.vPad) : 0
                    }
                }
            }
        }
    }

    // what follows the surface of the open card, on the list's black: the replies and
    // the actions (only while the card is open or moving)
    Loader {
        id: actionsLoader
        objectName: "actionsLoader"
        y: bg.height
        width: parent.width
        active: false
        opacity: card.expandProgress
        visible: active && opacity > 0
        sourceComponent: NotificationActions {
            width: actionsLoader.width
            notification: card.notification
            remote: card.remote
            layerHost: card.layerHost
        }
    }
}
