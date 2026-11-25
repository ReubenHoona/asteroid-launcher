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
 * lines each at most) and a 60 dp picture strip. The fades follow the
 * open state's own progress (openP, on the same spring), not the height:
 * an open card always shows its full layout alone, also when that is no
 * taller than the collapsed one, and is as tall as the full layout (at
 * least 64 dp). A card made open (the heads-up's full view) is open from
 * its first frame and takes a new height at once until the user toggles it.
 *
 * The card does not take touches itself: the stream's row puts the tap
 * handler over the swipe-to-reveal (a handler there sees the press while
 * SwipeToReveal's own area keeps the swipe) and says pressed / pressPoint,
 * tapped() and longPressed() here. A swipe either way is SwipeToReveal's.
 *
 * Flat (the heads-up's full view, as the Wear OS 6 emulator draws it, S10-d): no
 * surface and no ripple, the header, title and body straight on the black, a
 * 45 px header disc, the header 12 dp and the text 7 dp from the card's edge.
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
    // no surface: the heads-up's full view (see above)
    property bool flat: false

    // the finger that pressed the card is still down (after a long press too)
    readonly property bool held: pressed

    /* ---- stock geometry (px at 2 px per dp: 20 / 128 / 52 / 8) -------- */
    readonly property real sidePad: Theme.dp(10)
    readonly property real vPad: Theme.dp(10)
    readonly property real pictureGap: Theme.dp(4)
    // the open card's text items sit 7 dp from its edge, the header 10 dp (grw.java). Flat (S10-d):
    // the header 12 dp, so that a card at x 20 has its 45 px disc at x 44-88; the text 7 dp, its
    // ink from x 37 as the emulator's (Noto Sans starts its capitals about 3 px in)
    readonly property real headerInset: flat ? Theme.dp(12) : sidePad
    readonly property real textInset: Theme.dp(7)
    readonly property real headerIconSize: flat ? Theme.dp(22.5) : Theme.dp(24)
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
    // 0 collapsed .. 1 open, from the height: what the surface colour mixes on
    readonly property real expandProgress: {
        var span = Math.max(1, Math.max(collapsedHeight, fullHeight) - collapsedHeight)
        return Math.max(0, Math.min(1, (shownHeight - collapsedHeight) / span))
    }
    // 0 collapsed .. 1 open: the open state's own progress, on its own spring with the
    // height's numbers (800 / 0.8), started with it. What fades: the collapsed layer out,
    // the full text and what hangs below in (openOpacity, held to 0 .. 1)
    property real openP: 0
    readonly property real openOpacity: Math.max(0, Math.min(1, openP))
    readonly property bool animating: heightSpring.running || openSpring.running
    // The surface's height: the whole while nothing hangs below it, else from the collapsed
    // height to its own on the open progress, so the actions slide down with it
    readonly property real surfaceHeight: {
        if (actionsFullHeight <= 0)
            return shownHeight
        return collapsedHeight + openP * (surfaceFullHeight - collapsedHeight)
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
    // the user has opened or closed this card (a card made open has not, until then)
    property bool _toggled: false
    function fullH() { return surfaceFullHeight + actionsFullHeight }
    // open: as tall as the full layout, at least the card's 64 dp (not held to the
    // collapsed height: a short notification's full layout can be the shorter)
    function currentTarget() { return expanded ? Math.max(minHeight, fullH()) : collapsedHeight }
    // A height that changed by itself: a card the user opened (or one still moving)
    // follows on the spring; a closed one, and one made open, just take it (a text
    // that grew, the open card's parts laid out after it was made)
    function retarget() {
        if (!_ready)
            return
        var t = currentTarget()
        if (Math.abs(t - shownHeight) < 0.5 && !heightSpring.running)
            return
        if (heightSpring.running || (expanded && _toggled))
            heightSpring.animateTo(t)
        else
            heightSpring.snapTo(t)
    }
    onCollapsedHeightChanged: retarget()
    onFullHeightChanged: retarget()
    onExpandedChanged: {
        if (!_ready)
            return
        _toggled = true
        if (expanded) {
            fullLoader.active = true
            actionsLoader.active = true
        }
        openSpring.animateTo(expanded ? 1 : 0)
        heightSpring.animateTo(currentTarget())
    }
    Component.onCompleted: {
        // created open (a heads-up tap opened it first): open now, no animation
        fullLoader.active = expanded
        actionsLoader.active = expanded
        openSpring.snapTo(expanded ? 1 : 0)
        heightSpring.snapTo(currentTarget())
        _ready = true
    }
    // closed and both springs at rest: the open parts go
    function _settle() {
        if (!expanded && !heightSpring.running && !openSpring.running) {
            fullLoader.active = false
            actionsLoader.active = false
        }
    }

    // their settings and state, for the tests and the diagnostics
    readonly property QtObject heightAnimation: heightSpring
    readonly property WearSpring openAnimation: openSpring
    WearSpring {
        id: heightSpring
        target: card
        property: "shownHeight"
        stiffness: card.springStiffness
        dampingRatio: card.springDamping
        onFinished: card._settle()
    }
    WearSpring {
        id: openSpring
        target: card
        property: "openP"
        stiffness: card.springStiffness
        dampingRatio: card.springDamping
        onFinished: card._settle()
    }

    Rectangle {
        id: bg
        objectName: "cardSurface"
        width: parent.width
        height: card.surfaceHeight
        radius: card.radius
        color: card.flat ? "transparent"
                         : card.mix(Theme.color.surfaceContainer, Theme.color.surfaceContainerLow, card.expandProgress)
        clip: true

        Ripple {
            visible: !card.flat
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
            objectName: "collapsedLayer"
            width: parent.width
            height: parent.height
            opacity: 1 - card.openOpacity
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
            objectName: "fullLoader"
            width: parent.width
            active: false
            opacity: card.openOpacity
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
                        headerInset: card.headerInset
                        textInset: card.textInset
                        iconSize: card.headerIconSize
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
        opacity: card.openOpacity
        visible: active && opacity > 0
        sourceComponent: NotificationActions {
            width: actionsLoader.width
            notification: card.notification
            remote: card.remote
            layerHost: card.layerHost
        }
    }
}
