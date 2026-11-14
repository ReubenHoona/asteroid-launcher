/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.lipstick
import org.asteroid.controls
import ".."

/*
 * The full notification view that a heads-up opens (audit heads-up-alerts-02,
 * -04): the stream's open card (NotificationCard, expanded, with the reply row,
 * the smart replies, the app's actions and Open on phone) alone on a black
 * round screen, 21.88 % below the top as the stream's first card. The glanceable
 * turns into it over the face; the bubble grows into it over an app. Closing it
 * (the crown, a swipe right) leaves the notification in the list and goes back
 * to what was under: the face, or the app.
 *
 * It is a UI mode over whatever is under, not the stream: no list, no clear all.
 * The phone round trip, its result dialogs and the keyboard layers are the
 * shared NotificationRemote and a LayerStack here, as in the stream. Nothing
 * runs in it but what the card does (one minute timer: none; the time is read
 * when the card is made).
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

            Flickable {
                id: scroller
                anchors.fill: parent
                contentWidth: width
                contentHeight: openCard.y + openCard.height + detail.topPadding
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                NotificationCard {
                    id: openCard
                    x: detail.sideMargin
                    y: detail.topPadding
                    width: scroller.width - 2 * detail.sideMargin
                    notification: detail.notification
                    // made open: no opening animation
                    expanded: true
                    timestamp: detail.ago(detail.notification)
                    remote: transport
                    layerHost: stack
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
