/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.nemomobile.lipstick
import org.asteroid.controls
import ".."
import "headsup.js" as HU

/*
 * The full notification view that a heads-up opens (audit heads-up-alerts-02,
 * -04): the stream's open card (NotificationCard, expanded, with the reply row,
 * the smart replies, the app's actions and Open on phone) alone on a black
 * round screen, flat as the Wear OS 6 emulator draws it (S10-d: no card surface,
 * the header, title and body on the black; the header's disc top at 21.88 % of
 * the height, where the stream's first card starts). The glanceable
 * turns into it over the face; the bubble grows into it over an app. Closing it
 * (the crown, a swipe right) leaves the notification in the list and goes back
 * to what was under: the face, or the app.
 *
 * It is a UI mode over whatever is under, not the stream: no list, no clear all.
 * The phone round trip, its result dialogs and the keyboard layers are the
 * shared NotificationRemote and a LayerStack here, as in the stream. Nothing
 * runs in it but what the card does (one minute timer: none; the time is read
 * when the card is made).
 *
 * When it has come in, the scroll indicator shows on its list for 2 s
 * (RotaryInput.flashIndicator: the full view's ScreenScaffold, a screen that
 * opens). After the glanceable's morph (the preview calls entered(), CP3A's
 * onFullViewShown, klg.c()) the header arrow also shows at the top and fades
 * 150 ms later over 300 ms. Grown from the bubble (the preview calls
 * showIndicator()) there is no such arrow: CP3A's heads-up builds its own
 * expanded view (ktk.java:139-158) that no klg runs.
 */
Item {
    id: detail

    property QtObject notification: null
    // a phone action may go on for this notification (it is still the one in front)
    property var isActive: function (id) { return true }

    // the swipe right committed: close the view
    signal closeRequested()

    readonly property real sideMargin: Math.round(0.052 * width)
    readonly property real topPadding: Math.round(0.2188 * height)
    readonly property QtObject remote: transport
    readonly property QtObject layers: stack
    readonly property Item card: stack.firstPageItem ? stack.firstPageItem.card : null
    // the list of the open card (what the indicator shows)
    readonly property Item scroller: stack.firstPageItem ? stack.firstPageItem.list : null
    // the view has come in (entered() or showIndicator())
    property bool shown: false
    // the header arrow's alpha: 1 when the view has come in, then faded (arrowAnimation)
    property real arrowOpacity: 0
    readonly property SequentialAnimation arrowAnimation: arrowFade

    // The view has come in after the glanceable's morph (CP3A klg.c(), run only when the morph
    // ends: jpb.java:370-371, made only at juh.java:361): the header arrow at 1, faded 150 ms
    // later over 300 ms (kln.f(150), klp.b()); and the scroll indicator (showIndicator()).
    // Returns whether the indicator took the list
    function entered() {
        arrowOpacity = 1
        arrowFade.restart()
        return showIndicator()
    }
    // The view has come in, either way (the morph, or the bubble grown into it): the scroll
    // indicator on the list for 2 s, the header arrow left as it is. CP3A's heads-up view
    // (ktk.java:139-158, hun_window_view.xml) has no klg, kln or klp: its arrow is never shown
    // at progress 0.75 nor faded. Returns whether the indicator took the list (it does when the
    // list scrolls)
    function showIndicator() {
        shown = true
        var ok = _flashList()
        _flashPending = !ok
        if (_flashPending)
            flashWait.restart()
        return ok
    }
    function _flashList() {
        return scroller !== null && RotaryInput.flashIndicator(scroller)
    }
    // The card's column is laid out at the next frame: a view that came in before that (a quick
    // morph or rise on a busy frame) has a list that does not scroll yet. The indicator is asked
    // again when the list's content height changes, for half a second (single shot)
    property bool _flashPending: false
    function _retryFlash() {
        if (_flashPending && _flashList()) {
            _flashPending = false
            flashWait.stop()
        }
    }
    Timer {
        id: flashWait
        interval: 500
        onTriggered: detail._flashPending = false
    }
    // a single run, only after entered() (the morph)
    SequentialAnimation {
        id: arrowFade
        PauseAnimation { duration: Motion.duration(HU.ARROW.holdMs) }
        NumberAnimation {
            target: detail
            property: "arrowOpacity"
            to: 0
            duration: Motion.duration(HU.ARROW.fadeMs)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: HU.ARROW.fadeEasing
        }
    }
    // a keyboard, emoji or voice page is open over the card
    readonly property bool layerOpen: stack.layers.length > 0

    // stock's "Now", "5m", "2h", "1d" (the stream's own)
    function ago(n) {
        if (!n || !n.timestamp)
            return ""
        var delta = (new Date().getTime() - n.timestamp.getTime()) / 60000
        //% "Now"
        if (delta < 1) return qsTrId("id-now")
        //% "m"
        if (delta < 60) return Math.floor(delta) + qsTrId("id-minute-abbrev")
        delta /= 60
        //% "h"
        if (delta < 24) return Math.floor(delta) + qsTrId("id-hour-abbrev")
        //% "d"
        return Math.floor(delta / 24) + qsTrId("id-day-abbrev")
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        swipeEnabled: !detail.layerOpen
        onFinished: {
            var go = committed
            reset()
            if (go)
                detail.closeRequested()
        }

        Item {
            width: parent.width
            height: parent.height
            x: swipe.value

            LayerStack {
                id: stack
                anchors.fill: parent
                win: null
                firstPage: page
                gesturesEnabled: !(currentLayer && currentLayer.innerDepth > 0)
            }
        }
    }

    Component {
        id: page

        Item {
            property alias card: openCard
            property alias list: scroller

            Flickable {
                id: scroller
                anchors.fill: parent
                contentWidth: width
                contentHeight: openCard.y + openCard.height + detail.topPadding
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                NotificationCard {
                    id: openCard
                    flat: true
                    x: detail.sideMargin
                    // the header at the stream's top padding (84 px): disc 44-88, 84-128 at 384 px
                    y: detail.topPadding - openCard.vPad
                    width: scroller.width - 2 * detail.sideMargin
                    notification: detail.notification
                    // made open: no opening animation
                    expanded: true
                    timestamp: detail.ago(detail.notification)
                    remote: transport
                    layerHost: stack
                }
            }

            Connections {
                target: scroller
                enabled: detail._flashPending
                function onContentHeightChanged() { detail._retryFlash() }
            }

            // CP3A's header arrow over the list, at the top (full_view_container.xml; HU.ARROW)
            Shape {
                id: headerArrow
                objectName: "headerArrow"
                width: parent.width
                height: Math.ceil((HU.ARROW.centreY + HU.ARROW.tipY + HU.ARROW.stroke) * detail.width / 384)
                opacity: detail.arrowOpacity
                visible: opacity > 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "#ffffff"
                    strokeWidth: HU.ARROW.stroke * detail.width / 384
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap
                    joinStyle: ShapePath.MiterJoin
                    miterLimit: 4
                    PathPolyline { path: HU.arrowPoints(detail.width, detail.width / 384) }
                }
            }
        }
    }

    // the phone round trip of the open card and its dialogs
    NotificationRemote {
        id: transport
        anchors.fill: parent
        z: 20
        isActive: function (id) {
            return detail.notification !== null && detail.notification.replacesId === id && detail.isActive(id)
        }
    }
}
