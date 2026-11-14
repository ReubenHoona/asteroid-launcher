/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "setup.js" as Setup

/* "Setup complete" (setup-wizard-06), as stock's SuccessMessageComposableScreen: the title (16 sp, weight
 * 550, 72 % wide) under a check in a scalloped badge that draws itself in 1.0 s, its centre at 33.3 % of the
 * height. Then the badge shrinks to 82 % and badge and title slide up (the title 58 dp) on a critically
 * damped spring of stiffness 260; 1000 ms later `finished` is emitted: the setup goes to the watch face with
 * the completion sound and vibration (the caller plays them: see FirstRunConfig).
 *
 * Power (M1): the sequence runs once; the timers are single shots; nothing runs after `finished`. */
Item {
    id: page
    objectName: "setupComplete"

    signal finished()

    // 0 = the check is drawing, 1 = sliding, 2 = holding, 3 = done
    property int phase: 0
    // the slide's spring, 0 .. 1
    readonly property real slide: spring.value
    readonly property alias check: check
    readonly property alias title: title
    readonly property alias spring: spring
    readonly property real iconScale: 1 - (1 - Setup.complete.shrink) * slide
    // the title rises from `titleOffset` below its place to it
    readonly property real titleOffset: Theme.dp(Setup.complete.titleOffsetDp)

    function start() {
        phase = 0
        spring.snapTo(0)
        check.play()
        if (check.duration <= 0 || Motion.reduceMotion)
            _slideNow()
        else
            checkEnd.restart()
    }

    function _slideNow() {
        phase = 1
        spring.animateTo(1)
        holdTimer.restart()
    }

    Component.onCompleted: start()

    Rectangle {
        anchors.fill: parent
        color: Theme.color.background
    }

    // badge and title as one group that slides up
    Item {
        id: group
        anchors.fill: parent

        SetupCheck {
            id: check
            x: (page.width - width) / 2
            // centre at 33.3 % of the height, rising by 58 dp with the slide
            y: page.height * Setup.complete.checkCenter - height / 2 - page.slide * page.titleOffset * 0.5
            size: Theme.dp(Setup.complete.checkDp)
            duration: Setup.complete.checkMs
            scale: page.iconScale
        }

        Label {
            id: title
            objectName: "setupCompleteTitle"
            x: (page.width - width) / 2
            width: Math.round(page.width * Setup.complete.titleWidth)
            // under the badge; the slide lifts it by the offset
            y: page.height * Setup.complete.checkCenter + check.badgeSize / 2 + Theme.dp(12) - page.slide * page.titleOffset
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "titleMedium"
            color: Theme.color.onBackground
            //% "Setup complete"
            text: qsTrId("id-setup-complete") + localeManager.changesObserver
        }
    }

    WearSpring {
        id: spring
        stiffness: Setup.complete.stiffness
        dampingRatio: Setup.complete.dampingRatio
        visibilityThreshold: 0.002
    }

    // the check has drawn: slide
    Timer {
        id: checkEnd
        interval: Setup.complete.checkMs
        onTriggered: page._slideNow()
    }

    // 1000 ms after the slide starts the setup leaves
    Timer {
        id: holdTimer
        interval: Setup.complete.holdMs
        onTriggered: {
            page.phase = 3
            page.finished()
        }
    }
}
