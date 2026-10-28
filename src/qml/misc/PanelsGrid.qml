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
import org.asteroid.launcher

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
    }

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

    function addPanel(horizontalPos, verticalPos, component) {
        if (component.status === Component.Ready) {
            var rec = { item: component.createObject(content), col: horizontalPos, row: verticalPos }
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
        } else {
            contentY = content.y + delta
            var currentPanelY = -currentVerticalPos*panelHeight
            contentY = Math.min(contentY, currentPanelY + (toBottomAllowed ? panelHeight  : 0))
            contentY = Math.max(contentY, currentPanelY + (toTopAllowed    ? -panelHeight : 0))
        }
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
}
