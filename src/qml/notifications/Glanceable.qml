/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

pragma ComponentBehavior: Bound

import QtQuick
import org.asteroid.controls
import ".."
import "headsup.js" as HU

/*
 * A new notification on the watch face, full screen (audit heads-up-alerts-01,
 * -08; stock CP3A SysUI fullview_root_view.xml, ksx.java:74-200, 1230-1332,
 * klj.java:68-89), in the Wear OS 6 emulator's look (S09, raw/hsheet.png): a
 * black round screen; the notification's small icon bare and white (no disc)
 * in a 30 dp (60 px) box at the start, its glyph's ink from 9.9 % of the width
 * and 21.9 % of the height (a picture file is drawn as it is); under it the
 * title (the notification's title, else its text; the newest message of a
 * chat) 24 sp on a 27 sp line, at most 3 lines, start-aligned in the 9.2 %
 * side padding (its ink from x 39), its capitals' top at y 158 (a chat:
 * 26 / 29 sp, 2 lines, and the newest picture under it); and the app name
 * along the bottom edge, bold with no tracking (Noto Sans Bold stands in for
 * the emulator's heavy rounded face), 4 dp from the edge. The picture of a
 * chat is 104 dp with a pill radius of 41 dp, or 72 dp in a 116 x 96 dp box
 * for a group. px at 384; scaled by width / 384.
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
    // the icon's box (its glyph's ink starts 5 px in) and the title's side padding
    readonly property real iconTop: Math.round(HU.GLANCE.iconTopFraction * height) - Math.round(HU.GLANCE.iconInkInset * u)
    readonly property real iconStart: Math.round(HU.GLANCE.iconInkStartFraction * width) - Math.round(HU.GLANCE.iconInkInset * u)
    readonly property real sidePadding: Math.round(HU.GLANCE.sidePaddingFraction * width)
    readonly property real offset: HU.ENTRY.offsetFraction * height
    readonly property Item iconItem: iconBox
    readonly property Item titleItem: titleLabel
    readonly property Item pictureItem: pictureHolder
    readonly property Item nameItem: curvedName

    function iconOf(n) {
        function none(s) { return s === "" || s === null || s === undefined }
        if (!n)
            return ""
        if (!none(n.icon)) return n.icon
        if (!none(n.appIcon)) return n.appIcon
        return "ios-mail-outline"
    }
    readonly property string iconName: iconOf(notification)
    // an icon given as a picture file (a path or a URL) rather than a glyph name
    readonly property bool iconIsFile: iconName.charAt(0) === "/" || iconName.indexOf("file:") === 0

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

    // the small icon at the start (the end in a right-to-left language): a glyph in
    // onBackground, a picture file as it is; no container
    Item {
        id: iconBox
        width: Math.round(HU.GLANCE.iconSize * glance.u)
        height: width
        x: glance.LayoutMirroring.enabled ? glance.width - glance.iconStart - width : glance.iconStart
        y: glance.iconTop + (1 - glance.iconP) * glance.offset
        opacity: glance.iconP
        scale: HU.ENTRY.iconScaleFrom + (1 - HU.ENTRY.iconScaleFrom) * glance.iconP
        Icon {
            anchors.fill: parent
            visible: !glance.iconIsFile
            name: visible ? glance.iconName : ""
            color: Theme.color.onBackground
        }
        Image {
            anchors.fill: parent
            visible: glance.iconIsFile
            source: !visible ? "" : glance.iconName.charAt(0) === "/" ? "file://" + glance.iconName : glance.iconName
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    // the title, onBackground, start-aligned (horizontalAlignment left unset: a
    // right-to-left text and a mirrored layout align it to the right)
    Label {
        id: titleLabel
        x: glance.sidePadding
        width: glance.width - 2 * glance.sidePadding
        y: glance.iconTop + iconBox.height + HU.GLANCE.titleGap * glance.u + (1 - glance.titleP) * glance.offset
        text: glance.title
        font.pixelSize: Math.round(glance.titleSize * glance.u)
        font.weight: Font.Medium
        lineHeightMode: Text.FixedHeight
        lineHeight: Math.round((glance.chat ? HU.GLANCE.chatTitleLine : HU.GLANCE.titleLine) * glance.u)
        wrapMode: Text.Wrap
        maximumLineCount: glance.chat ? HU.GLANCE.chatTitleLines : HU.GLANCE.titleLines
        elide: Text.ElideRight
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

    // the app name along the bottom edge: arcMedium bold, no tracking
    BoldEdgeName {
        id: curvedName
        anchors.fill: parent
        text: glance.appName
        edgeMargin: Math.round(HU.GLANCE.nameEdge * glance.u)
        color: Theme.color.onBackground
        opacity: glance.nameP
    }

    /* CurvedText (org.asteroid.controls) with the arcMedium role at weight 700 and no
     * tracking (the role's own is 599 with 1.4 sp): its letters along the bottom edge,
     * read left to right, centred at 6 o'clock, their middle edgeMargin + half the
     * line from the edge, no wider than 120 degrees (an ellipsis past that) */
    component BoldEdgeName: Item {
        id: curved
        property string text: ""
        property color color: Theme.color.onBackground
        property real edgeMargin: Theme.dp(2)
        readonly property string role: "arcMedium"
        readonly property var _role: Theme.type.arcMedium
        readonly property real pixelSize: _role.pixelSize
        readonly property real lineHeight: _role.lineHeight
        readonly property int weight: Font.Bold
        readonly property real letterSpacing: 0
        readonly property real maxSweep: 120
        readonly property real radius: Math.min(width, height) / 2 - edgeMargin - lineHeight / 2
        readonly property var _chars: text.split("")
        readonly property var _widths: {
            var widths = []
            for (var i = 0; i < _chars.length; i++) {
                var item = _letters.count > i ? _letters.itemAt(i) : null
                widths.push(item ? item.implicitWidth : 0)
            }
            return widths
        }
        readonly property real _maxLength: maxSweep * Math.PI / 180 * Math.max(1, radius)
        // the whole text along the arc, px
        readonly property real naturalLength: {
            var t = 0
            for (var i = 0; i < _widths.length; i++)
                t += _widths[i]
            return t
        }
        readonly property bool fits: naturalLength <= _maxLength
        readonly property int _shown: {
            if (fits)
                return _widths.length
            var room = _maxLength - _ellipsis.implicitWidth
            var t = 0, n = 0
            while (n < _widths.length && t + _widths[n] <= room) {
                t += _widths[n]
                n++
            }
            return n
        }
        readonly property bool _elided: _shown < _chars.length
        readonly property real _length: {
            var t = 0
            for (var i = 0; i < _shown; i++)
                t += _widths[i]
            return t + (_elided ? _ellipsis.implicitWidth : 0)
        }
        readonly property var _mids: {
            var mids = []
            var x = -_length / 2
            for (var j = 0; j < _shown; j++) {
                mids.push(x + _widths[j] / 2)
                x += _widths[j]
            }
            mids.push(x + _ellipsis.implicitWidth / 2)
            return mids
        }

        Repeater {
            id: _letters
            model: curved._chars.length
            delegate: EdgeLetter {
                required property int index
                arc: curved
                visible: index < curved._shown
                text: curved._chars[index] !== undefined ? curved._chars[index] : ""
                along: curved._mids[index] !== undefined ? curved._mids[index] : 0
            }
        }
        EdgeLetter {
            id: _ellipsis
            arc: curved
            text: "…"
            visible: curved._elided
            along: curved._mids.length > 0 ? curved._mids[curved._mids.length - 1] : 0
        }
    }
    // one letter of BoldEdgeName (arc), turned to follow the edge
    component EdgeLetter: Text {
        property BoldEdgeName arc
        property real along: 0
        // radians from 6 o'clock, positive to the reader's right
        readonly property real angle: arc && arc.radius > 0 ? along / arc.radius : 0
        color: arc ? arc.color : "transparent"
        font.family: Theme.fontFamily
        font.pixelSize: arc ? arc.pixelSize : 1
        font.weight: Font.Bold
        // the role's width (90: SemiCondensed) at weight 700
        font.styleName: arc && arc._role.width < 95 ? "SemiCondensed Bold" : "Bold"
        font.letterSpacing: arc ? arc.letterSpacing : 0
        font.variableAxes: arc ? { "wght": arc.weight, "wdth": arc._role.width, "ROND": 100, "opsz": arc._role.opsz } : {}
        x: arc ? arc.width / 2 + arc.radius * Math.sin(angle) - width / 2 : 0
        y: arc ? arc.height / 2 + arc.radius * Math.cos(angle) - height / 2 : 0
        rotation: -angle * 180 / Math.PI
    }

    TapHandler {
        onTapped: glance.tapped()
    }
}
