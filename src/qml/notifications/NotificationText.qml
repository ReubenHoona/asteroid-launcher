/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

// The whole of a notification, as Wear OS opens a card: the app's icon,
// name and time, the title, and every line of the text (a conversation's
// messages, one per line, as asteroid-btsyncd writes them; opened, with
// asteroid-btsyncd's x-asteroid-messages, as Wear OS's message bubbles:
// NotificationConversation)
Column {
    id: nt

    property QtObject notification
    property string timestamp: ""
    property bool compact: false
    // the pictures the conversation's bubbles show; a tap on one
    readonly property var bubblePictures: conversationView.visible ? conversationView.picturePaths : []
    signal pictureTapped(string path, string size)

    spacing: 0

    function iconOf(n) {
        if (!n)
            return ""
        function none(s) { return s === "" || s === null || s === undefined }
        if (!none(n.icon)) return n.icon
        if (!none(n.appIcon)) return n.appIcon
        return "ios-mail-outline"
    }

    // The accent colour of the app's icon circle: the phone's hint when it
    // sends one (x-asteroid-accent-color, "RRGGBB"), else primary (kxr.java:48-230)
    function accentOf(n) {
        var h = n && n.hints ? n.hints["x-asteroid-accent-color"] : undefined
        var c = h ? String(h).replace("#", "") : ""
        return /^[0-9a-fA-F]{6}$/.test(c) ? "#" + c : Theme.color.primary
    }

    // A conversation card shows its newest lines when collapsed (stock shows the
    // newest message); a plain notification shows the start of its text
    readonly property bool conversation: {
        var h = notification && notification.hints ? notification.hints["x-asteroid-messages"] : undefined
        return h !== undefined && h !== null && String(h) !== ""
    }

    // The header (E08-E10, grw.java:7450-7712): a 24 dp circle in the app's
    // accent with an 18 dp glyph in onPrimary, 6 dp, the app name (titleSmall,
    // onSurfaceVariant, takes the free width), 6 dp, the time (bodyMedium,
    // onSurfaceVariant, at the end: "Now", "5m", "2h", "1d", no dot)
    Item {
        id: header
        width: parent.width
        height: iconCircle.height
        readonly property real gap: Theme.dp(6)

        Rectangle {
            id: iconCircle
            width: Theme.dp(24)
            height: width
            radius: width / 2
            color: nt.accentOf(nt.notification)
            Icon {
                anchors.centerIn: parent
                width: Theme.dp(18)
                height: width
                name: nt.iconOf(nt.notification)
                color: Theme.color.onPrimary
            }
        }
        Label {
            id: appLabel
            x: iconCircle.width + header.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, header.width - x - header.gap - timeLabel.width)
            elide: Text.ElideRight
            maximumLineCount: 1
            text: nt.notification ? nt.notification.appName : ""
            role: "titleSmall"
            color: Theme.color.onSurfaceVariant
        }
        Label {
            id: timeLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: nt.timestamp
            role: "bodyMedium"
            color: Theme.color.onSurfaceVariant
        }
    }

    // 2 dp between the header and the title (grw.java:6163-6190 padding top 2 dp)
    Item {
        width: 1
        height: titleLabel.visible ? Theme.dp(2) : 0
    }

    // The title: titleMedium (16 sp on an 18 sp line, weight 550), tertiary, two
    // lines in a card (collapsed_card_title_max_lines 2)
    Label {
        id: titleLabel
        width: parent.width
        visible: text.length > 0
        text: nt.notification ? nt.notification.summary : ""
        wrapMode: Text.Wrap
        maximumLineCount: nt.compact ? 2 : 4
        elide: Text.ElideRight
        role: "titleMedium"
        color: Theme.color.tertiary
    }

    NotificationConversation {
        id: conversationView
        width: parent.width
        visible: !nt.compact && messages.length > 0
        notification: nt.compact ? null : nt.notification
        onPictureTapped: (path, size) => nt.pictureTapped(path, size)
    }

    // The body: bodyLarge (16 sp on an 18 sp line, weight 450), onSurfaceVariant,
    // two lines in a card (collapsed_card_body_max_lines 2, grw.java:8011-8040)
    Label {
        width: parent.width
        visible: text.length > 0 && !conversationView.visible
        text: {
            var b = nt.notification ? nt.notification.body : ""
            if (!nt.compact || !nt.conversation)
                return b
            var lines = b.split("\n")
            return lines.slice(Math.max(0, lines.length - 2)).join("\n")
        }
        wrapMode: Text.Wrap
        maximumLineCount: nt.compact ? 2 : 40
        elide: Text.ElideRight
        role: "bodyLarge"
        color: Theme.color.onSurfaceVariant
    }
}
