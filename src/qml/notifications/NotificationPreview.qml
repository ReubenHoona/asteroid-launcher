/*
 * Copyright (C) 2015 Florent Revest <revestflo@gmail.com>
 *               2014 Aleksi Suomalainen <suomalainen.aleksi@gmail.com>
 *               2012 Jolla Ltd.
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
import ".."
import "../desktop.js" as Desktop
import "headsup.js" as HU

/*
 * A new notification as Wear OS CP3A shows it (W2-launcher-heads-up). What
 * alerts, when, and with or without waking the display is the presenter's
 * (lipstick eosalertpolicy.h); this draws what it hands over:
 *  - kind 1, the face is the current panel: the glanceable (Glanceable.qml),
 *    the whole round screen. 1000 ms later (1500 ms with Show new
 *    notifications = Immediately) it turns into the full notification view
 *    (HeadsUpDetail.qml): it fades out growing to 1.15 in 100 ms, then the view
 *    fades in over 100 ms scaling 0.85 -> 1 over 500 ms. A tap on the
 *    glanceable goes there at once. There is no auto-dismiss: it stays until
 *    the display leaves ON (the presenter brings it back if the display is on
 *    again within 10 s) or the user closes it, with the crown (alpha and scale
 *    to 0 in 300 ms) or a swipe right; closing returns to the face and the
 *    notification stays in the list;
 *  - kind 2, anywhere else (an app, the tiles, the app list): the icon bubble
 *    (HunBubble.qml), 3000 ms; a tap or a drag up grows the full view over
 *    whatever is there and closing it leaves what was under it open.
 * Only what is drawn takes touches (the bubble: its icon area). Nothing runs
 * but the animation in front; the display going off clears the presenter's
 * notification and ends it at once.
 */
Item {
    id: preview
    width: initialSize.width
    height: initialSize.height
    visible: mode !== "none"

    readonly property QtObject notification: notificationPreviewPresenter.notification
    property QtObject shownNotification: null
    // none, glance, full (over the face), bubble, closing
    property string mode: "none"

    // set by the compositor from the home screen: the face is the current panel with
    // nothing over it; the notification list is the current panel (no card over it)
    property bool faceCurrent: false
    property bool streamCurrent: false

    // the glanceable, then the full view or a bubble's window is showing: the crown and the
    // swipe back are the view's (the key router asks)
    readonly property bool viewShown: mode === "glance" || mode === "full" || (mode === "bubble" && bubble.windowUp)
    readonly property bool immediately: notificationPreviewPresenter.showImmediately === true
    // the morph's and the closing's numbers, for the tests
    property real glanceOpacity: 1
    property real glanceScale: 1
    property real detailOpacity: 1
    property real detailScale: 1
    property bool detailActive: false

    readonly property Item glanceItem: glance
    readonly property Item bubbleItem: bubble
    readonly property Item detailItem: detailLoader.item
    readonly property Item detailHost: detailLoader
    readonly property Timer stageTimer: stage
    readonly property real stageMs: immediately ? HU.STAGE.holdImmediate : HU.STAGE.hold

    property bool _finishing: false

    Binding { target: notificationPreviewPresenter; property: "faceCurrent"; value: preview.faceCurrent }
    Binding { target: notificationPreviewPresenter; property: "surfaceBusy"; value: preview.streamCurrent }
    Binding {
        target: notificationPreviewPresenter
        property: "detailOpen"
        value: preview.mode === "full" || (preview.mode === "bubble" && bubble.windowUp)
    }

    // the bubble ends without telling the preview it is done (finish() is the one that does)
    function clearBubble() {
        var was = _finishing
        _finishing = true
        bubble.dismissNow()
        _finishing = was
    }

    function show(n, kind) {
        stage.stop()
        morph.stop()
        crownGlance.stop()
        crownDetail.stop()
        glance.stop()
        clearBubble()
        detailActive = false
        glanceOpacity = 1
        glanceScale = 1
        detailOpacity = 1
        detailScale = 1
        shownNotification = n
        if (kind === 1) {
            mode = "glance"
            glance.start()
            stage.interval = stageMs
            stage.restart()
        } else {
            mode = "bubble"
            bubble.start()
        }
    }

    // Everything away (the presenter cleared the notification, the display went off, a call)
    function reset() {
        stage.stop()
        morph.stop()
        crownGlance.stop()
        crownDetail.stop()
        glance.stop()
        clearBubble()
        detailActive = false
        glanceOpacity = 1
        glanceScale = 1
        detailOpacity = 1
        detailScale = 1
        shownNotification = null
        mode = "none"
    }

    // Done with this one: away, and the next alert of the queue, if any
    function finish() {
        if (_finishing)
            return
        _finishing = true
        reset()
        _finishing = false
        notificationPreviewPresenter.showNextNotification()
    }

    // as before: put the card away now (an alarm or a call took the screen)
    function hide() {
        if (mode === "none")
            return
        finish()
    }

    // The glanceable becomes the full view (its time ran out, or a tap)
    function toFull() {
        if (mode !== "glance")
            return
        stage.stop()
        glance.stop()
        detailOpacity = 0
        detailScale = HU.MORPH.detailScaleFrom
        detailActive = true
        morph.restart()
    }

    // The crown while a view shows: a keyboard of the reply goes first; then the
    // face glanceable and the full view over it end in 300 ms (alpha and scale to
    // 0), the bubble's expanded view fades out (300 ms, cubic 0, 0, 0.2, 1) and the
    // app under it stays
    function closeFromCrown() {
        if (Desktop.keyboard && Desktop.keyboard.dismiss) {
            Desktop.keyboard.dismiss()
            return
        }
        if (mode === "glance") {
            stage.stop()
            crownGlance.restart()
        } else if (mode === "full") {
            morph.stop()
            crownDetail.restart()
        } else if (mode === "bubble" && bubble.windowUp) {
            bubble.closeExpanded()
        }
    }

    Connections {
        target: notificationPreviewPresenter
        function onNotificationChanged() {
            var n = notificationPreviewPresenter.notification
            if (n === null || n === undefined)
                preview.reset()
            else
                preview.show(n, notificationPreviewPresenter.kind)
        }
    }

    // the face is not the current panel any more: the glanceable is not for here
    onFaceCurrentChanged: if (!faceCurrent && mode === "glance") finish()

    // one single shot, only while the glanceable shows
    Timer {
        id: stage
        repeat: false
        onTriggered: preview.toFull()
    }

    SequentialAnimation {
        id: morph
        ParallelAnimation {
            NumberAnimation { target: preview; property: "glanceOpacity"; to: 0; duration: Motion.duration(HU.MORPH.glanceFadeMs) }
            NumberAnimation { target: preview; property: "glanceScale"; to: HU.MORPH.glanceScaleTo; duration: Motion.duration(HU.MORPH.glanceFadeMs) }
        }
        ScriptAction { script: preview.mode = "full" }
        ParallelAnimation {
            NumberAnimation { target: preview; property: "detailOpacity"; to: 1; duration: Motion.duration(HU.MORPH.detailFadeMs) }
            NumberAnimation {
                target: preview; property: "detailScale"; to: 1
                duration: Motion.duration(HU.MORPH.detailScaleMs)
                easing.type: Easing.InOutQuad
            }
        }
    }

    ParallelAnimation {
        id: crownGlance
        NumberAnimation { target: preview; property: "glanceOpacity"; to: 0; duration: Motion.duration(HU.MORPH.crownCloseMs) }
        NumberAnimation { target: preview; property: "glanceScale"; to: 0; duration: Motion.duration(HU.MORPH.crownCloseMs) }
        onFinished: preview.finish()
    }
    ParallelAnimation {
        id: crownDetail
        NumberAnimation { target: preview; property: "detailOpacity"; to: 0; duration: Motion.duration(HU.MORPH.crownCloseMs) }
        NumberAnimation { target: preview; property: "detailScale"; to: 0; duration: Motion.duration(HU.MORPH.crownCloseMs) }
        onFinished: preview.finish()
    }

    Glanceable {
        id: glance
        anchors.fill: parent
        visible: preview.mode === "glance" || (morph.running && preview.glanceOpacity > 0)
        opacity: preview.glanceOpacity
        scale: preview.glanceScale
        notification: preview.shownNotification
        onTapped: preview.toFull()
    }

    HunBubble {
        id: bubble
        anchors.fill: parent
        notification: preview.shownNotification
        queued: notificationPreviewPresenter.waiting === true
        onFinished: if (preview.mode === "bubble") preview.finish()
        onWindowUpChanged: if (windowUp) preview.detailActive = true
    }

    Loader {
        id: detailLoader
        z: 2
        width: preview.width
        height: preview.height
        active: preview.detailActive
        y: preview.mode === "bubble" ? preview.height * (1 - bubble.p) : 0
        opacity: preview.mode === "bubble" ? bubble.closeOpacity : preview.detailOpacity
        scale: preview.mode === "bubble" ? 1 : preview.detailScale
        visible: active && opacity > 0
        sourceComponent: HeadsUpDetail {
            notification: preview.shownNotification
            isActive: function (id) { return preview.mode !== "none" }
            onCloseRequested: preview.finish()
        }
    }
}
