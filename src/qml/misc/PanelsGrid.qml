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
import org.asteroid.controls
import org.asteroid.launcher
import "tray.js" as TrayRules

/* The grid of panels. In the Wear layout (trayMode, set by Trays.build) the
 * vertical panels are trays (W2-launcher-trays, stock TrayPositionController):
 * the watch face stays where it is (faceHost cancels the content's vertical
 * motion) and quick settings (row -1, from the top) and the notification
 * stream (row 1, from the bottom) slide over it. The content still moves as
 * before (content.y = 0 on the face, +height with quick settings out,
 * -height with the stream out), so currentVerticalPos, normalizedVerOffset
 * and contentY keep their meaning for everything that reads them; only what
 * is painted differs. The rules are in misc/tray.js:
 *  - the tray follows the finger 1:1; a finger that went down more than
 *    30 dp past the tray's edge is caught up in 300 ms
 *  - release: |v| > 1000 px/s decides by direction, else a closed tray opens
 *    past 33 % and an open one stays open from 67 %
 *  - then a spring from the release speed (at most 2000 px/s): open
 *    0.75/500, close 1.0/500 ending at 98 %
 *  - its own black background: alpha 0 below 25 % out, opaque at 50 %
 *  - the crown on the face opens the stream (forward) or quick settings
 *    (backward) after 150 px of rotation (RotaryInput's rotaryExit); a list
 *    in the stream at its top hands the rest of a downward drag to the tray
 * Without trayMode (the AsteroidOS layout) the grid is a pager as it was. */
GestureFilterArea {
    id: panelsGrid

    /* Fraction of a panel the content is shifted from the grid origin, clamped
     * to [-1, 1]. Kept as pure bindings on the content position so they can
     * never get out of sync: every consumer (parallax, wallpaper darkener,
     * background colours) derives from these and re-evaluates automatically.
     * Panels live on the axes through the origin, so at most one of the two is
     * ever non-zero during normal use - no orthogonality bookkeeping needed. */
    property real normalizedHorOffset: panelWidth  > 0 ? Math.max(-1, Math.min(1, -content.x/panelWidth))  : 0
    property real normalizedVerOffset: panelHeight > 0 ? Math.max(-1, Math.min(1, -content.y/panelHeight)) : 0

    /* Item that will move according to the user's needs */
    Item {
        id: content

        /* The watch face's parent in trayMode: it moves with the content
         * sideways (the tiles) and not up or down, so the trays pass over it */
        Item {
            id: stillHost
            y: panelsGrid.trayMode ? -content.y : 0
        }
    }
    readonly property Item faceHost: stillHost

    /* Panels handling
     *
     * Panels live on an integer lattice (col, row). They are kept in a Map
     * keyed by a single packed-integer hash of their coordinates, so lookups,
     * neighbour queries and removal are all O(1) and there is no coordinate
     * string parsing anywhere. Each entry is a {item, col, row} record; the
     * record carries the position so geometry can be recomputed on resize
     * without re-deriving it from the key.
     */

    property var panels: new Map() /* key(col,row) -> { item, col, row } */
    property alias panelWidth:  panelsGrid.width
    property alias panelHeight: panelsGrid.height

    /* Pack a coordinate pair into a unique integer key. The offset keeps the
     * hash collision-free for any |col|,|row| < 4096, far beyond what the UI
     * ever reaches (a handful of notifications). */
    function key(col, row) { return (col + 4096) * 8192 + (row + 4096) }

    function cellAt(col, row) { return panels.get(key(col, row)) }

    function placeItem(rec) {
        rec.item.x = panelWidth  * rec.col
        rec.item.y = panelHeight * rec.row
        rec.item.width  = panelWidth
        rec.item.height = panelHeight
    }

    /* host: the item the panel is made in (default: the content) */
    function addPanel(horizontalPos, verticalPos, component, host) {
        if (component.status === Component.Ready) {
            var rec = { item: component.createObject(host || content), col: horizontalPos, row: verticalPos }
            placeItem(rec)
            if(rec.item.panelsGrid !== undefined)
                rec.item.panelsGrid = panelsGrid
            panels.set(key(horizontalPos, verticalPos), rec)
            return rec.item
        }
    }

    function removePanel(horizontalPos, verticalPos) {
        var k = key(horizontalPos, verticalPos)
        var rec = panels.get(k)
        if(rec !== undefined) {
            rec.item.destroy()
            panels.delete(k)
        }
    }

    function movePanel(originHorizontalPos, originVerticalPos, destHorizontalPos, destVerticalPos) {
        var rec = panels.get(key(originHorizontalPos, originVerticalPos))
        if(rec !== undefined) {
            panels.delete(key(originHorizontalPos, originVerticalPos))
            rec.col = destHorizontalPos
            rec.row = destVerticalPos
            panels.set(key(destHorizontalPos, destVerticalPos), rec)
            placeItem(rec)
        }
    }

    function moveTo(posX, posY) {
        // a glide still going would take the content on to its own panel
        // after this, away from the one the grid says it is on
        contentAnim.stop()
        stopTrays()
        content.x = -panelWidth*posX
        content.y = -panelHeight*posY
        currentHorizontalPos = posX
        currentVerticalPos = posY
    }

    /* True while followTo() runs: the panel under the user was renumbered,
     * the user did not leave it (panels keep what they show, e.g. a reply
     * being written). */
    property bool following: false

    /* Keep showing the panel the user is on after it moved to (posX, posY)
     * because panels were added or removed before it. */
    function followTo(posX, posY) {
        following = true
        moveTo(posX, posY)
        var rec = cellAt(posX, posY)
        if (rec !== undefined)
            rec.item.visible = true
        following = false
        changeAllowedDirections()
    }

    /* Glide to a panel (the crown button back to the watchface) the way a
     * released swipe settles */
    function animateTo(posX, posY) {
        // every panel on the way shows while the content glides over it
        var c, r
        for (c = Math.min(posX, currentHorizontalPos); c <= Math.max(posX, currentHorizontalPos); c++)
            revealNeighbour(c, posY === currentVerticalPos ? posY : currentVerticalPos)
        for (r = Math.min(posY, currentVerticalPos); r <= Math.max(posY, currentVerticalPos); r++)
            revealNeighbour(posX, r)
        var horizontalMove = posX !== currentHorizontalPos
        currentHorizontalPos = posX
        currentVerticalPos = posY
        if (horizontalMove)
            settle("x", -panelWidth * posX, panelWidth)
        else if (trayMode)
            // the crown button back to the face: the tray closes (not a gesture)
            settleTray(TrayRules.REASON.nonDrag, 0)
        else
            settle("y", -panelHeight * posY, panelHeight)
    }

    function hideOffscreen() {
        for(var rec of panels.values())
            if(rec.col !== currentHorizontalPos || rec.row !== currentVerticalPos)
                rec.item.visible = false
    }

    onWidthChanged:  { for(var rec of panels.values()) placeItem(rec) }
    onHeightChanged: { for(var rec of panels.values()) placeItem(rec) }

    /* Possible directions handling */
    property int currentVerticalPos:   0
    property int currentHorizontalPos: 0

    function changeAllowedDirections() {
        var current = cellAt(currentHorizontalPos, currentVerticalPos)
        if(current === undefined) return

        /* A move towards a neighbour is allowed when that neighbour exists and
         * the current panel does not forbid leaving in that direction. Note the
         * naming: revealing the panel *above* means the content slides down, so
         * an existing top neighbour enables toBottomAllowed, and so on. */
        toBottomAllowed = cellAt(currentHorizontalPos,   currentVerticalPos-1) !== undefined && current.item.forbidTop    !== true
        toTopAllowed    = cellAt(currentHorizontalPos,   currentVerticalPos+1) !== undefined && current.item.forbidBottom !== true
        toRightAllowed  = cellAt(currentHorizontalPos-1, currentVerticalPos)   !== undefined && current.item.forbidLeft   !== true
        toLeftAllowed   = cellAt(currentHorizontalPos+1, currentVerticalPos)   !== undefined && current.item.forbidRight  !== true

        current.item.visible = true
    }

    onCurrentVerticalPosChanged:   changeAllowedDirections()
    onCurrentHorizontalPosChanged: changeAllowedDirections()

    /* Swipe handling */

    property alias contentX: content.x
    property alias contentY: content.y

    function revealNeighbour(col, row) {
        var rec = cellAt(col, row)
        if (rec !== undefined) rec.item.visible = true
    }

    /* Only the neighbour the content moves towards shows: revealing both
     * made the quick panel (and its charging particles) draw, unseen, under
     * every swipe to the notifications */
    onContentXChanged: {
        if (displayAmbient) return
        panelsHideTimeout.restart()
        var off = content.x + currentHorizontalPos * panelWidth
        if (off < -0.5)
            revealNeighbour(currentHorizontalPos+1, currentVerticalPos)
        else if (off > 0.5)
            revealNeighbour(currentHorizontalPos-1, currentVerticalPos)
    }

    onContentYChanged: {
        if (displayAmbient) return
        panelsHideTimeout.restart()
        var off = content.y + currentVerticalPos * panelHeight
        if (off > 0.5)
            revealNeighbour(currentHorizontalPos, currentVerticalPos-1)
        else if (off < -0.5)
            revealNeighbour(currentHorizontalPos, currentVerticalPos+1)
    }

    // hide what is not on screen once things are still (after building panels)
    function hideSoon() { panelsHideTimeout.restart() }

    /* An object with dragBy(dx) and release(velocity) that a swipe to the
     * right on the middle panel drives when there is no panel on its left
     * (the Wear layout's app list) */
    property var edgeTarget: null
    captureRight: edgeTarget !== null && currentHorizontalPos === 0 && currentVerticalPos === 0
                  && cellAt(-1, 0) === undefined
    property bool _edgeDrag: false

    /* A new swipe: the finger catches a panel still gliding (as a Wear OS
     * pager does) and whether it pulls the app list is decided afresh */
    onSwipeStarted: (horizontal) => {
        _edgeDrag = false
        contentAnim.stop()
        if (!horizontal) {
            // the finger catches a tray gliding in or out, as a pager's panel
            stopTrays()
            if (trayMode)
                beginTrayDrag()
        }
    }

    onSwipeMoved: (horizontal, delta) => {
        panelsHideTimeout.stop()
        if (horizontal && (_edgeDrag || (captureRight && !toRightAllowed && delta > 0
                                         && Math.abs(content.x + currentHorizontalPos * panelWidth) < 1))) {
            _edgeDrag = true
            edgeTarget.dragBy(delta)
            return
        }
        if(horizontal) {
            contentX = content.x + delta
            var currentPanelX = -currentHorizontalPos*panelWidth
            contentX = Math.min(contentX, currentPanelX + (toRightAllowed ? panelWidth  : 0))
            contentX = Math.max(contentX, currentPanelX + (toLeftAllowed  ? -panelWidth : 0))
        } else if (trayMode && trayDragging) {
            moveTrayDrag(delta)
        } else {
            contentY = clampVertical(content.y + delta)
        }
    }

    /* where the content may be vertically: the current panel's, and one
     * further towards each neighbour that exists and may be left towards */
    function clampVertical(y) {
        var currentPanelY = -currentVerticalPos*panelHeight
        y = Math.min(y, currentPanelY + (toBottomAllowed ? panelHeight  : 0))
        return Math.max(y, currentPanelY + (toTopAllowed    ? -panelHeight : 0))
    }

    function animateIndicators() {
        rightIndicator.animateFar()
        leftIndicator.animateFar()
        topIndicator.animateFar()
        bottomIndicator.animateFar()
    }

    onSwipeReleased: (horizontal, velocity, tracing) => {
        if (_edgeDrag) {
            _edgeDrag = false
            edgeTarget.release(velocity)
            animateIndicators()
            return
        }
        if (!horizontal && trayMode && trayDragging) {
            endTrayDrag()
            animateIndicators()
            return
        }
        if(!tracing) {
            if(horizontal) {
                var locX = contentX + currentHorizontalPos * panelWidth
                if((locX > width/2) || velocity > 10 && toRightAllowed)
                    currentHorizontalPos--
                else if((locX < -width/2) || velocity < -10 && toLeftAllowed)
                    currentHorizontalPos++

                settle("x", -panelWidth*currentHorizontalPos, panelWidth)
            } else {
                var locY = contentY + currentVerticalPos * panelHeight
                if((locY > height/2 && velocity > 0) || velocity > 10 && toBottomAllowed)
                    currentVerticalPos--
                else if((locY < -height/2 && velocity < 0) || velocity < -10 && toTopAllowed)
                    currentVerticalPos++

                settle("y", -panelHeight*currentVerticalPos, panelHeight)
            }
        }

        animateIndicators()
    }

    Timer {
        id: panelsHideTimeout
        interval: 500
        running: true
        repeat: false
        onTriggered: hideOffscreen();
    }

    /* The released panel glides to its place the way the finger was
     * going: LinearOutSlowIn (0, 0, 0.2, 1) as Wear OS settles a swipe, over
     * 150 ms for a short way up to 250 ms for a whole panel (it was a 100 ms
     * linear jump) */
    function settle(prop, to, size) {
        contentAnim.stop()
        var from = prop === "x" ? content.x : content.y
        var way = size > 0 ? Math.min(1, Math.abs(to - from) / size) : 1
        contentAnim.property = prop
        contentAnim.to = to
        contentAnim.duration = 150 + 100 * way
        contentAnim.start()
    }

    NumberAnimation {
        id: contentAnim
        target: content
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]
        onStopped: panelsHideTimeout.restart()
    }

    /* ---- Trays over a still face (W2-launcher-trays) -------------------- */

    /* the vertical panels are trays (the Wear layout; Trays.build) */
    property bool trayMode: false
    /* the screen is on and interactive; an open asked for before that waits
     * 50 ms (stock iho.p) */
    property bool trayInteractive: true
    /* the crown may open a tray: the watch face is what is on the screen */
    property bool crownEnabled: true
    // ms; the crown rules read it (tests replace it)
    property var clock: function () { return Date.now() }

    /* how far out the tray of row -1 (quick settings) or 1 (the stream) is,
     * 0 (closed) to 1 */
    function trayFraction(row) {
        if (!trayMode || panelHeight <= 0)
            return 0
        return Math.max(0, Math.min(1, TrayRules.sign(row) * content.y / panelHeight))
    }
    readonly property real topTrayFraction: trayFraction(-1)
    readonly property real bottomTrayFraction: trayFraction(1)

    /* The tray's own black background: a circle over the face and under the
     * tray's content, transparent until the tray is 25 % out and opaque at
     * 50 % (TrayRules.backgroundAlpha). attachTray() makes one for a tray. */
    Component {
        id: trayBackground
        Rectangle {
            property Item tray: null
            property int row: 0
            x: tray ? tray.x : 0
            y: tray ? tray.y : 0
            width: tray ? tray.width : 0
            height: tray ? tray.height : 0
            z: 1
            radius: width / 2
            color: "#000000"
            visible: !!tray && tray.visible && panelsGrid.trayMode
            opacity: TrayRules.backgroundAlpha(panelsGrid.trayFraction(row))
        }
    }
    function attachTray(item, row) {
        if (!item)
            return
        item.z = 2
        trayBackground.createObject(content, { tray: item, row: row })
    }

    /* -- a finger on a tray -- */
    property bool trayDragging: false
    property int trayRow: 0                // the tray the finger has: -1, 1; 0 not chosen yet
    property bool _trayStartedOpen: false
    property real _s0: 0                   // how far out it was when the finger took it
    property real _travel: 0               // the finger's way since it went down (px, + = down)
    property real _lead: 0                 // what the catch-up has to make up
    property real _catch: 0                // 0..1, the catch-up's progress
    on_CatchChanged: applyTrayDrag()

    NumberAnimation {
        id: catchUp
        target: panelsGrid
        property: "_catch"
        from: 0
        to: 1
        duration: Motion.duration(TrayRules.CATCHUP_MS)
        easing.type: Easing.OutCubic          // DecelerateInterpolator(1.5)
    }

    /* the tray settles on a spring (WearSpring on the content's y) */
    WearSpring {
        id: traySpring
        target: content
        property: "y"
        onFinished: panelsHideTimeout.restart()
    }
    // its settings and state, for the tests and the diagnostics
    readonly property QtObject trayAnimation: traySpring

    function stopTrays() {
        traySpring.stop()
        catchUp.stop()
        openDelay.stop()
        if (handingOver)
            endHandOver()
        trayDragging = false
    }

    function beginTrayDrag() {
        trayDragging = true
        catchUp.stop()
        _catch = 0
        _lead = 0
        trayRow = 0
        _trayStartedOpen = currentVerticalPos !== 0
        _travel = touchPosition.y - pressPosition.y
        if (currentVerticalPos !== 0)
            chooseTray(currentVerticalPos)
        else if (Math.abs(content.y) > 0.5)
            // a tray still on its way out or in: the finger takes that one
            chooseTray(content.y > 0 ? -1 : 1)
        else if (_travel !== 0)
            chooseTray(_travel > 0 ? -1 : 1)
        applyTrayDrag()
    }

    function chooseTray(row) {
        trayRow = row
        _s0 = Math.max(0, Math.min(panelHeight, TrayRules.sign(row) * content.y))
        // a finger that went down more than 30 dp past the tray's edge: the
        // tray catches up in 300 ms
        var u = row < 0 ? pressPosition.y : panelHeight - pressPosition.y
        _lead = TrayRules.catchUpLead(_s0, u)
        if (_lead > 0)
            catchUp.restart()
    }

    function moveTrayDrag(delta) {
        _travel += delta
        if (trayRow === 0 && delta !== 0)
            chooseTray(delta > 0 ? -1 : 1)
        applyTrayDrag()
    }

    function applyTrayDrag() {
        if (!trayDragging || trayRow === 0)
            return
        var sg = TrayRules.sign(trayRow)
        var s = _s0 + sg * _travel + _lead * _catch
        s = Math.max(0, Math.min(panelHeight, s))
        contentY = clampVertical(sg * s)
    }

    // the finger lifted: where the tray goes, and how
    function endTrayDrag() {
        trayDragging = false
        catchUp.stop()
        if (trayRow === 0)
            return
        var row = trayRow
        var vy = swipeVelocityY
        var open = TrayRules.releaseOpens(_trayStartedOpen, trayFraction(row), TrayRules.sign(row) * vy)
        currentVerticalPos = open && cellAt(0, row) !== undefined ? row : 0
        settleTray(TrayRules.REASON.drag, vy)
    }

    /* Spring the tray of currentVerticalPos out (or the open one in when it
     * is 0) from the content's y at velocity (px/s, + = down; capped at
     * 2000): open 0.75/500, close 1.0/500 ending at 98 %, a move asked for by
     * a gesture 0.8/200 (TrayRules.spring) */
    function settleTray(reason, velocity) {
        var open = currentVerticalPos !== 0
        var sp = TrayRules.spring(open, reason)
        traySpring.stiffness = sp.stiffness
        traySpring.dampingRatio = sp.dampingRatio
        traySpring.stopAtFraction = sp.stopAt
        traySpring.animateTo(open ? TrayRules.sign(currentVerticalPos) * panelHeight : 0,
                             TrayRules.clampVelocity(velocity))
    }

    /* -- opening and closing a tray without a finger -- */
    property int _pendingRow: 0
    property int _pendingReason: 0
    property real _pendingVelocity: 0
    Timer {
        id: openDelay
        interval: TrayRules.DELAY_OPEN_MS
        onTriggered: panelsGrid.openTrayNow(panelsGrid._pendingRow, panelsGrid._pendingReason, panelsGrid._pendingVelocity)
    }

    function openTrayNow(row, reason, velocity) {
        stopTrays()
        revealNeighbour(0, row)
        currentVerticalPos = row
        settleTray(reason, velocity)
    }

    function openTray(row, reason, velocity) {
        if (!trayMode || currentHorizontalPos !== 0 || cellAt(0, row) === undefined)
            return false
        if (currentVerticalPos === row)
            return true
        if (!trayInteractive) {
            _pendingRow = row
            _pendingReason = reason
            _pendingVelocity = velocity
            openDelay.restart()
            return true
        }
        openTrayNow(row, reason, velocity)
        return true
    }

    function closeTray(reason) {
        if (!trayMode || currentVerticalPos === 0)
            return false
        stopTrays()
        currentVerticalPos = 0
        settleTray(reason, 0)
        return true
    }

    /* the notification stream asked for by something else (a tap on the
     * heads-up card, the Notifications complication): the tray comes up on
     * the gesture spring at 2000 px/s (stock jsm: q(0, -2000, 4)) */
    function showStream() {
        if (trayMode)
            return openTray(1, TrayRules.REASON.gesture, -TrayRules.VELOCITY_CAP)
        moveTo(0, 1)
        return true
    }

    /* -- a list at its end hands a drag over to its tray (stock nested scroll) --
     *
     * The tray's list owns a drag that starts on it (GestureFilterArea leaves
     * it alone), and the list stops at its edge: the top for the stream, the
     * end for quick settings (which opens at the bottom of its list). A finger
     * that goes on from there pulls the tray in instead (the list stays at its
     * edge meanwhile), as one gesture; lifted, the release rules above apply.
     * The tray offers the list as its handOverView. */
    property bool handingOver: false
    property real _hoY: NaN
    property int _hoBounds: 0
    property var _hoView: null
    property int _hoRow: 0

    function nestedView() {
        if (!trayMode || currentVerticalPos === 0)
            return null
        var rec = cellAt(0, currentVerticalPos)
        return rec && rec.item && rec.item.handOverView ? rec.item.handOverView : null
    }

    // the list at its edge: the stream's top, the end of the quick settings list
    function atTrayEdge(v, row) {
        return row === 1 ? v.atYBeginning : v.atYEnd
    }

    function pinList(v, row) {
        v.contentY = row === 1 ? v.originY - v.topMargin
                               : v.originY + v.contentHeight + v.bottomMargin - v.height
    }

    function beginHandOver(v, row) {
        handingOver = true
        _hoView = v
        _hoRow = row
        _hoBounds = v.boundsBehavior
        v.boundsBehavior = Flickable.StopAtBounds
        v.cancelFlick()
        traySpring.stop()
        contentAnim.stop()
        panelsHideTimeout.stop()
        trayRow = row
        _trayStartedOpen = true
    }

    function endHandOver() {
        if (_hoView)
            _hoView.boundsBehavior = _hoBounds
        _hoView = null
        handingOver = false
    }

    function handOverMoved(y) {
        var dy = isNaN(_hoY) ? 0 : y - _hoY
        _hoY = y
        if (!trayMode || trayDragging)
            return
        var v = handingOver ? _hoView : nestedView()
        if (!v || !v.dragging) {
            if (handingOver)
                endHandOver()
            return
        }
        var row = handingOver ? _hoRow : currentVerticalPos
        // the finger direction that pulls the tray in: down for the stream, up for quick settings
        var closing = row === 1 ? 1 : -1
        if (!handingOver) {
            // the list is at its edge and the finger goes on that way
            if (dy * closing <= 0 || !atTrayEdge(v, row))
                return
            beginHandOver(v, row)
        }
        // all the way out again and the finger still going the other way: the list has it back
        if (dy * closing < 0 && trayFraction(row) >= 1 - 0.5 / panelHeight) {
            endHandOver()
            return
        }
        pinList(v, row)
        contentY = row === 1 ? Math.max(-panelHeight, Math.min(0, content.y + dy))
                             : Math.max(0, Math.min(panelHeight, content.y + dy))
    }

    function handOverEnded() {
        _hoY = NaN
        if (!handingOver)
            return
        var row = _hoRow
        endHandOver()
        var vy = swipeVelocityY
        var open = TrayRules.releaseOpens(true, trayFraction(row), TrayRules.sign(row) * vy)
        currentVerticalPos = open ? row : 0
        settleTray(TrayRules.REASON.drag, vy)
    }

    onTouchMoved: handOverMoved(touchPosition.y)
    onTouchEnded: handOverEnded()

    /* -- the crown --
     *
     * RotaryInput (qml-asteroid) calls rotaryExit(direction) on the nearest
     * item that declares it when the crown has pushed 150 px past what it can
     * scroll (stock ScrollAccumulator with SysUIOverlayScrollSlop150: events
     * under 120 ms apart): direction 1 is forward (scroll down), -1 backward.
     * On the watch face nothing scrolls, so it opens a tray: forward the
     * stream, backward quick settings, not within 500 ms of a crown close.
     * With a tray out it closes it when the crown goes towards the tray's
     * edge of origin (stream: backward; quick settings: forward), not within
     * 300 ms of the crown open. */
    signal rotaryExit(int direction)
    // the edges the crown may push past: -1 start, 1 end, 0 both, 2 none
    // (RotaryInput then plays the end bump as without a receiver)
    property int rotaryExitEdge: !trayMode || currentHorizontalPos !== 0 || trayDragging ? 2
                                 : currentVerticalPos === 1 ? -1
                                 : currentVerticalPos === -1 ? 1
                                 : crownEnabled ? 0 : 2
    property real _lastCrownOpen: -1e12
    property real _lastCrownClose: -1e12

    function crownScrolled(direction) {
        if (!trayMode || trayDragging || handingOver || currentHorizontalPos !== 0)
            return false
        var now = clock()
        if (currentVerticalPos === 0) {
            if (!crownEnabled)
                return false
            var row = TrayRules.crownOpens(direction, now, _lastCrownClose)
            if (row === 0 || !openTray(row, TrayRules.REASON.nonDrag, 0))
                return false
            _lastCrownOpen = now
            return true
        }
        if (TrayRules.crownCloses(currentVerticalPos, direction, now, _lastCrownOpen)) {
            closeTray(TrayRules.REASON.nonDrag)
            _lastCrownClose = now
            return true
        }
        return false
    }
    onRotaryExit: (direction) => crownScrolled(direction)
}
