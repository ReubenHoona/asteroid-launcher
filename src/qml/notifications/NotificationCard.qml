/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * One card of the notification stream, as Wear OS draws them: a rounded
 * dark card with the app, the time, the title and the newest lines (and a
 * message's picture, NotificationPicture, under them). A tap
 * opens it; a swipe to either side drags it along under the finger and,
 * past a third of its width or on a flick, sends it off the screen and
 * dismisses it; otherwise it settles back (200 ms, LinearOutSlowIn).
 * "extra" > 0 shows the "+N" of a collapsed group. A long press (Wear OS:
 * the app's notification settings, BlockingMenu) is longPressed().
 */
Item {
    id: card

    property QtObject notification
    property string timestamp: ""
    property int extra: 0

    signal tapped()
    signal dismissed()
    signal longPressed()
    // the finger that pressed the card is still down (after a long press too)
    readonly property bool held: tap.pressed

    // horizontal offset while dragged or flying off
    property real dx: 0
    readonly property real progress: width > 0 ? Math.min(1, Math.abs(dx) / width) : 0

    height: bg.height
    opacity: 1 - 0.85 * progress
    transform: Translate { x: card.dx }

    function flyOff(direction) {
        settle.stop()
        fly.to = direction * card.width * 1.15
        flyAnim.restart()
    }

    Rectangle {
        id: bg
        width: parent.width
        height: content.height + 2 * card.pad
        radius: Theme.shape.clamp(Theme.shape.large, height)
        color: tap.pressed ? Qt.tint(Theme.color.surfaceContainer, Qt.alpha(Theme.color.onSurface, Theme.alpha.pressed)) : Theme.color.surfaceContainer
    }
    readonly property real pad: Dims.l(4.5)

    Column {
        id: content
        x: card.pad
        y: card.pad
        width: card.width - 2 * card.pad
        spacing: picture.visible ? Dims.h(2.5) : 0

        NotificationText {
            width: parent.width - (badge.visible ? badge.width : 0)
            compact: true
            notification: card.notification
            timestamp: card.timestamp
        }

        // A message's picture, at most square here (the full view has all of it)
        NotificationPicture {
            id: picture
            width: parent.width
            maxHeight: width
            radius: Math.max(0, bg.radius - card.pad)
            notification: card.notification
        }
    }

    Rectangle {
        id: badge
        visible: card.extra > 0
        anchors.right: bg.right
        anchors.rightMargin: card.pad * 0.8
        anchors.top: bg.top
        anchors.topMargin: card.pad * 0.8
        height: Dims.l(8)
        width: Math.max(height, badgeLabel.implicitWidth + height * 0.6)
        radius: height / 2
        color: Theme.color.primary
        Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: "+" + card.extra
            color: Theme.color.onPrimary
            font.pixelSize: Theme.type.bodyExtraSmall.pixelSize
            font.styleName: "SemiCondensed Medium"
        }
    }

    TapHandler {
        id: tap
        // as the watchface's long press (the face picker)
        longPressThreshold: 0.5
        onTapped: card.tapped()
        onLongPressed: card.longPressed()
    }

    DragHandler {
        id: drag
        target: null
        xAxis.enabled: true
        yAxis.enabled: false
        onActiveChanged: {
            if (active) {
                settle.stop()
                flyAnim.stop()
                return
            }
            var v = centroid.velocity.x
            if (Math.abs(card.dx) > card.width / 3 || Math.abs(v) > 600 && v * card.dx > 0)
                card.flyOff(card.dx < 0 ? -1 : 1)
            else
                settle.restart()
        }
        onTranslationChanged: if (active) card.dx = translation.x
    }

    NumberAnimation {
        id: settle
        target: card
        property: "dx"
        to: 0
        duration: 200
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0, 0, 0.2, 1, 1, 1]
    }

    SequentialAnimation {
        id: flyAnim
        NumberAnimation {
            id: fly
            target: card
            property: "dx"
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
        }
        ScriptAction {
            script: {
                Haptics.click()
                card.dismissed()
            }
        }
    }
}
