/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import QtQuick.Shapes
import org.nemomobile.lipstick
import org.asteroid.controls
import Nemo.Configuration
import "home"
import "desktop.js" as Desktop

/*
 * The notification stream of the Wear layout, the tray under the watchface
 * (swipe up), as Wear OS CP3A shows it (stock sysui kwf.java, kvy.java):
 *  - one card per notification, newest first (no grouping by app, no "+N":
 *    asteroid-btsyncd already makes one card per conversation);
 *  - a tap opens the card in place, inside the list, one at a time; a tap
 *    on the open card closes it. Opening scrolls first (preScroll);
 *  - a swipe either way reveals "Clear" (and "Settings" for a phone app's card)
 *    as the Wear OS 6 emulator draws it (S34, S34-b, M10): a blue-grey pill on
 *    the side the card leaves (SwipeToReveal bidirectional, expressiveLook). A
 *    full swipe clears the card: its pill stays 100 ms, then fades in 100 ms
 *    while the cards under it slide up (282 ms, LinearOutSlowIn);
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
    // where a card that opens in place puts its top: 11.7 % of the height (45 px; the Wear OS 6
    // emulator, S08), above the list's top margin, the card above edge-scaled over the gap
    readonly property real openTop: Math.round(0.117 * height)
    // its text: a 140 dp box with 7.3 % of the screen as side padding (kwf.java:323, kvn.java:74)
    readonly property real emptyTextPadding: Math.round(0.073 * height)
    // CP3A's trophy_40px (res/drawable/trophy_40px.xml, 960 x 960 viewport): the Material
    // Symbols trophy, filled (one path: the cup and the two holes of its handles)
    readonly property string trophyPath: "M282.67,433.33L282.67,272L186.67,272Q186.67,272 186.67,272Q186.67,272 186.67,272L186.67,314.67Q186.67,357.33 213.67,389.83Q240.67,422.33 282.67,433.33ZM677.33,433.33Q719.33,422.33 746.33,389.83Q773.33,357.33 773.33,314.67L773.33,272Q773.33,272 773.33,272Q773.33,272 773.33,272L677.33,272L677.33,433.33ZM446.67,773.33L446.67,633.33Q394.33,622.33 353.5,588.5Q312.67,554.67 296,504Q221.67,495.67 170.83,442.17Q120,388.67 120,314.67L120,272Q120,244.5 139.58,224.92Q159.17,205.33 186.67,205.33L282.67,205.33L282.67,186.67Q282.67,159.17 302.25,139.58Q321.83,120 349.33,120L610.67,120Q638.17,120 657.75,139.58Q677.33,159.17 677.33,186.67L677.33,205.33L773.33,205.33Q800.83,205.33 820.42,224.92Q840,244.5 840,272L840,314.67Q840,388.67 789.17,442.17Q738.33,495.67 664,504Q647.33,554.67 606.5,588.5Q565.67,622.33 513.33,633.33L513.33,773.33L634.67,773.33Q648.83,773.33 658.42,782.95Q668,792.57 668,806.78Q668,821 658.42,830.5Q648.83,840 634.67,840L325.33,840Q311.17,840 301.58,830.38Q292,820.77 292,806.55Q292,792.33 301.58,782.83Q311.17,773.33 325.33,773.33L446.67,773.33Z"

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
    // item animations in ms (see the list): a new card fades in; a cleared card's row (its pill)
    // is held, then fades; the cards under it move up on LinearOutSlowIn (the emulator, M10)
    readonly property int addMs: 450
    readonly property int removeHoldMs: 100
    readonly property int removeFadeMs: 100
    readonly property int displacedMs: 282
    readonly property var displacedEasing: [0, 0, 0.2, 1, 1, 1]

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
    // every step). The list is packed (ScalingList, N61-04): every row keeps its
    // natural height and place, and its picture is scaled and moved up to its
    // neighbours by how near the edge it is drawn, so where a card is drawn
    // (cardTopGoal) moves with the list and with the cards around it. The goal is
    // therefore asked live, and asked again at the end until the list is where it
    // is told to be.
    property real scrollProgress: 0
    property real scrollStart: 0
    property var scrollGoalFn: null
    // where the running scroll last put the list; NaN: no scroll runs. Anything else that moves the
    // list (the crown) moves it away from this, and the scroll then gives way (stopScroll)
    property real scrollWritten: NaN
    // The card to open or close once the scroll is over (stock scrolls first,
    // then changes the card, kvy.java:98-99); -2: none
    property int pendingExpanded: -2
    // the curve of the scroll tween: null is OutCubic (Clear all's scroll to the top, whose stock
    // curve was lost), else a BezierSpline (motion E10: the card scrolls are FastOutSlowIn)
    property var scrollCurve: null
    // stop what moves the list and take it for a scroll to goalFn(); false: no list
    function takeList(goalFn, thenExpanded) {
        var lv = listView
        if (!lv)
            return false
        lv.cancelFlick()
        if (lv.physics)
            lv.physics.stop()
        scrollAnim.stop()
        scrollSpring.stop()
        scrollGoalFn = goalFn
        scrollStart = lv.contentY
        scrollWritten = scrollStart
        scrollProgress = 0
        pendingExpanded = thenExpanded === undefined ? -2 : thenExpanded
        return true
    }
    // ms: a tween of that length (after delayMs); ms < 0: a spring of that stiffness, -ms
    function scrollGoal(goalFn, ms, thenExpanded, curve, delayMs) {
        if (!takeList(goalFn, thenExpanded))
            return
        if (ms < 0) {
            scrollSpring.stiffness = -ms
            scrollSpring.snapTo(0)
            scrollSpring.animateTo(1)
            return
        }
        scrollCurve = curve === undefined ? null : curve
        scrollPause.duration = delayMs === undefined ? 0 : delayMs
        scrollTween.duration = ms
        scrollAnim.restart()
    }
    function scrollToTop(ms) {
        scrollGoal(function () { return listView.originY - listView.topMargin }, ms)
    }
    // the list goes to where goalFn() says at once (stock's scrollToItem, erl.i)
    function jumpTo(goalFn) {
        if (takeList(goalFn))
            scrollDone()
    }
    // the contentY that puts the card of notification nid at y in the list; pastEnd: not held to the
    // list's end (its size has not caught up yet with a card that has just been told to open). y is
    // where the card is drawn: the row sits in the list's transformed (packed) wrapper, so its mapped
    // top is its picture's, which depends on where the list is (scrollDone asks again)
    function cardTopGoal(nid, y, pastEnd) {
        var lv = listView
        var row = rowItems[nid]
        if (!lv || !row)
            return lv ? lv.contentY : 0
        var want = lv.contentY + (row.mapToItem(lv, 0, 0).y - y)
        var lo = lv.originY - lv.topMargin
        if (pastEnd)
            return Math.max(lo, want)
        var hi = Math.max(lo, lv.originY + lv.contentHeight + lv.bottomMargin - lv.height)
        return Math.max(lo, Math.min(hi, want))
    }
    onScrollProgressChanged: {
        if (listView && scrollGoalFn) {
            scrollWritten = scrollStart + (scrollGoalFn() - scrollStart) * scrollProgress
            listView.contentY = scrollWritten
        }
    }
    function scrollDone() {
        var lv = stream.listView
        stream.scrollWritten = NaN
        for (var i = 0; lv && stream.scrollGoalFn && i < 4; i++) {
            // lay the list out now, not at the next frame, before the goal is asked: under reduce
            // motion the card snapped to its new height in the call that started the scroll, which
            // ended there too, so the list's end still had the card's old height. The goal is asked
            // again after each move: the drawn top it reads is packed for where the list was (a
            // jump moves the list far in one step)
            lv.forceLayout()
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
    // The user took the list (a finger down on it, the crown): a running scroll stops where the list
    // is, with no snap to its goal, and the card change that waited for it is dropped. So does stock's:
    // its scrolls run at MutatePriority.Default (erl.java:166, mv.h), which user input cancels, and the
    // cancel ends kvy's coroutine before it toggles the card (kvy.java:65, 98-99)
    function stopScroll() {
        if (isNaN(scrollWritten))
            return
        scrollAnim.stop()
        scrollSpring.stop()
        scrollWritten = NaN
        scrollGoalFn = null
        pendingExpanded = -2
    }
    // The list (lv) moved while a scroll runs. When the cards' heights change under the scroll (a card
    // closes as another opens, or as Clear all starts) the content can end above where the scroll
    // put the list, and the list puts itself back inside its bounds: setContentHeight does it at once
    // (a write to contentY does not set moving), the fixup after a layout at once too, or in a glide
    // when the list's last move was the finger's (qquicklistview.cpp:1672). That is followed and the
    // scroll goes on (its goal is held to the new bounds), as stock's scrollBy steps go on at the
    // list's end (amk.java:53-58). Anything else that moves the list more than 1 px (ScrollPhysics'
    // own test for another writer) from where the scroll put it is the crown: the scroll gives way
    function listMoved(lv) {
        if (isNaN(scrollWritten))
            return
        var y = lv.contentY
        var lo = lv.originY - lv.topMargin
        var hi = Math.max(lo, lv.originY + lv.contentHeight + lv.bottomMargin - lv.height)
        var held = Math.max(lo, Math.min(hi, scrollWritten))
        // on the bound, or on the way from where the scroll put the list to it
        if (Math.abs(y - held) < 0.5 || (y - held) * (y - scrollWritten) < 0) {
            scrollWritten = y
            return
        }
        if (Math.abs(y - scrollWritten) > 1)
            stopScroll()
    }
    SequentialAnimation {
        id: scrollAnim
        PauseAnimation { id: scrollPause; duration: 0 }
        NumberAnimation {
            id: scrollTween
            target: stream
            property: "scrollProgress"
            from: 0
            to: 1
            easing.type: stream.scrollCurve ? Easing.BezierSpline : Easing.OutCubic
            easing.bezierCurve: stream.scrollCurve ? stream.scrollCurve : []
        }
        onFinished: stream.scrollDone()
    }
    // the scroll after a card that is not a conversation opens: spring 1.0/800 (kwa.java, kwf.java:632)
    WearSpring {
        id: scrollSpring
        dampingRatio: 1.0
        visibilityThreshold: 0.001
        onValueChanged: if (running) stream.scrollProgress = value
        onFinished: {
            stream.scrollProgress = 1
            stream.scrollDone()
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
     *    closes as this opens: scroll so its top is at openTop (the closing card
     *    above gives its height up);
     *  - closing a card whose top is more than two screen widths above the
     *    list: scroll back to it (200 ms).
     * The two opening cases jump there and the card opens at once (erl.i is
     * scrollToItem, erl.java:165-167, 189-198); only the closing case scrolls,
     * 200 ms on FastOutSlowIn (kvy.java:90-95, motion E10), and the card
     * closes after it. Returns where the card's top is to be in the list (px
     * from its top), or NaN for no scroll.
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
                want = stream.openTop
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
        if (isNaN(y)) {
            expandedId = opening ? nid : -1
            if (opening)
                scrollAfterOpen(nid)
        } else if (opening) {
            jumpTo(function () { return cardTopGoal(nid, y) })
            expandedId = nid
        } else {
            scrollGoal(function () { return cardTopGoal(nid, y) }, Motion.duration(200), -1,
                       Motion.easing.legacy)
        }
    }

    /* A card opened with no scroll before it (it opens downwards): the list then scrolls its top to
     * openTop (kwa.java:105-144, "Expanding downward measured item"; motion E10). A conversation
     * scrolls on a 300 ms FastOutSlowIn tween after 20 ms (autoscroll_duration, autoscroll_delay,
     * kwm.java:7-8), any other card on the inline spring 1.0/800 (kwf.java:632). The target is
     * where the Wear OS 6 emulator puts an opened card's top (S08: y 45, 0.117 of the height),
     * the card above edge-scaled over it; CP3A's was an offset of 0.16 of the screen height in one
     * layout and 0 in the other (kwf.java:697). */
    function isConversation(n) {
        return !!n && !!n.hints && (n.hints["x-asteroid-messages"] !== undefined || conversationKey(n) !== "")
    }
    function scrollAfterOpen(nid) {
        var lv = listView
        var row = rowItems[nid]
        if (!lv || !row)
            return
        var goal = function () { return cardTopGoal(nid, stream.openTop) }
        // nothing to scroll when the card's top is where the list starts already. Asked past the
        // list's end: the card has not grown yet (its height spring and the list's layout run from
        // the next frame), so the end still has its closed height, and at the end of the list goal()
        // would always say there is nothing to scroll. goal() keeps the end as the card grows.
        if (Math.abs(cardTopGoal(nid, stream.openTop, true) - lv.contentY) < 0.5)
            return
        if (isConversation(row.notification))
            scrollGoal(goal, Motion.duration(300), undefined, Motion.easing.legacy, Motion.duration(20))
        else
            scrollGoal(goal, -800)
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

    // The conversation a message card belongs to (asteroid-btsyncd's hint x-asteroid-conversation:
    // the key of the phone's conversation list, "t<thread id>" or "n<hash>"); "" for any other card
    function conversationKey(n) {
        var h = n && n.hints ? n.hints["x-asteroid-conversation"] : ""
        return h ? String(h) : ""
    }

    // The messages app opens on the conversation with its list under it (messages-contacts-21:
    // stock runs the notification's view_conversation intent of Google Messages, parent = the
    // list). A running app takes the key from the dconf hand-off keys (a second start of a
    // single-instance app only raises it), a new one reads them at start.
    ConfigurationValue { id: openConversationKey; key: "/org/asteroidos/messages/open-conversation"; defaultValue: "" }
    ConfigurationValue { id: openConversationName; key: "/org/asteroidos/messages/open-name"; defaultValue: "" }
    property string lastConversation: ""
    function openConversation(n) {
        var key = conversationKey(n)
        if (key === "" || !Desktop.desktop || !Desktop.desktop.launchByName)
            return false
        openConversationName.value = n.summary ? String(n.summary) : ""
        openConversationKey.value = key
        lastConversation = key
        Desktop.desktop.launchByName("asteroid-messages", null)
        return true
    }

    // A tap on a call card reopens the call (its content intent is the
    // in-call activity, jgv.java:128-130); a tap on the content of an open message card hands
    // the conversation to the messages app; any other card opens in place
    function cardTapped(n) {
        if (!n)
            return
        if (isCall(n) && reopenCall(n))
            return
        if (expandedId === idOf(n) && conversationKey(n) !== "" && openConversation(n))
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
        scrollSpring.stop()
        scrollWritten = NaN
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

    // CP3A gives the stream a scroll indicator only while the tray is fully open and the list
    // is not empty (kwf.java:664-680: the indicator slot is null unless the open fraction is 1),
    // and its ScreenScaffold shows it as a screen that opens. Here: once the tray is open and at
    // rest (row 1 of the grid, all the way out, no spring, no finger on it) the list's
    // indicator shows for 2 s (RotaryInput.flashIndicator); not under a page over the list
    readonly property var _grid: panelsGrid
    readonly property bool openAtRest: !!_grid && _grid.currentVerticalPos === 1 && _grid.currentHorizontalPos === 0
                                       && _grid.normalizedVerOffset >= 0.999 && _grid.trayDragging !== true
                                       && !(_grid.trayAnimation && _grid.trayAnimation.running)
    onOpenAtRestChanged: if (openAtRest) flashIndicator()
    // whether the indicator took the list (it does when the list scrolls)
    function flashIndicator() {
        if (modelEmpty || stack.layers.length > 0 || listView === null)
            return false
        return RotaryInput.flashIndicator(listView)
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
                // the ongoing activities as status chips above the cards (status-indicators-21): no
                // entry, no height
                header: Component {
                    LiveChips {
                        interactive: stream.screenOn
                        onTapped: function (key) {
                            if (typeof ongoingRegistry !== "undefined" && ongoingRegistry !== null)
                                ongoingRegistry.activate(key)
                            // an entry without an app has its full view (system-dialogs-misc-12)
                            if (Desktop.liveUpdate)
                                Desktop.liveUpdate.tap(key)
                        }
                        onMenuRequested: function (key, app, title) {
                            if (typeof desktop !== "undefined" && desktop && desktop.openLiveMenu)
                                desktop.openLiveMenu(app, title)
                        }
                    }
                }
                // the last card ends 16 dp above Clear all (70 dp)
                bottomMargin: clearAllButton.contentPadding
                sideMargin: stream.sideMargin
                cacheBuffer: stream.height
                visible: !stream.modelEmpty
                // No stretch at the top (stock shows none: the tray takes that
                // edge, PanelsGrid.handOverMoved); the end stretches as in any list
                physics.stretchEnabled: !(lv.atYBeginning && !lv.atYEnd)
                // the crown (anything but the scroll itself and the list's hold on its bounds) moved
                // the list: the scroll gives way (listMoved)
                onContentYChanged: stream.listMoved(lv)

                // A new card fades in on CP3A's animateItem spring (kwf.java:106-114, stiffness
                // 200, ~0.45 s: the row's fadeIn). A cleared card as the Wear OS 6 emulator (M10):
                // its row, by then only the pill at the full width, stays 100 ms under its
                // neighbours, then fades in 100 ms, while the cards under it move up over 282 ms on
                // LinearOutSlowIn (the next card 266 -> 84 px). None under reduce motion. No
                // ListView.add transition: a view that has one keeps the positions it laid out
                // while the cards still changed their height (the notification arrives after the
                // row is made)
                remove: Transition {
                    SequentialAnimation {
                        PropertyAction { property: "z"; value: -1 }
                        PauseAnimation { duration: Motion.duration(stream.removeHoldMs) }
                        NumberAnimation { property: "opacity"; to: 0; duration: Motion.duration(stream.removeFadeMs) }
                    }
                }
                displaced: Transition {
                    NumberAnimation {
                        properties: "y"
                        duration: Motion.duration(stream.displacedMs)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: stream.displacedEasing
                    }
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
                    visible: notification !== null || cleared

                    // Cleared by a full swipe: the card has left and the row is its pill. The
                    // notification goes from byId before the row leaves the list, so the row stays
                    // drawn at the height it had while its remove transition runs
                    property bool cleared: false
                    property real clearedHeight: 0
                    function clear() {
                        if (cleared)
                            return
                        clearedHeight = card.height
                        cleared = true
                        stream.dismiss([notification])
                    }

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
                        height: row.cleared ? row.clearedHeight : card.height
                        // either way, in the emulator's look (S34, S34-b): the #343B4D pill on the
                        // side the card leaves, 2 dp from it, the X glyph, "Clear" near full width
                        bidirectional: true
                        expressiveLook: true
                        swipeEnabled: row.notification !== null && row.notification.userRemovable
                                      && !stream.touchExploration && !stream.clearing
                        hasSecondaryAction: stream.canBlock(row.notification)
                        onPrimaryAction: row.clear()
                        // a cleared card that comes back (another card's reveal covers it) before its
                        // notification has gone is a card again
                        onState_Changed: if (state_ === "covered") row.cleared = false
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

            // A finger down anywhere on the list stops a running scroll (stopScroll) before the
            // list takes the drag. Passive and above the list: the press goes on to what is under it
            Item {
                anchors.fill: parent
                z: 100
                PointHandler {
                    onActiveChanged: if (active) stream.stopScroll()
                }
            }

            // Nothing to show (kvn.java:22-75, STRINGS empty_state_text): a
            // trophy and a line, no Clear all, no clock. The trophy is CP3A's
            // filled trophy_40px drawn at 28 dp in onSurface (kvn.java:73); the
            // text 6 dp below it in a 140 dp box with 7.3 % side padding
            Item {
                anchors.fill: parent
                anchors.topMargin: stream.emptyTop
                anchors.bottomMargin: stream.emptyBottom
                visible: stream.modelEmpty
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.dp(6)
                    Shape {
                        id: trophy
                        objectName: "emptyTrophy"
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.dp(28)
                        height: width
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Theme.color.onSurface
                            strokeColor: "transparent"
                            strokeWidth: -1
                            scale: Qt.size(trophy.width / 960, trophy.height / 960)
                            PathSvg { path: stream.trophyPath }
                        }
                    }
                    Label {
                        objectName: "emptyLabel"
                        width: Theme.dp(140)
                        leftPadding: stream.emptyTextPadding
                        rightPadding: stream.emptyTextPadding
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
