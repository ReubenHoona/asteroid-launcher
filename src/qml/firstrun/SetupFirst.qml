/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* The first setup screen (setup-wizard-02), as stock's FastPairComposableScreen: "Keep the watch & phone
 * close" under a full screen animation of a phone coming to the watch, an info chip under the title and,
 * over the bottom 22 % of the screen, the button "Choose watch language". Back is ignored here (the stack
 * has nothing under it). After `autoLanguageSeconds` of nothing the page opens the language list itself.
 *
 * Power (M1): the animation runs only while the display is on and the page is shown, one cycle is
 * 3.5 s and then it rests for 1 s; the 180 s timer is one single shot that a touch restarts. */
Item {
    id: page
    objectName: "setupFirst"

    // the display is on (not off, not ambient)
    property bool displayOn: true
    // this page is the one in front
    property bool active: visible
    readonly property bool animating: displayOn && active && !Motion.reduceMotion
    signal chooseLanguage()
    // restart the 180 s wait (a touch on the page, the page coming back)
    function touched() { autoTimer.restart() }

    readonly property alias title: title
    readonly property alias chip: chip
    readonly property alias receiver: receiver
    readonly property alias autoTimer: autoTimer
    // 0 .. 1 over one animation cycle
    property real t: 0

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    // ---- the animation: a phone comes to the watch, rings spread between them ----
    Item {
        id: scene
        objectName: "setupFirstScene"
        width: page.width
        height: page.height * Setup.first.titleTop
        clip: true

        readonly property real watchSize: width * 0.30
        readonly property real phoneW: width * 0.2
        readonly property real phoneH: width * 0.36
        readonly property real approach: Math.min(1, page.t / 0.6)
        readonly property real pulse: Math.max(0, (page.t - 0.55) / 0.45)

        // three rings spreading from the watch once the phone is near
        Repeater {
            model: 3
            Rectangle {
                required property int index
                anchors.centerIn: watch
                readonly property real p: Math.max(0, Math.min(1, scene.pulse * 1.6 - index * 0.25))
                width: scene.watchSize * (1 + 1.1 * p)
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Theme.dp(2)
                border.color: Theme.color.primary
                opacity: p > 0 && p < 1 ? 0.7 * (1 - p) : 0
            }
        }

        Rectangle {
            id: watch
            objectName: "setupFirstWatch"
            width: scene.watchSize
            height: width
            radius: width / 2
            x: scene.width * 0.56
            y: scene.height * 0.5 - height / 2
            color: Theme.color.surfaceContainer
            border.width: Theme.dp(3)
            border.color: Theme.color.onSurfaceVariant
            Icon {
                anchors.centerIn: parent
                width: parent.width * 0.5
                height: width
                name: "ios-bluetooth"
                color: Theme.color.primary
                opacity: 0.4 + 0.6 * scene.approach
            }
        }

        Rectangle {
            id: phone
            objectName: "setupFirstPhone"
            width: scene.phoneW
            height: scene.phoneH
            radius: width * 0.22
            x: scene.width * 0.06 + (scene.width * 0.30 - scene.phoneW * 0.2) * scene.approach
            y: scene.height * 0.5 - height / 2
            color: Theme.color.surfaceContainer
            border.width: Theme.dp(3)
            border.color: Theme.color.onSurfaceVariant
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.08
                width: parent.width * 0.3
                height: Theme.dp(3)
                radius: height / 2
                color: Theme.color.onSurfaceVariant
            }
        }
    }

    SequentialAnimation {
        id: cycle
        running: page.animating
        loops: Animation.Infinite
        NumberAnimation { target: page; property: "t"; from: 0; to: 1; duration: Setup.first.animationMs; easing.type: Easing.Linear }
        PauseAnimation { duration: Setup.first.pauseMs }
        onRunningChanged: if (!running) page.t = 0
    }

    // ---- the title and the chip ----
    Label {
        id: title
        objectName: "setupFirstTitle"
        x: (page.width - width) / 2
        y: Math.round(page.height * Setup.first.titleTop)
        width: Math.round(page.width * Setup.first.titleWidth)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        role: "titleMedium"
        color: Theme.color.onBackground
        //% "Keep the watch & phone close"
        text: qsTrId("id-setup-keep-close") + localeManager.changesObserver
    }

    // the interaction receiver: the bottom 22 % of the screen opens the language list; its visible part is the chip
    MouseArea {
        id: receiver
        objectName: "setupFirstReceiver"
        x: 0
        width: page.width
        height: Math.round(page.height * Setup.first.receiverHeight)
        y: page.height - height
        //% "Choose watch language"
        Accessible.name: qsTrId("id-setup-choose-language") + localeManager.changesObserver
        Accessible.role: Accessible.Button
        onPressed: autoTimer.restart()
        onClicked: page.chooseLanguage()
    }

    Rectangle {
        id: chip
        objectName: "setupFirstChip"
        width: Theme.dp(Setup.first.chipWidthDp)
        height: Theme.dp(Setup.first.chipHeightDp)
        radius: Theme.dp(Setup.first.chipRadiusDp)
        color: Theme.color.surfaceContainer
        x: (page.width - width) / 2
        // 5 % of the height under the title
        y: title.y + title.height + Math.round(page.height * Setup.first.chipGap)
        Icon {
            anchors.centerIn: parent
            width: Theme.dp(Setup.first.chipGlyphDp)
            height: width
            name: "ios-information"
            color: Theme.color.onSurfaceVariant
        }
        Accessible.ignored: true
    }

    // 180 s of nothing: the list opens by itself (a single shot; nothing runs while the page is not in front)
    Timer {
        id: autoTimer
        interval: Setup.autoLanguageSeconds * 1000
        running: page.active
        onTriggered: page.chooseLanguage()
    }

    // a touch anywhere is a user being there
    PointHandler {
        acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Mouse
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) autoTimer.restart()
    }
}
