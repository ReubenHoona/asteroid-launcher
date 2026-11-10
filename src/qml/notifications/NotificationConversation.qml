/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * A conversation in the full view, as Wear OS 4 shows a MessagingStyle
 * notification (ClockworkSysUiGoogle full_view_nonuser_message,
 * full_view_user_message, full_view_message_person): one bubble per message,
 * the others' at the start in a dark bubble, the user's own at the end in
 * the accent colour; the sender's name above a run of messages of a group
 * (not in a one to one conversation, whose title is the person); bubbles of
 * a run joined with small corners on the sender's side (24 dp corners, 4 dp
 * where they join, 12 x 8 dp padding, 2 dp between them, 8 dp between runs).
 * The messages come from asteroid-btsyncd's x-asteroid-messages hint (JSON:
 * s sender, t text, me the user's own, p the file of its picture with w, h).
 * A message's picture shows in its bubble, above its text, as stock keeps a
 * message's image with the message (full_view_message_picture); a tap on it
 * is pictureTapped (the full screen view).
 */
Column {
    id: conversation

    property QtObject notification
    // [{ s, t, me, p, size }] oldest first, [] when the notification has none
    readonly property var messages: parse(notification)
    // the pictures the bubbles show
    readonly property var picturePaths: messages.filter(function (m) { return m.p !== "" }).map(function (m) { return m.p })

    signal pictureTapped(string path, string size)
    // a group, or a conversation whose senders are not only its title
    readonly property bool showSenders: {
        var title = notification ? notification.summary : ""
        for (var i = 0; i < messages.length; i++)
            if (!messages[i].me && messages[i].s !== "" && messages[i].s !== title)
                return true
        return false
    }

    function parse(n) {
        if (!n || !n.hints)
            return []
        var raw = n.hints["x-asteroid-messages"]
        if (!raw)
            return []
        try {
            var list = JSON.parse(String(raw))
            if (!Array.isArray(list))
                return []
            return list.filter(function (m) { return m && typeof m.t === "string" && (m.t.length > 0 || typeof m.p === "string") })
                       .map(function (m) {
                           var p = typeof m.p === "string" ? m.p : ""
                           var size = Number(m.w) > 0 && Number(m.h) > 0 ? m.w + "x" + m.h : ""
                           return { s: typeof m.s === "string" ? m.s : "", t: m.t, me: m.me === true, p: p, size: size }
                       })
                       .filter(function (m) { return m.t.length > 0 || m.p !== "" })
        } catch (e) {
            return []
        }
    }

    // two messages of one run: the same side, and the same sender for the others'
    function sameRun(a, b) {
        if (!a || !b || a.me !== b.me)
            return false
        return a.me || a.s === b.s
    }

    // stock: 24 dp corners, 4 dp joins (the launcher's 24 dp card is Dims.l(8))
    readonly property real largeRadius: Dims.l(8)
    readonly property real smallRadius: Dims.l(1.4)

    spacing: 0

    Repeater {
        id: repeater
        model: conversation.messages.length
        delegate: Item {
            id: message
            objectName: "bubble"
            readonly property var m: conversation.messages[index]
            readonly property var previous: index > 0 ? conversation.messages[index - 1] : null
            readonly property var next: index + 1 < conversation.messages.length ? conversation.messages[index + 1] : null
            readonly property bool joinedAbove: conversation.sameRun(previous, m)
            readonly property bool joinedBelow: conversation.sameRun(m, next)
            readonly property bool own: m.me
            readonly property bool named: conversation.showSenders && !own && !joinedAbove && m.s !== ""
            readonly property alias bubble: bubbleRect
            readonly property alias label: textLabel

            width: conversation.width
            height: (index === 0 ? 0 : joinedAbove ? Dims.l(0.7) : Dims.l(2.6))
                    + (named ? senderLabel.height + Dims.l(0.7) : 0) + bubbleRect.height

            Label {
                id: senderLabel
                visible: message.named
                y: index === 0 ? 0 : Dims.l(2.6)
                x: Dims.l(1.4)
                width: conversation.width - 2 * x
                text: message.m.s
                color: Theme.color.primary
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Theme.type.bodyExtraSmall.pixelSize
                font.styleName: "SemiCondensed Medium"
            }

            Rectangle {
                id: bubbleRect
                readonly property real padX: Dims.l(3.9)
                readonly property real padY: Dims.l(2.6)
                readonly property bool hasText: message.m.t.length > 0
                readonly property bool hasPicture: message.m.p !== ""
                // a picture message is as wide as the bubbles get
                readonly property real pictureWidth: conversation.width * 0.86 - 2 * padY
                y: message.height - height
                width: hasPicture ? conversation.width * 0.86 : textLabel.width + 2 * padX
                height: (hasPicture ? bubblePicture.height + padY : 0) + (hasText ? textLabel.height + padY : 0) + padY
                x: message.own ? conversation.width - width : 0
                color: message.own ? Theme.color.primary : "#303033"
                readonly property real r: Math.min(conversation.largeRadius, height / 2)
                // the corners on the sender's side are small where the run goes on
                topLeftRadius: !message.own && message.joinedAbove ? conversation.smallRadius : r
                bottomLeftRadius: !message.own && message.joinedBelow ? conversation.smallRadius : r
                topRightRadius: message.own && message.joinedAbove ? conversation.smallRadius : r
                bottomRightRadius: message.own && message.joinedBelow ? conversation.smallRadius : r

                NotificationPicture {
                    id: bubblePicture
                    objectName: "bubblePicture"
                    visible: bubbleRect.hasPicture
                    x: bubbleRect.padY
                    y: bubbleRect.padY
                    width: bubbleRect.pictureWidth
                    // at most square in the bubble (the full screen view shows all of it)
                    maxHeight: width
                    radius: Math.max(0, bubbleRect.r - bubbleRect.padY)
                    picturePath: message.m.p
                    pictureSize: message.m.size
                    showError: true
                    tappable: true
                    onTapped: conversation.pictureTapped(message.m.p, message.m.size)
                }

                Label {
                    id: textLabel
                    visible: bubbleRect.hasText
                    x: bubbleRect.padX
                    y: bubbleRect.hasPicture ? bubblePicture.y + bubblePicture.height + bubbleRect.padY : bubbleRect.padY
                    // as wide as the text, at most 86 % of the column
                    width: Math.min(implicitWidth, conversation.width * 0.86 - 2 * bubbleRect.padX)
                    text: message.m.t
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: message.own ? Theme.color.onPrimary : "#e3e3e3"
                    font.pixelSize: Theme.type.bodySmall.pixelSize
                }
            }
        }
    }
}
