/*
 * Copyright (C) 2026 Timo Könnecke <github.com/moWerk>
 *               2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
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
import ".."

/* The status slot of the home screen (split out of MainScreen.qml): the
 * unread notification indicator at the top and the four edge hints.
 * Instantiated once in MainScreen as `statusSlot`, at z 0 above the grid
 * as before; MainScreen forwards rightIndicator, leftIndicator,
 * topIndicator and bottomIndicator (the grid, the app launchers and the
 * first-run wizard use them). Reads MainScreen's `grid` through the
 * context. Owned by W2-launcher-status. */
Item {
    id: statusSlot
    anchors.fill: parent

    readonly property Item notificationIndicator: notifIndicator
    readonly property Item rightIndicator: rightEdgeIndicator
    readonly property Item leftIndicator: leftEdgeIndicator
    readonly property Item topIndicator: topEdgeIndicator
    readonly property Item bottomIndicator: bottomEdgeIndicator

    NotificationIndicator {
        id: notifIndicator
        anchors.top: parent.top
        anchors.topMargin: Dims.h(5)
        height: Dims.h(8)
        width: parent.width
        panelsGrid: grid
    }

    Indicator { id: rightEdgeIndicator; edge: Qt.RightEdge }
    Indicator { id: leftEdgeIndicator; edge: Qt.LeftEdge }
    Indicator { id: topEdgeIndicator; edge: Qt.TopEdge }
    Indicator { id: bottomEdgeIndicator; edge: Qt.BottomEdge }
}
