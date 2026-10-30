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
 * s sender, t text, me the user's own).
 */
Column {
    id: conversation

    property QtObject notification
    // [{ s, t, me }] oldest first, [] when the notification has none
    readonly property var messages: parse(notification)
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
            return list.filter(function (m) { return m && typeof m.t === "string" && m.t.length > 0 })
                       .map(function (m) { return { s: typeof m.s === "string" ? m.s : "", t: m.t, me: m.me === true } })
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
                color: "#a8c7fa"
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Dims.l(5.2)
                font.styleName: "SemiCondensed Medium"
            }

            Rectangle {
                id: bubbleRect
                readonly property real padX: Dims.l(3.9)
                readonly property real padY: Dims.l(2.6)
                y: message.height - height
                width: textLabel.width + 2 * padX
                height: textLabel.height + 2 * padY
                x: message.own ? conversation.width - width : 0
                color: message.own ? "#a8c7fa" : "#303033"
                readonly property real r: Math.min(conversation.largeRadius, height / 2)
                // the corners on the sender's side are small where the run goes on
                topLeftRadius: !message.own && message.joinedAbove ? conversation.smallRadius : r
                bottomLeftRadius: !message.own && message.joinedBelow ? conversation.smallRadius : r
                topRightRadius: message.own && message.joinedAbove ? conversation.smallRadius : r
                bottomRightRadius: message.own && message.joinedBelow ? conversation.smallRadius : r

                Label {
                    id: textLabel
                    x: bubbleRect.padX
                    y: bubbleRect.padY
                    // as wide as the text, at most 86 % of the column
                    width: Math.min(implicitWidth, conversation.width * 0.86 - 2 * bubbleRect.padX)
                    text: message.m.t
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: message.own ? "#062e6f" : "#e3e3e3"
                    font.pixelSize: Dims.l(6)
                }
            }
        }
    }
}
