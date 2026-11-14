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
import org.nemomobile.lipstick
import "status.js" as Status
import "ongoing.js" as Ongoing
import ".."

/* The status slot of the home screen (split out of MainScreen.qml): what the watch
 * face overlay of stock Wear OS draws over the face (W2-launcher-status):
 *   - the status icon, one at a time at the top centre (FaceStatusIcon, fed by
 *     StatusSources: the 16 stock types in the stock order);
 *   - the unread notification bar at the bottom (NotificationIndicator);
 *   - the ongoing activity chip at the bottom, the Live Space (LiveSpace, fed by the
 *     ongoing registry, OngoingFeed, MediaOngoing);
 *   - the four edge hints of the AsteroidOS layout (stock draws none on the Wear
 *     layout's face: status-indicators-10).
 * Instantiated once in MainScreen as `statusSlot`, at z 0 above the grid as before;
 * MainScreen forwards rightIndicator, leftIndicator, topIndicator and bottomIndicator
 * (the grid, the app launchers and the first-run wizard use them). Reads MainScreen's
 * `grid` and `desktop` through the context.
 *
 * Battery: everything here follows signals; the icon and the chip draw static, at full
 * opacity, with no animation in the always-on screen, and the sensor hub draws what the AP
 * drew last: `ambientIconsKey` says when that changes (AmbientController invalidates the hub's
 * layout once per change). */
Item {
    id: statusSlot
    anchors.fill: parent

    readonly property Item notificationIndicator: notifIndicator
    readonly property Item rightIndicator: rightEdgeIndicator
    readonly property Item leftIndicator: leftEdgeIndicator
    readonly property Item topIndicator: topEdgeIndicator
    readonly property Item bottomIndicator: bottomEdgeIndicator
    readonly property Item sources: statusSources
    readonly property Item statusIcon: faceStatus
    readonly property Item liveSpace: chip
    readonly property Item feed: ongoingFeed
    readonly property Item media: mediaOngoing

    // the Wear layout (MainScreen's): no edge hints there
    readonly property bool wearLayout: typeof desktop === "undefined" || !desktop || desktop.wearLayout !== false
    // the screen is on and showing: the icon and the chip animate; else they are static
    readonly property bool interactive: (typeof desktop === "undefined" || !desktop
                                         || (desktop.displayAwake === true && desktop.displayAmbient !== true))
    // what the sensor hub's always-on layout depends on: the status icon and the chip's icon
    readonly property string ambientIconsKey: Status.ambientKey(statusSources.slotKey, chip.ambientKey)

    NotificationIndicator {
        id: notifIndicator
        anchors.top: parent.top
        anchors.topMargin: Dims.h(5)
        height: Dims.h(8)
        width: parent.width
        panelsGrid: grid
    }

    // gone as the face is swiped away (the dot's rule: a panel over the face covers them)
    Item {
        id: overlayPart
        objectName: "overlayPart"
        anchors.fill: parent
        readonly property real offset: typeof grid !== "undefined" && grid
                                       ? Math.abs(grid.normalizedHorOffset) + Math.abs(grid.normalizedVerOffset) : 0
        opacity: Math.max(0, 1 - 3 * offset)
        visible: opacity > 0

        StatusSources { id: statusSources }

        FaceStatusIcon {
            id: faceStatus
            slotKey: statusSources.slotKey
            interactive: statusSlot.interactive
        }

        LiveSpace {
            id: chip
            entry: ongoingFeed.registry ? ongoingFeed.registry.top : ({})
            interactive: statusSlot.interactive
            iconOnly: ongoingFeed.isIconOnly(entry && entry.app ? entry.app : "")
            onTapped: function (key, app) {
                if (ongoingFeed.registry)
                    ongoingFeed.registry.activate(key)
            }
            onMenuRequested: function (key, app, title) { statusSlot.openLiveMenu(app, title) }
        }
    }

    // the long press menu of a live update (the chip's and the stream's): stock's list with the
    // display style and the mute button (LiveMenu); `who` is the entry's title (the app's name)
    function openLiveMenu(app, who) {
        if (!app)
            return
        liveMenu.app = app
        liveMenu.who = who
        liveMenu.open()
    }

    OngoingFeed { id: ongoingFeed }
    MediaOngoing { id: mediaOngoing }

    // long press on a live update: stock ini.java:160-230 (jfm), hdw.java:1170-1262
    LiveMenu {
        id: liveMenu
        iconOnly: ongoingFeed.isIconOnly(app)
        companion: "Gadgetbridge"
        onStyleChosen: function (only) { ongoingFeed.setIconOnly(app, only) }
        onMuteRequested: muteConfirm.open()
    }

    // the button asked: confirm first (jfi, ini.java:226: mute_live_update_confirmation_dialog_title /
    // _description; the description names the phone app)
    AlertDialog {
        id: muteConfirm
        objectName: "liveMuteConfirm"
        //% "Turn off %1 live updates?"
        title: qsTrId("id-live-turn-off-title").arg(liveMenu.who)
        //% "You can still manage settings in the %1 app on your phone"
        text: qsTrId("id-live-turn-off-text").arg(liveMenu.companion)
        onConfirmed: {
            ongoingFeed.mute(liveMenu.app)
            liveMenu.close()
        }
    }

    // the edge hints belong to the AsteroidOS layout; the Wear layout's face has none
    Item {
        id: edgeHints
        objectName: "edgeHints"
        anchors.fill: parent
        visible: !statusSlot.wearLayout

        Indicator { id: rightEdgeIndicator; edge: Qt.RightEdge }
        Indicator { id: leftEdgeIndicator; edge: Qt.LeftEdge }
        Indicator { id: topEdgeIndicator; edge: Qt.TopEdge }
        Indicator { id: bottomEdgeIndicator; edge: Qt.BottomEdge }
    }
}
