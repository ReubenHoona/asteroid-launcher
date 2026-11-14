/*
 * Copyright (C) 2017 Florent Revest <revestflo@gmail.com>
 * All rights reserved.
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of the author nor the
 *       names of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import QtQuick
import Nemo.Configuration
import org.nemomobile.lipstick
import org.asteroid.controls
import QtQuick.Shapes
import "desktop.js" as Desktop
import "home/unread.js" as Unread

/*
 * The home screen's notification indicator. The AsteroidOS layout: the
 * notifications' icons at the top while the notification panels show. The
 * Wear layout: Wear OS's unread notification indicator (CP3A Koru overlay,
 * Settings "Show unread notification indicator", on by default): a short bar
 * at 6 o'clock on the watch face (an arc segment of the screen's edge circle:
 * stroke 4 dp, round caps, 16 dp long, white, over a soft black pill; it
 * slides up 5 dp in 500 ms when it shows, nai.java:33-58, overlay.css) while a
 * notification came after the notification stream was last looked at. What
 * counts and what marks it read is stock's UnreadItemsTracker (home/unread.js):
 * a new item is unread, a newer revision of a read one is unread again, showing
 * the stream marks them all read, opening one notification from a heads-up
 * marks only that one (W2-launcher-status, status-indicators-05, -08).
 * dconf /org/asteroidos/notifications/unread-dot false hides it; when the
 * stream was last seen is kept in /org/asteroidos/notifications/seen-until
 * (ms since the epoch, over restarts: lipstick keeps its notifications).
 */
Item {
    id: notifIndic
    property QtObject panelsGrid
    property real iconSize: height
    property int currentIndex
    property var icons: []

    // the Wear layout (MainScreen's, read once it is set up)
    property bool wearLayout: true
    Component.onCompleted: Qt.callLater(function () {
        notifIndic.homeDesktop = Desktop.desktop
        notifIndic.wearLayout = !Desktop.desktop || Desktop.desktop.wearLayout !== false
        notifIndic.countUnread()
    })

    ConfigurationValue {
        id: unreadDotSetting
        key: "/org/asteroidos/notifications/unread-dot"
        defaultValue: true
    }
    ConfigurationValue {
        id: seenUntil
        key: "/org/asteroidos/notifications/seen-until"
        defaultValue: 0
        onValueChanged: notifIndic.countUnread()
    }

    // notifications newer than the last look at the stream and not read one by one, and the newest's time
    property int unreadCount: 0
    property real newestTimestamp: 0
    // read one by one (opened from a heads-up or the glanceable view): {id: revision}
    property var readItems: ({})
    // the full view of one notification is open from a heads-up (MainScreen.openNotification): the
    // stream under it is not "looked at" until that view is closed
    property bool fromHeadsUp: false
    // the home screen (set once it is up) and its notification stream
    property var homeDesktop: null
    readonly property var streamItem: homeDesktop ? homeDesktop.streamItem : null
    readonly property bool streamShown: wearLayout && panelsGrid !== null
                                        && panelsGrid.currentHorizontalPos === 0 && panelsGrid.currentVerticalPos === 1
    onStreamShownChanged: {
        if (streamShown) {
            // opening the stream marks all read (jui.java:33-55), not when it opens for one notification
            if (!fromHeadsUp)
                markAllRead()
        } else {
            fromHeadsUp = false
        }
    }
    Connections {
        target: notifIndic.streamItem
        ignoreUnknownSignals: true
        // the notification's view is closed with the stream still showing: the list is looked at now
        function onExpandedIdChanged() {
            if (notifIndic.fromHeadsUp && notifIndic.streamItem.expandedId < 0 && notifIndic.streamShown) {
                notifIndic.fromHeadsUp = false
                notifIndic.markAllRead()
            }
        }
    }
    // the dot is wanted (the setting is on and a notification is unread): the
    // always-on layout of the sensor hub has it from the grab, so a change of
    // this rebuilds that layout (AmbientController, ambient-aod-10)
    readonly property bool dotWanted: wearLayout && unreadDotSetting.value !== false && unreadCount > 0

    // a call has its own screen: not an unread notification
    function isCall(n) {
        var a = n && n.hints ? n.hints["x-asteroid-phone-actions"] : ""
        a = a ? String(a).split(",") : []
        return a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0 || a.indexOf("end") >= 0
    }

    function items() {
        var l = []
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n)
                l.push(n)
        }
        return l
    }

    function countUnread() {
        var l = items()
        var seen = Number(seenUntil.value) || 0
        // a read mark of an item that is gone is dropped
        var pruned = Unread.prune(readItems, l)
        if (Object.keys(pruned).length !== Object.keys(readItems).length)
            readItems = pruned
        var r = Unread.summarize(l, seen, readItems)
        newestTimestamp = r.newest
        unreadCount = r.count
        // looked at as it comes (not while only one notification's view is open)
        if (streamShown && r.count > 0 && !fromHeadsUp)
            markAllRead()
    }

    // The stream was looked at: everything is read
    function markAllRead() {
        if (unreadCount > 0 && newestTimestamp > (Number(seenUntil.value) || 0))
            seenUntil.value = newestTimestamp
        if (Object.keys(readItems).length > 0)
            readItems = ({})
    }

    // One notification was opened from a heads-up or the glanceable view: only it is read
    // (enj.java:285-296); the stream that opens under its view does not mark the others
    function openedFromHeadsUp(n) {
        readItems = Unread.markRead(readItems, n)
        fromHeadsUp = true
        countUnread()
    }

    /* The unread bar (CP3A Koru overlay, nai.java:33-58, assets/overlay.css): an arc segment of
     * the screen's edge circle at 6 o'clock, stroke 4 dp (8 px), round caps, 16 dp (32 px) long
     * end to end, white; its centre line 4 px inside the edge (radius screen/2 - stroke/2). The
     * sweep is 2 atan(((length - stroke) / 2) / radius) = 7.2 degrees on the 192 dp screen. Under
     * it a soft black pill 32 x 8 dp (64 x 16 px) at 80 %, its bottom 2 dp (4 px) under the screen
     * edge (the stock one is a blurred picture; ours is three stacked pills of the same box).
     * It slides up 5 dp (10 px) in 500 ms, cubic-bezier(0, 0, 0, 1), when it shows and back down
     * when it goes; in the always-on screen no animation. It fades as the face is swiped away.
     * The always-on layout of the sensor hub has it from the grab (ambient-aod-10). */
    Item {
        id: unreadBar
        objectName: "unreadBar"
        readonly property real offset: notifIndic.panelsGrid
                                       ? Math.abs(notifIndic.panelsGrid.normalizedHorOffset) + Math.abs(notifIndic.panelsGrid.normalizedVerOffset)
                                       : 0
        // the screen, in this item's own coordinates
        readonly property real screenW: notifIndic.parent ? notifIndic.parent.width : Dims.w(100)
        readonly property real screenH: notifIndic.parent ? notifIndic.parent.height : Dims.h(100)
        readonly property real strokeW: Theme.dp(Unread.BAR_STROKE_DP)
        readonly property real lengthW: Theme.dp(Unread.BAR_LENGTH_DP)
        readonly property real arcRadius: screenW / 2 - strokeW / 2
        readonly property real sweep: Unread.barSweepDeg(screenW, lengthW, strokeW)
        readonly property real slideDistance: Theme.dp(Unread.BAR_SLIDE_DP)
        readonly property bool wanted: notifIndic.dotWanted
        // the bar's rest is 0, away it is 5 dp down
        property real shift: wanted ? 0 : slideDistance
        readonly property bool animated: !Lipstick.compositor.displayAmbient && Motion.animationScale > 0
        Behavior on shift {
            enabled: unreadBar.animated
            NumberAnimation {
                duration: Motion.duration(Unread.BAR_SLIDE_MS)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.easing.standardDecelerate
            }
        }
        x: 0
        y: -notifIndic.y
        width: screenW
        height: screenH
        // fades as the watch face is swiped away (the same in the always-on screen)
        opacity: Math.max(0, 1 - 3 * offset)
        visible: (wanted || shift < slideDistance) && opacity > 0

        Item {
            id: barGroup
            anchors.fill: parent
            transform: Translate { y: unreadBar.shift }

            // the soft black pill: 64 x 16 px, its bottom 4 px under the edge; three layers, the
            // middle of it 80 % black, the rim soft
            Repeater {
                model: [ { w: 1.0, h: 1.0, a: 0.35 }, { w: 0.8, h: 0.8, a: 0.4 }, { w: 0.6, h: 0.6, a: 0.55 } ]
                delegate: Rectangle {
                    objectName: "unreadPill" + index
                    readonly property real boxW: Theme.dp(Unread.PILL_W_DP)
                    readonly property real boxH: Theme.dp(Unread.PILL_H_DP)
                    width: boxW * modelData.w
                    height: boxH * modelData.h
                    radius: height / 2
                    color: "#000000"
                    opacity: modelData.a
                    x: (unreadBar.width - width) / 2
                    // centred in the box whose bottom is 2 dp under the screen edge
                    y: unreadBar.height + Theme.dp(Unread.PILL_BELOW_DP) - boxH + (boxH - height) / 2
                }
            }

            Shape {
                id: arc
                objectName: "unreadArc"
                anchors.fill: parent
                ShapePath {
                    strokeColor: "#ffffff"
                    strokeWidth: unreadBar.strokeW
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: unreadBar.width / 2
                        centerY: unreadBar.height / 2
                        radiusX: unreadBar.arcRadius
                        radiusY: unreadBar.arcRadius
                        // 90 degrees is 6 o'clock (clockwise from 3 o'clock)
                        startAngle: 90 - unreadBar.sweep / 2
                        sweepAngle: unreadBar.sweep
                    }
                }
            }
        }
    }

    // the AsteroidOS layout's icons
    Item {
        id: legacy
        anchors.fill: parent
        visible: false

        Item {
            id: content
            x: notifIndic.width/2

            Rectangle {
                id: separator
                visible: notifModel.itemCount !== 0
                x: iconSize*1.1
                width: 1
                height: iconSize
                color: "#8e8e8e"
            }

            Icon {
                visible: notifModel.itemCount !== 0
                name: "ios-time"
                color: "#8e8e8e"
                width: iconSize
                height: iconSize
                anchors.leftMargin: iconSize/10
                anchors.left: separator.right
            }
        }
    }

    Component {
        id: iconComponent;
        Icon {
            property QtObject notification
            property int index: 0
            
            name: {
                if(notification==null)
                    return "";

                function noicon(str) {
                    return str === "" || str === null || str === undefined;
                }
                if(noicon(notification.icon) && noicon(notification.appIcon))
                    return "ios-mail-outline";
                if(noicon(notification.icon) && !noicon(notification.appIcon))
                    return notification.appIcon;
                if(!noicon(notification.icon) && noicon(notification.appIcon))
                    return notification.icon;

                return notification.icon;
            }
            color: index == notifIndic.currentIndex ? "#FFFFFF" : "#8e8e8e"
        }
    }

    function addIcon(pos, item) {
        if (iconComponent.status === Component.Ready) {
            var icon = iconComponent.createObject(content)
            icon.x = iconSize*pos
            icon.y = 0
            icon.width = iconSize
            icon.height = iconSize
            icon.notification = item
            icon.index = pos
            icons[pos] = icon
        }
    }

    function moveIcon(originPos, destPos) {
        var icon = icons[originPos]
        if(icon !== undefined) {
            icons[destPos] = icon
            icon.x = iconSize*destPos
            icon.index = destPos
            icons[originPos] = undefined
        }
    }

    function removeIcon(pos) {
        var icon = icons[pos]
        if(icon !== undefined)
            icon.destroy()
        icons[pos] = undefined
    }

    function moveTo(pos) {
        content.x = notifIndic.width/2 - iconSize/2 -iconSize*pos
        currentIndex = pos
    }

    Connections {
        target: panelsGrid

        function makeVisible() {
            if((panelsGrid.currentVerticalPos == 0 && panelsGrid.currentHorizontalPos < 0) && !Lipstick.compositor.displayAmbient) {
                legacy.visible = true
                moveTo(panelsGrid.currentHorizontalPos+1)
            } else
                legacy.visible = false
        }

        function onCurrentHorizontalPosChanged() { makeVisible() }
        function onCurrentVerticalPosChanged() { makeVisible() }
    }

    NotificationListModel {
        id: notifModel
        onItemAdded: (item) => {
            var index = notifModel.indexOf(item)

            var leftIconIndex = notifModel.itemCount
            while(leftIconIndex > index) {
                moveIcon(-leftIconIndex+1, (-leftIconIndex))
                leftIconIndex--
            }

            addIcon(-index, item)
            notifIndic.countUnread()
        }

        onRowsRemoved: (parent, first, last) => {
            for (var i = first ; i <= last; i++)
                removeIcon(-i)

            for (var i = last+1 ; i <= notifModel.itemCount+1; i++)
                moveIcon(-i, -i+(last-first+1))
            notifIndic.countUnread()
        }
    }
    // an update in place (lipstick's model: dataChanged, or moved to the top); a model
    // without these signals (a test double) is fine
    Connections {
        target: notifModel
        ignoreUnknownSignals: true
        function onDataChanged() { notifIndic.countUnread() }
        function onRowsMoved() { notifIndic.countUnread() }
    }
}
