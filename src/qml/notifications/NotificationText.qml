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

    spacing: Dims.h(1.5)

    function iconOf(n) {
        if (!n)
            return ""
        function none(s) { return s === "" || s === null || s === undefined }
        if (!none(n.icon)) return n.icon
        if (!none(n.appIcon)) return n.appIcon
        return "ios-mail-outline"
    }

    Row {
        spacing: Dims.w(2)
        width: parent.width
        Rectangle {
            width: Dims.l(8)
            height: width
            radius: width / 2
            color: "#33ffffff"
            anchors.verticalCenter: parent.verticalCenter
            Icon {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: width
                name: nt.iconOf(nt.notification)
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, nt.width - Dims.l(8) - timeLabel.width - Dims.w(4))
            elide: Text.ElideRight
            text: nt.notification ? nt.notification.appName : ""
            color: "#a8c7fa"
            font.pixelSize: Dims.l(5.6)
            font.styleName: "SemiCondensed Medium"
        }
        Label {
            id: timeLabel
            anchors.verticalCenter: parent.verticalCenter
            text: nt.timestamp !== "" ? "· " + nt.timestamp : ""
            opacity: 0.6
            font.pixelSize: Dims.l(5.6)
        }
    }

    Label {
        width: parent.width
        visible: text.length > 0
        text: nt.notification ? nt.notification.summary : ""
        wrapMode: Text.Wrap
        maximumLineCount: nt.compact ? 1 : 4
        elide: Text.ElideRight
        font.pixelSize: Dims.l(6.6)
        font.styleName: "SemiCondensed Medium"
    }

    NotificationConversation {
        id: conversationView
        width: parent.width
        visible: !nt.compact && messages.length > 0
        notification: nt.compact ? null : nt.notification
        onPictureTapped: (path, size) => nt.pictureTapped(path, size)
    }

    Label {
        width: parent.width
        visible: text.length > 0 && !conversationView.visible
        text: {
            var b = nt.notification ? nt.notification.body : ""
            if (!nt.compact)
                return b
            // a card shows the newest lines
            var lines = b.split("\n")
            return lines.slice(Math.max(0, lines.length - 2)).join("\n")
        }
        wrapMode: Text.Wrap
        maximumLineCount: nt.compact ? 2 : 40
        elide: Text.ElideRight
        opacity: 0.85
        font.pixelSize: Dims.l(6)
    }
}
