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

/*
 * A new notification as Wear OS shows it: a peek card slides up at the
 * bottom of the screen over whatever is there (250 ms, EmphasizedDecelerate),
 * with the app, the title and the newest lines (and a message's picture, as a
 * wide strip; never on the always-on display). A tap opens the
 * notification in the stream, a swipe down or to the side puts the card
 * away (the notification stays in the stream), and it goes by itself after
 * 5 s. Only the card takes touches.
 */
Item {
    id: notificationWindow
    width: initialSize.width
    height: initialSize.height

    readonly property QtObject notification: notificationPreviewPresenter.notification
    property QtObject shownNotification: null
    // 0 hidden .. 1 up
    property real slide: 0
    property real dragX: 0
    property real dragY: 0
    property real flyTo: 0

    function show() {
        hideAnim.stop()
        shownNotification = notification
        dragX = 0
        dragY = 0
        showAnim.restart()
        hideTimer.restart()
    }

    // away: down by default, or off to the side it was swiped
    function hide() {
        if (slide <= 0 && !showAnim.running) {
            notificationPreviewPresenter.showNextNotification()
            return
        }
        hideTimer.stop()
        showAnim.stop()
        flyTo = dragX === 0 ? 0 : (dragX > 0 ? 1 : -1) * width
        hideAnim.restart()
    }

    function open() {
        var n = shownNotification
        hide()
        if (n && Desktop.desktop && Desktop.desktop.openNotification)
            Desktop.desktop.openNotification(n)
    }

    Connections {
        target: notificationPreviewPresenter
        function onNotificationChanged() {
            if (notificationPreviewPresenter.notification != null)
                notificationWindow.show()
            else if (notificationWindow.slide > 0)
                notificationWindow.hide()
        }
    }

    NumberAnimation {
        id: showAnim
        target: notificationWindow
        property: "slide"
        to: 1
        duration: 250
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.05, 0.7, 0.1, 1, 1, 1]
    }

    SequentialAnimation {
        id: hideAnim
        ParallelAnimation {
            NumberAnimation {
                target: notificationWindow; property: "slide"; to: 0; duration: 200
                easing.type: Easing.BezierSpline; easing.bezierCurve: [0.3, 0, 0.8, 0.15, 1, 1]
            }
            NumberAnimation {
                target: notificationWindow; property: "dragX"; duration: 200
                to: notificationWindow.flyTo
            }
        }
        ScriptAction {
            script: {
                notificationWindow.shownNotification = null
                notificationWindow.dragX = 0
                notificationWindow.dragY = 0
                notificationPreviewPresenter.showNextNotification()
            }
        }
    }

    NumberAnimation {
        id: settleAnim
        target: notificationWindow
        properties: "dragX,dragY"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]
    }

    Timer {
        id: hideTimer
        interval: 5000
        onTriggered: if (!drag.active) notificationWindow.hide()
    }

    Item {
        id: card
        visible: notificationWindow.slide > 0 && notificationWindow.shownNotification !== null
        width: Math.round(notificationWindow.width * 0.7)
        height: content.height + 2 * pad
        readonly property real pad: Dims.l(4.5)
        readonly property real restY: notificationWindow.height - height - Math.round(notificationWindow.height * 0.1)
        x: (notificationWindow.width - width) / 2 + notificationWindow.dragX
        y: notificationWindow.height + (restY - notificationWindow.height) * notificationWindow.slide
           + Math.max(0, notificationWindow.dragY)
        opacity: 1 - Math.min(1, Math.abs(notificationWindow.dragX) / width) * 0.8

        Rectangle {
            anchors.fill: parent
            radius: Math.min(height / 2, Dims.l(8))
            color: tap.pressed ? "#3a3a3d" : "#262628"
            border.color: "#3c4043"
            border.width: 1
        }

        Column {
            id: content
            x: card.pad
            y: card.pad
            width: card.width - 2 * card.pad
            spacing: picture.visible ? Dims.h(2) : 0

            NotificationText {
                width: parent.width
                compact: true
                notification: notificationWindow.shownNotification
                //% "Now"
                timestamp: qsTrId("id-now")
            }

            // A message's picture, cropped to a wide strip in the peek card
            NotificationPicture {
                id: picture
                width: parent.width
                maxHeight: Math.round(width * 0.56)
                radius: Math.max(0, Math.min(card.height / 2, Dims.l(8)) - card.pad)
                notification: notificationWindow.shownNotification
            }
        }

        TapHandler {
            id: tap
            onTapped: notificationWindow.open()
        }

        DragHandler {
            id: drag
            target: null
            onTranslationChanged: {
                if (!active)
                    return
                // sideways, or down; not up
                if (Math.abs(translation.x) > Math.abs(translation.y)) {
                    notificationWindow.dragX = translation.x
                    notificationWindow.dragY = 0
                } else {
                    notificationWindow.dragX = 0
                    notificationWindow.dragY = Math.max(0, translation.y)
                }
            }
            onActiveChanged: {
                if (active) {
                    settleAnim.stop()
                    return
                }
                if (Math.abs(notificationWindow.dragX) > card.width / 3 || notificationWindow.dragY > card.height / 3)
                    notificationWindow.hide()
                else {
                    settleAnim.restart()
                    hideTimer.restart()
                }
            }
        }
    }
}
