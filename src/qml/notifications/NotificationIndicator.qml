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
import "desktop.js" as Desktop

/*
 * The home screen's notification indicator. The AsteroidOS layout: the
 * notifications' icons at the top while the notification panels show. The
 * Wear layout: Wear OS's unread notification dot (ClockworkSysUiGoogle's
 * WatchFaceOverlayUi, Settings "Show unread notification dot", on by
 * default): a dot at the bottom of the watch face while a notification came
 * after the notification stream was last looked at; showing the stream
 * marks them all read, as stock (UnreadItemsTracker.markAllItemsRead).
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

    // notifications newer than the last look at the stream, and the newest's time
    property int unreadCount: 0
    property real newestTimestamp: 0
    readonly property bool streamShown: wearLayout && panelsGrid !== null
                                        && panelsGrid.currentHorizontalPos === 0 && panelsGrid.currentVerticalPos === 1
    onStreamShownChanged: if (streamShown) markAllRead()

    // a call has its own screen: not an unread notification
    function isCall(n) {
        var a = n && n.hints ? n.hints["x-asteroid-phone-actions"] : ""
        a = a ? String(a).split(",") : []
        return a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0 || a.indexOf("end") >= 0
    }

    function countUnread() {
        var seen = Number(seenUntil.value) || 0
        var count = 0
        var newest = 0
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (!n || !n.timestamp || isCall(n))
                continue
            var t = n.timestamp.getTime()
            if (isNaN(t))
                continue
            newest = Math.max(newest, t)
            if (t > seen)
                count++
        }
        newestTimestamp = newest
        unreadCount = count
        // looked at as it comes
        if (streamShown && count > 0)
            markAllRead()
    }

    function markAllRead() {
        if (unreadCount > 0 && newestTimestamp > (Number(seenUntil.value) || 0))
            seenUntil.value = newestTimestamp
    }

    Item {
        id: unreadDot
        objectName: "unreadDot"
        readonly property real offset: notifIndic.panelsGrid
                                       ? Math.abs(notifIndic.panelsGrid.normalizedHorOffset) + Math.abs(notifIndic.panelsGrid.normalizedVerOffset)
                                       : 0
        width: Dims.l(2.8)
        height: width
        x: (notifIndic.width - width) / 2
        // its middle Dims.h(5.5) above the bottom of the screen
        y: (notifIndic.parent ? notifIndic.parent.height : notifIndic.height) - notifIndic.y - Dims.h(5.5) - height / 2
        // fades as the watch face is swiped away; grey on the always-on display, as the face
        opacity: Math.max(0, 1 - 3 * offset) * (Lipstick.compositor.displayAmbient ? 0.55 : 1)
        visible: notifIndic.wearLayout && unreadDotSetting.value !== false && notifIndic.unreadCount > 0 && opacity > 0

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"
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
