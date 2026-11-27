/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls

/*
 * A conversation in the open card, as Wear OS CP3A shows a MessagingStyle
 * notification (SysUI grw.java:7040-7329, khb.java:15-40, kqr.java, kqq.java):
 * one bubble per message, the others' at the start, the user's own at the end;
 * the sender's name above a run of messages of a group (not in a one to one
 * conversation, whose title is the person); the bubbles of a run joined with
 * small corners on the sender's side. All numbers are px at 2 px per dp
 * (Theme.dp):
 *  - others: surfaceContainer, text onSurface; own: primaryDim, text onPrimary;
 *  - text bodyLarge (16 sp, 32 px); padding 12 x 10 dp (24 x 20 px);
 *  - corners 22 dp (44 px), 4 dp (8 px) on the sender's side where a run joins
 *    (full_view_message_text_large/small_corner_radius);
 *  - a bubble is at most the column's width less 5.52 % of 192 dp (21 px), left
 *    free on the far side (full_view_message_bubble_padding_percentage);
 *  - the sender's name labelSmall (13 sp, 26 px), onSurface, two lines at most,
 *    8 dp above a run (inferred 2 dp between the name and the bubble);
 *  - a message's picture is an item of its own before its text bubble, on the
 *    sender's side, 22 dp corners, no bubble behind it (MessageImageModel,
 *    full_view_message_image_corner_radius); it is not tappable (no viewer).
 *  - R5 B-04: a time section header before the first message that has a time
 *    and before each message an hour or more after the one before (hfu.l,
 *    kha.b = 1 h; koi.java:905-957): labelSmall, onSurfaceVariant, one line,
 *    centred, 8 dp above (2 dp for the first) (grw.java:6990-7037,
 *    7343-7353); its words (kls, the full view's): "Now" under a minute,
 *    "%dm ago" under an hour, the time under a day, the weekday and the time
 *    under a week, else the month, day and time (kgl buckets), the time in
 *    the 12 or 24 hour format of Settings (use-12h-format);
 *  - R5 B-04: the sender row has the sender's 18 dp round avatar before the
 *    name, 4 dp apart (grw.java:7125-7170 am(): spacedBy 4, CircleShape 18),
 *    when the phone sent one (btsyncd's a, asked for when the card shows, as
 *    the message pictures: NotificationPicture); a run of the others' bubbles
 *    is also cut where a minute or more passed (kha.d, a = 60 s) when both
 *    messages have a time.
 * The messages come from asteroid-btsyncd's x-asteroid-messages hint (JSON:
 * s sender, t text, me the user's own, p the file of its picture with w, h,
 * a the file of the sender's avatar, ts the time in seconds).
 */
Column {
    id: conversation

    property QtObject notification
    // [{ s, t, me, p, size, a, ts }] oldest first, [] when the notification has none
    readonly property var messages: parse(notification)
    // the time the section headers are worded against: when the messages were read (no timer runs)
    property real nowMs: Date.now()
    onMessagesChanged: nowMs = Date.now()
    // Settings > System > Date & time: 12 hour times
    ConfigurationValue { id: use12h; key: "/org/asteroidos/settings/use-12h-format"; defaultValue: false }
    readonly property bool twelveHour: use12h.value === true || String(use12h.value) === "true"
    // the pictures the messages show
    readonly property var picturePaths: messages.filter(function (m) { return m.p !== "" }).map(function (m) { return m.p })

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
                           var ts = Number(m.ts) > 0 ? Number(m.ts) : 0
                           return { s: typeof m.s === "string" ? m.s : "", t: m.t, me: m.me === true, p: p, size: size,
                                    a: typeof m.a === "string" ? m.a : "", ts: ts }
                       })
                       .filter(function (m) { return m.t.length > 0 || m.p !== "" })
        } catch (e) {
            return []
        }
    }

    // two messages of one run: the same side, and the same sender for the others'; with both times, less than a
    // minute apart (kha.d: the same person within kha.a = 60 s)
    function sameRun(a, b) {
        if (!a || !b || a.me !== b.me)
            return false
        if (a.ts > 0 && b.ts > 0 && Math.abs(b.ts - a.ts) >= 60)
            return false
        return a.me || a.s === b.s
    }

    // a time section header before m (hfu.l: the first message, or an hour or more after the one before)
    function sectionShown(previous, m) {
        if (!m || !(m.ts > 0))
            return false
        return !previous || !(previous.ts > 0) || Math.abs(m.ts - previous.ts) >= 3600
    }
    // the header's words for a time ts (s) at now (ms) (kls.a with kgl's buckets)
    function sectionText(ts, now, twelve) {
        var when = new Date(ts * 1000)
        var age = now - ts * 1000
        var time = Qt.formatTime(when, twelve ? "h:mm AP" : "HH:mm")
        if (age >= 7 * 86400000)
            return Qt.formatDate(when, "MMM d") + ", " + time
        if (age >= 86400000)
            return Qt.formatDate(when, "ddd") + " " + time
        if (age >= 3600000)
            return time
        if (age >= 60000)
            //% "%1m ago"
            return qsTrId("id-conversation-minutes-ago").arg(Math.floor(age / 60000))
        //% "Now"
        return qsTrId("id-now")
    }

    readonly property real largeRadius: Theme.dp(22)      // 44 px
    readonly property real smallRadius: Theme.dp(4)       // 8 px
    readonly property real padX: Theme.dp(12)             // 24 px
    readonly property real padY: Theme.dp(10)             // 20 px
    readonly property real farInset: Math.round(0.0552 * Theme.dp(192))   // 21 px
    readonly property real bubbleMax: width - farInset
    readonly property real joinGap: Theme.dp(2)           // inside a run
    readonly property real runGap: Theme.dp(8)            // before a run (before its name)
    readonly property real avatarSize: Theme.dp(18)       // 36 px: the sender's avatar
    readonly property real avatarGap: Theme.dp(4)         // between the avatar and the name

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
            readonly property bool sectioned: conversation.sectionShown(previous, m)
            readonly property bool named: conversation.showSenders && !own && (!joinedAbove || sectioned) && m.s !== ""
            readonly property bool hasAvatar: named && m.a !== ""
            readonly property bool hasText: m.t.length > 0
            readonly property bool hasPicture: m.p !== ""
            readonly property real topGap: sectioned ? (index === 0 ? conversation.joinGap : conversation.runGap)
                                                     : index === 0 ? 0 : joinedAbove ? conversation.joinGap : conversation.runGap
            readonly property alias bubble: bubbleRect
            readonly property alias label: textLabel
            readonly property alias sender: senderLabel
            readonly property alias picture: bubblePicture
            readonly property alias section: sectionLabel
            readonly property alias avatar: senderAvatar

            width: conversation.width
            height: topGap + parts.height

            Column {
                id: parts
                y: message.topGap
                width: parent.width
                spacing: conversation.joinGap

                // the time section header: centred, one line
                Label {
                    id: sectionLabel
                    objectName: "sectionHeader"
                    visible: message.sectioned
                    width: conversation.width
                    height: message.sectioned ? implicitHeight : 0
                    horizontalAlignment: Text.AlignHCenter
                    text: message.sectioned ? conversation.sectionText(message.m.ts, conversation.nowMs, conversation.twelveHour) : ""
                    maximumLineCount: 1
                    elide: Text.ElideRight
                    role: "labelSmall"
                    color: Theme.color.onSurfaceVariant
                }

                // the sender: the 18 dp round avatar (when the phone sent one), 4 dp, the name
                Item {
                    id: senderRow
                    visible: message.named
                    x: conversation.padX
                    width: conversation.width - 2 * conversation.padX
                    height: message.named ? Math.max(senderLabel.implicitHeight, senderAvatar.visible ? senderAvatar.height : 0) : 0

                    NotificationPicture {
                        id: senderAvatar
                        objectName: "senderAvatar"
                        anchors.verticalCenter: parent.verticalCenter
                        width: conversation.avatarSize
                        maxHeight: conversation.avatarSize
                        radius: conversation.avatarSize / 2
                        picturePath: message.hasAvatar ? message.m.a : ""
                        pictureSize: "1x1"
                        showError: false
                    }
                    Label {
                        id: senderLabel
                        x: senderAvatar.visible ? senderAvatar.width + conversation.avatarGap : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x
                        text: message.m.s
                        color: Theme.color.onSurface
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        role: "labelSmall"
                    }
                }

                // the picture, before the text, on the sender's side
                NotificationPicture {
                    id: bubblePicture
                    objectName: "bubblePicture"
                    visible: message.hasPicture
                    width: conversation.bubbleMax
                    x: message.own ? conversation.width - width : 0
                    // at most square
                    maxHeight: width
                    radius: conversation.largeRadius
                    picturePath: message.m.p
                    pictureSize: message.m.size
                    showError: true
                }

                Rectangle {
                    id: bubbleRect
                    visible: message.hasText
                    width: textLabel.width + 2 * conversation.padX
                    height: message.hasText ? textLabel.height + 2 * conversation.padY : 0
                    x: message.own ? conversation.width - width : 0
                    color: message.own ? Theme.color.primaryDim : Theme.color.surfaceContainer
                    // the corners on the sender's side are small where the run goes on
                    readonly property real tl0: !message.own && message.joinedAbove && !message.hasPicture ? conversation.smallRadius : conversation.largeRadius
                    readonly property real bl0: !message.own && message.joinedBelow ? conversation.smallRadius : conversation.largeRadius
                    readonly property real tr0: message.own && message.joinedAbove && !message.hasPicture ? conversation.smallRadius : conversation.largeRadius
                    readonly property real br0: message.own && message.joinedBelow ? conversation.smallRadius : conversation.largeRadius
                    // as Compose's rounded shape: corners that would meet on a side shrink together
                    readonly property real fit: Math.min(1, height / Math.max(1, Math.max(tl0 + bl0, tr0 + br0)),
                                                         width / Math.max(1, Math.max(tl0 + tr0, bl0 + br0)))
                    topLeftRadius: tl0 * fit
                    bottomLeftRadius: bl0 * fit
                    topRightRadius: tr0 * fit
                    bottomRightRadius: br0 * fit

                    Label {
                        id: textLabel
                        x: conversation.padX
                        y: conversation.padY
                        // as wide as the text, at most the bubble's maximum
                        width: Math.min(implicitWidth, conversation.bubbleMax - 2 * conversation.padX)
                        text: message.m.t
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        role: "bodyLarge"
                        color: message.own ? Theme.color.onPrimary : Theme.color.onSurface
                    }
                }
            }
        }
    }
}
