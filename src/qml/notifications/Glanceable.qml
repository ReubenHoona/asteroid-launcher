/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import ".."
import "headsup.js" as HU

/*
 * A new notification on the watch face, full screen (audit heads-up-alerts-01,
 * -08; stock CP3A SysUI fullview_root_view.xml, ksx.java:74-200, 1230-1332,
 * klj.java:68-89): a black round screen; the primary icon (30 dp, 60 px) with
 * its top at 19.6 % of the height; below it, 6 dp on, the title (the newest
 * message of a chat, else the text) 24 sp on a 27 sp line, at most 3 lines,
 * centred in the 9.2 % side padding (a chat: 26 / 29 sp, 2 lines, and the
 * newest picture under it); and the app name along the bottom edge (arcMedium,
 * 4 dp from the edge). The picture of a chat is 104 dp with a pill radius of
 * 41 dp, or 72 dp in a 116 x 96 dp box for a group. px at 384; scaled by
 * width / 384.
 *
 * It comes in on springs of damping 1 (ksx.java): the icon, the picture and
 * the title fade in from 10 % of the screen height below (stiffness 260, the
 * slow spec), the icon from scale 0.75, the picture from 0.88 on stiffness
 * 130; the title and the app name 67 ms after the icon. Nothing animates once
 * it is in; stop() ends it at once (the display going off).
 */
Item {
    id: glance

    property QtObject notification: null
    readonly property real u: width / 384

    // the first screen of the full notification view follows after this (the preview)
    signal tapped()

    readonly property bool chat: HU.isChat(notification)
    readonly property bool group: HU.isGroup(notification)
    readonly property string title: HU.titleOf(notification)
    readonly property string picturePath: chat ? HU.pictureOf(notification) : ""
    readonly property string appName: notification ? String(notification.appName) : ""
    readonly property int titleSize: chat ? HU.GLANCE.chatTitleSize : HU.GLANCE.titleSize

    // the entry's progress, 0 .. 1 each (springs)
    property real iconP: 1
    property real photoP: 1
    property real photoScaleP: 1
    property real titleP: 1
    property real nameP: 1
    readonly property bool animating: iconSpring.running || photoSpring.running
                                      || photoScaleSpring.running || titleSpring.running || nameSpring.running
                                      || delay.running
    // the springs, for the tests
    readonly property QtObject iconAnimation: iconSpring
    readonly property QtObject photoAnimation: photoSpring
    readonly property QtObject photoScaleAnimation: photoScaleSpring
    readonly property QtObject titleAnimation: titleSpring
    readonly property QtObject nameAnimation: nameSpring
    readonly property Timer entryDelay: delay

    // the geometry, for the tests
    readonly property real iconTop: Math.round(HU.GLANCE.iconTopFraction * height)
    readonly property real sidePadding: Math.round(HU.GLANCE.sidePaddingFraction * width)
    readonly property real offset: HU.ENTRY.offsetFraction * height
    readonly property Item iconItem: iconCircle
    readonly property Item titleItem: titleLabel
    readonly property Item pictureItem: pictureHolder
    readonly property Item nameItem: curvedName

    function accentOf(n) {
        var h = n && n.hints ? n.hints["x-asteroid-accent-color"] : undefined
        var c = h ? String(h).replace("#", "") : ""
        return /^[0-9a-fA-F]{6}$/.test(c) ? "#" + c : Theme.color.primary
    }
    function iconOf(n) {
        function none(s) { return s === "" || s === null || s === undefined }
        if (!n)
            return ""
        if (!none(n.icon)) return n.icon
        if (!none(n.appIcon)) return n.appIcon
        return "ios-mail-outline"
    }

    // From the start: everything comes in
    function start() {
        delay.stop()
        iconSpring.snapTo(0)
        photoSpring.snapTo(0)
        photoScaleSpring.snapTo(0)
        titleSpring.snapTo(0)
        nameSpring.snapTo(0)
        iconSpring.animateTo(1)
        photoSpring.animateTo(1)
        photoScaleSpring.animateTo(1)
        if (Motion.animationScale > 0) {
            delay.interval = HU.ENTRY.titleDelayMs
            delay.restart()
        } else {
            titleSpring.animateTo(1)
            nameSpring.animateTo(1)
        }
    }

    // the end at once: all in, nothing running
    function stop() {
        delay.stop()
        iconSpring.stop(); photoSpring.stop(); photoScaleSpring.stop(); titleSpring.stop(); nameSpring.stop()
        iconP = 1; photoP = 1; photoScaleP = 1; titleP = 1; nameP = 1
    }

    // a single shot, only during the entry: the title and the app name start 67 ms late
    Timer {
        id: delay
        repeat: false
        onTriggered: {
            titleSpring.animateTo(1)
            nameSpring.animateTo(1)
        }
    }
    WearSpring { id: iconSpring; target: glance; property: "iconP"; stiffness: HU.ENTRY.stiffness; dampingRatio: 1; visibilityThreshold: 0.001 }
    WearSpring { id: photoSpring; target: glance; property: "photoP"; stiffness: HU.ENTRY.stiffness; dampingRatio: 1; visibilityThreshold: 0.001 }
    WearSpring { id: photoScaleSpring; target: glance; property: "photoScaleP"; stiffness: HU.ENTRY.photoScaleStiffness; dampingRatio: 1; visibilityThreshold: 0.001 }
    WearSpring { id: titleSpring; target: glance; property: "titleP"; stiffness: HU.ENTRY.stiffness; dampingRatio: 1; visibilityThreshold: 0.001 }
    WearSpring { id: nameSpring; target: glance; property: "nameP"; stiffness: HU.ENTRY.stiffness; dampingRatio: 1; visibilityThreshold: 0.001 }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    // the primary icon
    Rectangle {
        id: iconCircle
        width: Math.round(HU.GLANCE.iconSize * glance.u)
        height: width
        radius: width / 2
        x: (glance.width - width) / 2
        y: glance.iconTop + (1 - glance.iconP) * glance.offset
        color: glance.accentOf(glance.notification)
        opacity: glance.iconP
        scale: HU.ENTRY.iconScaleFrom + (1 - HU.ENTRY.iconScaleFrom) * glance.iconP
        Icon {
            anchors.centerIn: parent
            width: Math.round(parent.width * HU.GLANCE.glyphFraction)
            height: width
            name: glance.iconOf(glance.notification)
            color: Theme.color.onPrimary
        }
    }

    // the title, onBackground, centred
    Label {
        id: titleLabel
        x: glance.sidePadding
        width: glance.width - 2 * glance.sidePadding
        y: glance.iconTop + iconCircle.height + HU.GLANCE.titleGap * glance.u + (1 - glance.titleP) * glance.offset
        text: glance.title
        font.pixelSize: Math.round(glance.titleSize * glance.u)
        font.weight: Font.Medium
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round((glance.chat ? HU.GLANCE.chatTitleLine : HU.GLANCE.titleLine) * glance.u)
        wrapMode: Text.Wrap
        maximumLineCount: glance.chat ? HU.GLANCE.chatTitleLines : HU.GLANCE.titleLines
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: Theme.color.onBackground
        opacity: glance.titleP
    }

    // a conversation's newest picture: 104 dp with a pill radius (one to one), a 72 dp
    // picture in a 116 x 96 dp box (a group). What the title leaves of the round
    // screen above the app name is all it may take.
    Item {
        id: pictureHolder
        visible: glance.picturePath !== ""
        readonly property real topY: titleLabel.y + titleLabel.height + Math.round(4 * glance.u)
        readonly property real room: Math.max(0, glance.height - Math.round(48 * glance.u) - topY)
        width: glance.group ? Math.round(HU.GLANCE.groupBoxWidth * glance.u) : Math.round(HU.GLANCE.picture * glance.u)
        height: Math.min(room, glance.group ? Math.round(HU.GLANCE.groupBoxHeight * glance.u) : Math.round(HU.GLANCE.picture * glance.u))
        x: (glance.width - width) / 2
        y: topY + (1 - glance.photoP) * glance.offset
        opacity: glance.photoP
        scale: HU.ENTRY.photoScaleFrom + (1 - HU.ENTRY.photoScaleFrom) * glance.photoScaleP

        Rectangle {
            anchors.fill: parent
            visible: glance.group
            radius: Math.round(HU.GLANCE.pictureRadius * glance.u)
            color: Theme.color.surfaceContainer
        }
        NotificationPicture {
            id: photo
            anchors.centerIn: parent
            width: glance.group ? Math.round(HU.GLANCE.groupPicture * glance.u) : parent.width
            maxHeight: parent.height
            radius: glance.group ? Math.round(HU.GLANCE.groupPicture * glance.u / 2) : Math.round(HU.GLANCE.pictureRadius * glance.u)
            picturePath: glance.picturePath
            notification: glance.notification
        }
    }

    // the app name along the bottom edge
    CurvedText {
        id: curvedName
        anchors.fill: parent
        text: glance.appName
        role: "arcMedium"
        edgeMargin: Math.round(HU.GLANCE.nameEdge * glance.u)
        color: Theme.color.onBackground
        opacity: glance.nameP
    }

    TapHandler {
        onTapped: glance.tapped()
    }
}
