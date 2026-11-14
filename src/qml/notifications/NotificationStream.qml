/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.nemomobile.lipstick
import org.asteroid.controls

/*
 * The notification stream of the Wear layout, the tray under the watchface
 * (swipe up), as Wear OS CP3A shows it (stock sysui kwf.java, kvy.java):
 *  - one card per notification, newest first (no grouping by app, no "+N":
 *    asteroid-btsyncd already makes one card per conversation);
 *  - a tap opens the card in place, inside the list, one at a time; a tap
 *    on the open card closes it. Opening scrolls first (preScroll);
 *  - a swipe to the left reveals "Clear" and "Settings" (SwipeToReveal);
 *  - "Clear all" is an edge button that grows out of the bottom edge as the
 *    end of the list comes up, 70 dp; a tap slides every clearable card off
 *    to the left (300 ms) while the list goes back to the top (250 ms);
 *  - the list is a ScalingList (rows shrink and fade towards the round
 *    edges, packed), 21.88 % of the height free at the top, cards 5.2 %
 *    of the width from the sides, 4 dp between cards;
 *  - nothing to show: a trophy and "You're all caught up", no clock.
 * The crown and a finger scroll it; the tray's background is the grid's
 * (ownBackground). A long press on a phone app's card opens the menu for
 * that app's notifications (NotificationBlockingMenu); other cards ignore
 * it, as stock ("Cannot block notifications from ... Ignoring long press").
 * The open card lists, below its text, the input row (emoji, voice, keyboard),
 * the replies, the app's actions and Open on phone (NotificationActions); the
 * keyboard, emoji and voice pages are layers of this stack, the phone round trip
 * and its result dialogs are the NotificationRemote below. A swipe clears an
 * open card as any other, a long press on its text turns the app off.
 * Battery: no timer runs while the display is off or in ambient, however
 * long the stream stays open (stock keeps it open for the go-to-watch-face
 * time, AppLifecycle brings the face back).
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

    // The list a downward drag that reaches its top hands over to the tray
    // (PanelsGrid.handOverMoved, stock nested scroll); none in a page. The
    // grid sets the list's boundsBehavior for the hand-over and puts it back:
    // the list keeps it writable (nothing here binds it).
    readonly property Item handOverView: stack.layers.length === 0 ? listView : null

    // The stream draws its own black background unless it sits in a tray
    // (Trays.build sets this false: the tray's background fades in
    // between 25 % and 50 % out, PanelsGrid.attachTray)
    property bool ownBackground: true

    /* ---- geometry (kwf.java:684-714; VALUES.tsv trayview_*) -------------- */
    readonly property real topPadding: Math.round(0.2188 * height)       // 21.88 %
    readonly property real sideMargin: Math.round(0.052 * width)         // 5.2 %
    readonly property real cardSpacing: Theme.dp(4)
    readonly property real cardWidth: width - 2 * sideMargin
    // the empty state's column sits between 7.1 % and 16 % of the height
    readonly property real emptyTop: Math.round(0.071 * height)
    readonly property real emptyBottom: Math.round(0.16 * height)

    // the notifications by id, and the ids in the list, newest first
    property var byId: ({})
    property int revision: 0
    // the card open in place (its notification's id), -1: none
    property int expandedId: -1
    // the relative times are worked out again when the stream shows, and
    // every minute while it does and the screen is on
    property int clockTick: 0
    // the display is on and not in ambient: nothing refreshes otherwise
    property bool awake: true
    readonly property bool screenOn: awake && !Lipstick.compositor.displayAmbient

    // "Clear all" in progress: the cards of notifications that can be cleared
    // slide off (clearProgress 0 -> 1)
    property bool clearing: false
    property real clearProgress: 0

    // Screen reader on: no swipe to reveal (kwb.java:114). The screen
    // reader's own switch is a context object once it exists.
    readonly property bool touchExploration: typeof screenReader !== "undefined" && screenReader !== null
                                             && (screenReader.enabled === true || screenReader.active === true)

    // rows by notification id, for the pre-scroll
    property var rowItems: ({})
    // the notifications that came in after the first ones: their cards fade in
    property var freshIds: ({})
    // item animations in ms (see the list)
    readonly property int addMs: 450
    readonly property int removeMs: 50
    readonly property int displacedMs: 70

    function idOf(n) { return n ? n.replacesId : -1 }

    function notificationOf(nid, rev) {
        return byId[nid] || null
    }

    // Something in the stream can be cleared (Clear all is enabled, kwf.java:988)
    readonly property bool hasClearable: {
        revision
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (n && n.userRemovable)
                return true
        }
        return false
    }

    function rebuild() {
        var map = {}
        var order = []
        for (var i = 0; i < notifModel.itemCount; i++) {
            var n = notifModel.get(i)
            if (!n)
                continue
            map[idOf(n)] = n
            order.push(idOf(n))
        }
        byId = map
        freshIds = {}
        // move the list model to the new order with the least changes, so
        // cards that stay keep their delegates (and nothing jumps)
        for (var r = rows.count - 1; r >= 0; r--) {
            if (order.indexOf(rows.get(r).nid) < 0)
                rows.remove(r)
        }
        for (var j = 0; j < order.length; j++) {
            var at = -1
            for (var m = j; m < rows.count; m++) {
                if (rows.get(m).nid === order[j]) { at = m; break }
            }
            if (at < 0) {
                if (revision > 0)
                    freshIds[order[j]] = true
                rows.insert(j, { nid: order[j] })
            }
            else if (at !== j)
                rows.move(at, j, 1)
        }
        if (expandedId >= 0 && !map[expandedId])
            expandedId = -1
        revision++
        if (clearing && clearDismissed)
            endClear()
    }

    function dismiss(list) {
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].userRemovable)
                list[i].removeRequested()
        }
    }

    /* ---- Clear all (kwf.java:972-986, jsm.java:388-420) ----------------- */

    // No confirmation. Every clearable card slides left by the width of the
    // screen (300 ms, FastOutSlowIn) and fades 1 -> 0 while the list scrolls
    // to the top (250 ms); then the notifications are cleared and the empty
    // state shows. Cards that cannot be cleared stay.
    function clearAll() {
        if (clearing || !hasClearable)
            return
        clearing = true
        clearProgress = 0
        if (expandedId >= 0)
            expandedId = -1
        scrollToTop(Motion.duration(250))
        clearAnim.restart()
    }

    // the slide is over: the notifications are asked to go; the cards stay
    // off screen until the model has dropped them (rebuild)
    function clearedAll() {
        var all = []
        for (var i = 0; i < notifModel.itemCount; i++)
            all.push(notifModel.get(i))
        clearDismissed = true
        failsafe.restart()
        dismiss(all)
    }

    function endClear() {
        failsafe.stop()
        clearing = false
        clearDismissed = false
        clearProgress = 0
    }
    property bool clearDismissed: false

    NumberAnimation {
        id: clearAnim
        target: stream
        property: "clearProgress"
        from: 0
        to: 1
        duration: Motion.duration(300)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easing.legacy
        onFinished: if (stream.clearing) stream.clearedAll()
    }
    // phone notifications close through the phone: a round trip is not awaited
    // for ever (single shot, only during a clear)
    Timer {
        id: failsafe
        interval: 1000
        onTriggered: stream.endClear()
    }

    /* ---- scrolling ------------------------------------------------------ */

    // Scroll the list in ms to where goalFn() says (a contentY, asked again at
    // every step). The list is packed: a card is laid out at its scaled height,
    // and the scale follows its place on the screen, so the cards under the ones
    // that scroll into view move as they do. The goal is therefore asked live, and
    // asked again at the end until the list is where it is told to be.
    property real scrollProgress: 0
    property real scrollStart: 0
    property var scrollGoalFn: null
    // The card to open or close once the scroll is over (stock scrolls first,
    // then changes the card, kvy.java:98-99); -2: none
    property int pendingExpanded: -2
    function scrollGoal(goalFn, ms, thenExpanded) {
        var lv = listView
        if (!lv)
            return
        lv.cancelFlick()
        if (lv.physics)
            lv.physics.stop()
        scrollAnim.stop()
        scrollGoalFn = goalFn
        scrollStart = lv.contentY
        scrollProgress = 0
        pendingExpanded = thenExpanded === undefined ? -2 : thenExpanded
        scrollAnim.duration = ms
        scrollAnim.restart()
    }
    function scrollToTop(ms) {
        scrollGoal(function () { return listView.originY - listView.topMargin }, ms)
    }
    // the contentY that puts the card of notification nid at y in the list
    function cardTopGoal(nid, y) {
        var lv = listView
        var row = rowItems[nid]
        if (!lv || !row)
            return lv ? lv.contentY : 0
        var want = lv.contentY + (row.mapToItem(lv, 0, 0).y - y)
        var lo = lv.originY - lv.topMargin
        var hi = Math.max(lo, lv.originY + lv.contentHeight + lv.bottomMargin - lv.height)
        return Math.max(lo, Math.min(hi, want))
    }
    onScrollProgressChanged: {
        if (listView && scrollGoalFn)
            listView.contentY = scrollStart + (scrollGoalFn() - scrollStart) * scrollProgress
    }
    NumberAnimation {
        id: scrollAnim
        target: stream
        property: "scrollProgress"
        from: 0
        to: 1
        easing.type: Easing.OutCubic
        onFinished: {
            var lv = stream.listView
            for (var i = 0; lv && stream.scrollGoalFn && i < 4; i++) {
                var g = stream.scrollGoalFn()
                if (Math.abs(g - lv.contentY) < 0.5)
                    break
                lv.contentY = g
            }
            stream.scrollGoalFn = null
            if (stream.pendingExpanded !== -2) {
                stream.expandedId = stream.pendingExpanded
                stream.pendingExpanded = -2
            }
        }
    }

    function rowIndex(nid) {
        for (var i = 0; i < rows.count; i++)
            if (rows.get(i).nid === nid)
                return i
        return -1
    }

    /*
     * The scroll before a card opens or closes (kvy.java, ComposeN10NTrayList
     * handlePreScrollOnClick; the decompile of the first branch is partial,
     * the gap text's reading is used):
     *  - opening a card whose bottom is in the upper half of the list: scroll
     *    so its top is at a quarter of the list's height;
     *  - opening a card (not the first on the screen) right under the one that
     *    closes as this opens: scroll so its top is where the list starts (the
     *    closing card above gives its height up);
     *  - closing a card whose top is more than two screen widths above the
     *    list: scroll back to it (200 ms).
     * The card changes after the scroll (200 ms). Returns where the card's top
     * is to be in the list (px from its top), or NaN for no scroll.
     */
    function preScrollTop(nid, opening) {
        var lv = listView
        var row = rowItems[nid]
        if (!lv || !row)
            return NaN
        var top = row.mapToItem(lv, 0, 0).y
        var bottom = row.mapToItem(lv, 0, row.height).y
        var h = lv.height
        if (opening) {
            var want = NaN
            if (bottom < h / 2)
                want = h / 4
            var i = rowIndex(nid)
            // the card above is the one that closes as this one opens: this card goes
            // to where the list starts (the list keeps what is in view while the
            // card above, out of view, closes)
            if (i > 0 && expandedId === rows.get(i - 1).nid && i !== lv.indexAt(1, lv.contentY + 1))
                want = lv.topMargin
            return want
        }
        if (top < -2 * stream.width)
            return lv.topMargin
        return NaN
    }

    // A tap on a card: open it, or close it when it is the open one
    function toggleCard(nid) {
        var opening = expandedId !== nid
        var y = preScrollTop(nid, opening)
        if (isNaN(y))
            expandedId = opening ? nid : -1
        else
            scrollGoal(function () { return cardTopGoal(nid, y) }, Motion.duration(200), opening ? nid : -1)
    }

    // The heads-up card was tapped (MainScreen.openNotification): that
    // notification opens in place
    function expand(n) {
        if (!n)
            return
        var nid = idOf(n)
        if (expandedId === nid)
            return
        if (listView && !modelEmpty)
            toggleCard(nid)
        else
            expandedId = nid
    }
    // as before the cards opened in place (MainScreen still calls this)
    function openDetail(n) { expand(n) }

    // what the open cards send to the phone and what comes back (replies, actions,
    // results, the keyboard layers); the card says it is gone through isActive
    readonly property QtObject remote: transport

    // A phone app's notification whose app the phone can stop sending
    function canBlock(n) {
        var a = n && n.hints ? n.hints["x-asteroid-phone-actions"] : ""
        return a ? String(a).split(",").indexOf("mute") >= 0 : false
    }

    // A call from the phone: ringing, or in progress
    function callActionsOf(n) {
        var a = n && n.hints ? n.hints["x-asteroid-phone-actions"] : ""
        return a ? String(a).split(",") : []
    }
    function isCall(n) {
        var a = callActionsOf(n)
        return a.indexOf("end") >= 0 || a.indexOf("answer") >= 0 || a.indexOf("reject") >= 0
    }

    // The call view (IncomingCall, a layer of the compositor's overlays)
    function reopenCall(n) {
        var c = Lipstick.compositor
        var arbiter = c && c.overlays ? c.overlays : null
        var view = arbiter && arbiter.callView ? arbiter.callView : null
        return view && typeof view.reopen === "function" ? view.reopen(n) === true : false
    }

    // A tap on a call card reopens the call (its content intent is the
    // in-call activity, jgv.java:128-130); any other card opens in place
    function cardTapped(n) {
        if (!n)
            return
        if (isCall(n) && reopenCall(n))
            return
        toggleCard(idOf(n))
    }

    // card: the card whose long press (its finger still down) opens it
    function openBlockingMenu(n, card) {
        if (!canBlock(n))
            return false
        Haptics.longPress()
        stack.push(blockingPage, { notification: n, openingCard: card || null, remote: transport })
        return true
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
        expandedId = -1
        pendingExpanded = -2
        scrollAnim.stop()
        // the top with its margin (positionViewAtBeginning() goes past it,
        // and the list would then not be at its beginning)
        if (listView && !listView.atYBeginning) {
            listView.cancelFlick()
            listView.contentY = listView.originY - listView.topMargin
        }
    }
    function needsReset() {
        return stack.layers.length > 0 || expandedId >= 0 || (listView !== null && !listView.atYBeginning)
    }

    onVisibleChanged: {
        if (visible)
            clockTick++
        else if (needsReset())
            reset()
    }
    // One timer, only while the stream shows with the screen on
    Timer {
        interval: 60000
        repeat: true
        running: stream.visible && !stream.modelEmpty && stream.screenOn
        onTriggered: stream.clockTick++
    }
    Connections {
        target: Lipstick.compositor
        function onDisplayAboutToBeOff() { stream.awake = false }
        function onDisplayAboutToBeOn() { stream.awake = true; if (stream.visible) stream.clockTick++ }
    }

    Connections {
        target: stream.panelsGrid
        function onCurrentVerticalPosChanged() {
            stream.panelsGrid.changeAllowedDirections()
        }
    }

    ListModel { id: rows }

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
        visible: stream.ownBackground
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

            ScalingList {
                id: lv
                anchors.fill: parent
                model: rows
                packed: true
                // the stream's edge values (notif-stream-11): 0.6, [0, 0, 0.6, 1]
                edgeScale: Motion.list.streamEdgeScale
                edgeEasing: Motion.list.streamEdgeEasing
                spacing: stream.cardSpacing
                topMargin: stream.topPadding
                // the last card ends 16 dp above Clear all (70 dp)
                bottomMargin: clearAllButton.contentPadding
                sideMargin: stream.sideMargin
                cacheBuffer: stream.height
                visible: !stream.modelEmpty
                // No stretch at the top (stock shows none: the tray takes that
                // edge, PanelsGrid.handOverMoved); the end stretches as in any list
                physics.stretchEnabled: !(lv.atYBeginning && !lv.atYEnd)

                // animateItem (kwf.java:106-114, 632-633): fade in on a spring of
                // stiffness 200 (~0.45 s: the row's fadeIn), moves on 1.0 / 10000
                // (~0.07 s), fade out on 10000 (near instant); none under reduce
                // motion. No ListView.add transition: a view that has one keeps the
                // positions it laid out while the cards still changed their height
                // (the notification arrives after the row is made)
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: Motion.duration(stream.removeMs) }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Motion.duration(stream.displacedMs); easing.type: Easing.OutCubic }
                }

                itemDelegate: Item {
                    id: row
                    property int index: -1
                    property var model: null
                    property var modelData: null

                    readonly property int nid: model ? model.nid : -1
                    readonly property var notification: stream.notificationOf(nid, stream.revision)
                    readonly property bool expanded: stream.expandedId === nid && notification !== null
                    // this card goes with Clear all
                    readonly property bool clearingNow: stream.clearing && notification !== null && notification.userRemovable

                    width: parent ? parent.width : stream.cardWidth
                    height: swipe.height
                    visible: notification !== null

                    // the stream finds a row by its notification's id (pre-scroll); the model
                    // role arrives after the row is made
                    property int regId: -1
                    function register() {
                        if (regId >= 0 && stream.rowItems[regId] === row)
                            delete stream.rowItems[regId]
                        regId = nid
                        if (nid >= 0)
                            stream.rowItems[nid] = row
                        if (nid >= 0 && stream.freshIds[nid] === true) {
                            delete stream.freshIds[nid]
                            fadeIn.restart()
                        }
                    }
                    NumberAnimation {
                        id: fadeIn
                        target: row
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Motion.duration(stream.addMs)
                        easing.type: Easing.OutCubic
                    }
                    onNidChanged: register()
                    Component.onCompleted: register()
                    Component.onDestruction: if (stream.rowItems[regId] === row) delete stream.rowItems[regId]

                    SwipeToReveal {
                        id: swipe
                        width: row.width
                        height: card.height
                        swipeEnabled: row.notification !== null && row.notification.userRemovable
                                      && !stream.touchExploration && !stream.clearing
                        hasSecondaryAction: stream.canBlock(row.notification)
                        onPrimaryAction: stream.dismiss([row.notification])
                        onSecondaryAction: stream.openBlockingMenu(row.notification, null)
                        opacity: row.clearingNow ? 1 - stream.clearProgress : 1
                        transform: Translate { x: row.clearingNow ? -stream.clearProgress * stream.width : 0 }
                        // A tap: SwipeToReveal's own area keeps the press for the swipe and,
                        // while the card is covered, passes the click on to the areas under it,
                        // top down: a button of the open card first, then this one (so it sits
                        // under the card)
                        MouseArea {
                            anchors.top: card.top
                            anchors.left: card.left
                            anchors.right: card.right
                            // the card's surface; the buttons below it are their own
                            height: card.surfaceHeight
                            onClicked: if (!row.longFired && !stream.clearing) card.tapped()
                        }

                        NotificationCard {
                            id: card
                            width: swipe.width
                            notification: row.notification
                            expanded: row.expanded
                            timestamp: stream.ago(row.notification, stream.clockTick)
                            remote: transport
                            layerHost: stack
                            pressed: row.down
                            pressPoint: pointer.point.position
                            onTapped: stream.cardTapped(row.notification)
                            onLongPressed: stream.openBlockingMenu(row.notification, card)
                            onClearRequested: stream.dismiss([row.notification])
                        }
                    }

                    // The finger on an uncovered card (ripple, held, long press). A
                    // PointHandler over the swipe-to-reveal only watches: SwipeToReveal's own
                    // area keeps the press for the swipe (a tap handler there would take it)
                    // (a finger on the buttons of an open card is theirs, not the card's)
                    readonly property bool down: pointer.active && swipe.state_ === "covered"
                                                 && !swipe.dragging && !stream.clearing
                                                 && !card.onActions(pointer.point.position)
                    property bool longFired: false
                    onDownChanged: if (down) longFired = false
                    Item {
                        anchors.fill: swipe
                        z: 5
                        PointHandler {
                            id: pointer
                            acceptedButtons: Qt.LeftButton
                        }
                    }
                    // as the watchface's long press (the face picker): half a second, only
                    // while a finger is down on the card
                    Timer {
                        interval: 500
                        running: row.down
                        onTriggered: {
                            row.longFired = true
                            card.longPressed()
                        }
                    }
                }
            }

            // Wear OS ends the stream with Clear all, an edge button that
            // grows out of the bottom edge as the end of the list comes up
            // (ScreenScaffold, kwf.java:928-994; EdgeButton Medium 70 dp,
            // primaryDim / onPrimary, enabled while anything can be cleared)
            EdgeButton {
                id: clearAllButton
                flickable: lv
                preferredHeight: Theme.size.edgeButtonMedium
                //% "Clear all"
                text: qsTrId("id-clear-all") + localeManager.changesObserver
                enabled: stream.hasClearable && !stream.clearing
                containerColor: enabled ? Theme.color.primaryDim
                                        : Qt.rgba(Theme.color.onSurface.r, Theme.color.onSurface.g,
                                                  Theme.color.onSurface.b, Theme.alpha.disabledContainer)
                visible: !stream.modelEmpty && shownHeight > 0.5
                onClicked: stream.clearAll()
            }

            // Nothing to show (kvn.java:22-75, STRINGS empty_state_text): a
            // trophy and a line, no Clear all, no clock
            Item {
                anchors.fill: parent
                anchors.topMargin: stream.emptyTop
                anchors.bottomMargin: stream.emptyBottom
                visible: stream.modelEmpty
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.dp(6)
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.dp(28)
                        height: width
                        name: "ios-trophy-outline"
                        color: Theme.color.onSurface
                    }
                    Label {
                        width: Theme.dp(140)
                        //% "You're all caught up"
                        text: qsTrId("id-all-caught-up") + localeManager.changesObserver
                        role: "titleLarge"
                        color: Theme.color.onSurface
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    // Wear OS's long press menu: the app's notifications on or off
    Component {
        id: blockingPage

        Item {
            id: blocking
            property var pop
            property int depth
            property QtObject notification
            property Item openingCard: null
            property QtObject remote: null

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            NotificationBlockingMenu {
                id: blockingMenu
                anchors.fill: parent
                notification: blocking.notification
                // the long press's finger is still down: its lift is not a tap here
                openedByHold: blocking.openingCard !== null
                holding: blocking.openingCard !== null && blocking.openingCard.held
                remote: blocking.remote
                onTurnedOff: blocking.pop()
            }

            // Wear OS: the time scrolls away with the page
            TimeText {
                opacity: Math.max(0, 1 - blockingMenu.scrolled / Dims.h(10))
                transform: Translate { y: -blockingMenu.scrolled }
            }
        }
    }

    // The phone round trip of the open cards and its dialogs, over the whole stream
    NotificationRemote {
        id: transport
        anchors.fill: parent
        z: 20
        isActive: function (id) { return stream.byId[id] !== undefined }
    }
}
