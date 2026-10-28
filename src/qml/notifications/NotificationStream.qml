/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.lipstick
import org.asteroid.controls

/*
 * The notification stream of the Wear layout, under the watchface (swipe
 * up), as Wear OS shows it: one card per app, newest first, the crown and a
 * finger scroll it, the cards shrink and fade at the round edges. An app
 * with several notifications (asteroid-btsyncd already makes one card per
 * conversation, with its messages) shows its newest with "+N"; a tap opens
 * the group, a tap on a card opens the whole notification with its
 * actions, replies and voice replies (NotificationActions), a swipe right
 * from the edge comes back. A card swiped sideways is dismissed (a closed
 * group: all of it), "Clear all" at the end dismisses everything.
 */
Item {
    id: stream

    property QtObject panelsGrid
    readonly property bool modelEmpty: notifModel.itemCount === 0

    // the panels grid: back to the watchface with a swipe down only from the
    // top of the list and from the list itself
    property bool forbidLeft: true
    property bool forbidRight: true
    property bool forbidBottom: true
    property bool forbidTop: stack.layers.length > 0 || (listView !== null && !listView.atYBeginning)
    onForbidTopChanged: if (panelsGrid) panelsGrid.changeAllowedDirections()

    readonly property Item listView: stack.firstPageItem ? stack.firstPageItem.list : null

    // the groups, newest first: key -> notifications, newest first
    property var groupItems: ({})
    property int revision: 0
    property string expandedKey: ""
    // the relative times are worked out again when the stream shows, and
    // every minute while it does
    property int clockTick: 0

    function keyOf(n) {
        return n && n.appName ? n.appName : "?"
    }

    function itemsOf(key, rev) {
        return groupItems[key] || []
    }

    function rebuild() {
        var map = {}
        var order = []
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (!n)
                continue
            var k = keyOf(n)
            if (!map[k]) {
                map[k] = []
                order.push(k)
            }
            map[k].push(n)
        }
        groupItems = map
        // move the list model to the new order with the least changes, so
        // cards that stay keep their delegates (and nothing jumps)
        for (var r = groups.count - 1; r >= 0; r--) {
            if (order.indexOf(groups.get(r).key) < 0)
                groups.remove(r)
        }
        for (var j = 0; j < order.length; j++) {
            var at = -1
            for (var m = j; m < groups.count; m++) {
                if (groups.get(m).key === order[j]) { at = m; break }
            }
            if (at < 0)
                groups.insert(j, { key: order[j] })
            else if (at !== j)
                groups.move(at, j, 1)
        }
        if (expandedKey !== "" && !map[expandedKey])
            expandedKey = ""
        revision++
    }

    function dismiss(list) {
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].userRemovable)
                list[i].removeRequested()
        }
    }

    function clearAll() {
        var all = []
        for (var i = 0; i < notifModel.itemCount; i++)
            all.push(notifModel.get(i))
        dismiss(all)
        Haptics.click()
    }

    function openDetail(n) {
        stack.push(detailPage, { notification: n })
    }

    function ago(n, tick) {
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

    // back to the top, closed, once the user has left the stream: done when
    // it is hidden (not as the user leaves: that was work in the first
    // frames of the glide away), and only when something is to be undone
    function reset() {
        while (stack.layers.length > 0)
            stack.pop(stack.currentLayer)
        expandedKey = ""
        // the top with its margin (positionViewAtBeginning() goes past it,
        // and the list would then not be at its beginning)
        if (listView && !listView.atYBeginning) {
            listView.cancelFlick()
            listView.contentY = listView.originY - listView.topMargin
        }
    }
    function needsReset() {
        return stack.layers.length > 0 || expandedKey !== "" || (listView !== null && !listView.atYBeginning)
    }

    onVisibleChanged: {
        if (visible)
            clockTick++
        else if (needsReset())
            reset()
    }
    Timer {
        interval: 60000
        repeat: true
        running: stream.visible && !stream.modelEmpty
        onTriggered: stream.clockTick++
    }

    Connections {
        target: stream.panelsGrid
        function onCurrentVerticalPosChanged() {
            stream.panelsGrid.changeAllowedDirections()
        }
    }

    ListModel { id: groups }

    NotificationListModel {
        id: notifModel
        // lipstick restores its notifications in one batch: build once
        onItemAdded: rebuildSoon.restart()
        onRowsRemoved: rebuildSoon.restart()
        onRowsMoved: rebuildSoon.restart()
        Component.onCompleted: rebuildSoon.restart()
    }
    Timer {
        id: rebuildSoon
        interval: 0
        onTriggered: stream.rebuild()
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#000000"
    }

    LayerStack {
        id: stack
        win: null
        firstPage: listPage
        // a reply page open in the notification goes back first
        gesturesEnabled: !(currentLayer && currentLayer.innerDepth > 0)
    }

    Component {
        id: listPage

        Item {
            property alias list: lv

            ListView {
                id: lv
                anchors.fill: parent
                model: groups
                spacing: Math.round(stream.height * 0.02)
                topMargin: Math.round(stream.height * 0.15)
                bottomMargin: Math.round(stream.height * 0.1)
                boundsBehavior: Flickable.DragOverBounds
                cacheBuffer: stream.height
                visible: !stream.modelEmpty

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 150 }
                }
                displaced: Transition {
                    NumberAnimation {
                        properties: "y"; duration: 250
                        easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
                    }
                }

                delegate: Item {
                    id: group
                    width: lv.width
                    height: col.height
                    readonly property string groupKey: model.key
                    readonly property var items: stream.itemsOf(groupKey, stream.revision)
                    readonly property bool expanded: stream.expandedKey === groupKey && items.length > 1

                    EdgeEffect { id: edge; item: group }
                    transform: Scale {
                        origin.x: group.width / 2
                        origin.y: group.height / 2
                        xScale: edge.scale
                        yScale: edge.scale
                    }

                    Column {
                        id: col
                        width: Math.round(lv.width * 0.84)
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Math.round(stream.height * 0.015)
                        opacity: edge.alpha

                        // an open group: its name, a tap closes it
                        MouseArea {
                            visible: group.expanded
                            width: col.width
                            height: Math.round(stream.height * 0.1)
                            onClicked: stream.expandedKey = ""
                            Label {
                                anchors.centerIn: parent
                                text: group.groupKey + "  ·  " + group.items.length
                                color: "#a8c7fa"
                                font.pixelSize: Dims.l(5.8)
                                font.styleName: "SemiCondensed Medium"
                            }
                        }

                        Repeater {
                            model: group.expanded ? group.items.length : Math.min(1, group.items.length)
                            delegate: NotificationCard {
                                width: col.width
                                notification: group.items[index] || null
                                extra: group.expanded ? 0 : group.items.length - 1
                                timestamp: stream.ago(notification, stream.clockTick)
                                onTapped: {
                                    Haptics.click()
                                    if (!group.expanded && group.items.length > 1)
                                        stream.expandedKey = group.groupKey
                                    else
                                        stream.openDetail(notification)
                                }
                                onDismissed: stream.dismiss(group.expanded || group.items.length === 1
                                                            ? [notification] : group.items)
                            }
                        }
                    }
                }

                // Wear OS ends the stream with a clear all button
                footer: Item {
                    width: lv.width
                    height: Math.round(stream.height * 0.3)
                    MouseArea {
                        id: clearButton
                        anchors.centerIn: parent
                        width: Math.round(stream.width * 0.5)
                        height: Math.round(stream.height * 0.15)
                        onClicked: stream.clearAll()
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "#2d2d30"
                            opacity: clearButton.pressed ? 0.7 : 1
                        }
                        Label {
                            anchors.centerIn: parent
                            //% "Clear all"
                            text: qsTrId("id-clear-all") + localeManager.changesObserver
                            font.pixelSize: Dims.l(6)
                            font.styleName: "SemiCondensed Medium"
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                visible: stream.modelEmpty
                spacing: Dims.h(3)
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Dims.w(18)
                    height: width
                    name: "ios-notifications-outline"
                    opacity: 0.7
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    //% "No notifications"
                    text: qsTrId("id-no-notifications") + localeManager.changesObserver
                    font.pixelSize: Dims.l(6)
                    opacity: 0.7
                }
            }

            TimeText { }
        }
    }

    Component {
        id: detailPage

        Item {
            id: detail
            property var pop
            property int depth
            property QtObject notification
            // pages open inside the notification (reply, voice, snooze)
            readonly property int innerDepth: actionsPage.forbidBottom ? 1 : 0

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            NotificationActions {
                id: actionsPage
                anchors.fill: parent
                showText: true
                notification: detail.notification
                notificationModel: notifModel
                panelsGrid: null
            }

            TimeText { visible: !actionsPage.fullScreenLayer }

            // the phone closed it, or it was dismissed: back to the stream
            Connections {
                target: notifModel
                function onRowsRemoved() {
                    if (notifModel.indexOf(detail.notification) < 0 && stack.currentLayer === detail)
                        stack.popAnim()
                }
            }
        }
    }
}
