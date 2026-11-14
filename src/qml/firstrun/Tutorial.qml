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
import Nemo.Configuration
import Nemo.DBus
import "../desktop.js" as Desktop
import "tutorial.js" as Tut

/* The navigation tutorial (setup-wizard-01, choice-settings-12), an interactive coach over the real home
 * screen as stock CP3A's, after Setup complete:
 *
 *   welcome (2500 ms of our greeting animation, "Hi there" at 2000 ms, the 59 dp arrow button at 2800 ms)
 *   -> "Let's review some navigation basics!" (Continue / Skip)
 *   -> "Swipe up for notifications" (an example notification is posted; 3000 ms once it is open)
 *   -> "Swipe down for Quick Settings" (3000 ms) -> "Swipe left or right to cycle through widgets"
 *   -> "Keep swiping left for more widgets" and "... right ..." (3000 ms each)
 *   -> "Widgets provide quick access to helpful info" (a check button) -> "All set" (1000 ms)
 *   -> "Press the crown to return to the watch face" (3000 ms on the face)
 *   -> "From the watch face, press the crown to see apps"
 *   -> the side button step: the text and the end follow the side button setting
 *   -> "Time to explore your watch!" (a check, a 59 dp confirm button, our chime; closes itself after 5 s).
 *
 * The coach never takes a touch from the home screen: the dim layer and the tips are only drawn over it; each
 * step ends when the home screen shows that the gesture was done (the grid's position, the app list, Recents,
 * the assistant). A step that is not done times out after 15 minutes (an hour for the first two): the tutorial
 * then ends as Skip does. Finishing, Skip and a timeout write the end (firstRun.finishTutorial) and take the
 * example notification away.
 *
 * Power (M1): the steps are driven by the home screen's own changes; the timers are single shots and the hint
 * animations stop with the display. */
Item {
    id: tuto
    objectName: "tutorial"
    anchors.fill: parent

    property bool displayOn: true
    // the tutorial is over: the host removes it
    signal done()

    // ---- what the home screen is doing ----
    readonly property var grid: Desktop.panelsGrid
    readonly property var desk: Desktop.desktop
    readonly property int vpos: grid ? grid.currentVerticalPos : 0
    readonly property int hpos: grid ? grid.currentHorizontalPos : 0
    readonly property bool drawerOpen: desk && desk.appDrawer ? desk.appDrawer.isOpen === true : false
    readonly property bool recentsOpen: desk && desk.recents ? desk.recents.isOpen === true : false
    readonly property bool assistantShown: Desktop.compositorRoot ? Desktop.compositorRoot.assistantShown === true : false

    ConfigurationValue {
        id: sideButton
        key: "/org/asteroidos/ux/side-button"
        defaultValue: "assistant"
    }
    readonly property string sideMode: Tut.sideMode(sideButton.value)

    readonly property var snap: ({ vpos: vpos, hpos: hpos, drawerOpen: drawerOpen, recentsOpen: recentsOpen,
                                   assistantShown: assistantShown, side: sideButton.value })
    onSnapChanged: check()

    // ---- the script ----
    property string step: "welcome"
    // the step's gesture is done and its result is being shown
    property bool holding: false
    property int exampleId: 0
    property bool finished: false

    readonly property alias stepTimeout: stepTimeout
    readonly property alias holdTimer: holdTimer
    readonly property alias autoClose: autoClose
    readonly property alias hint: hint
    // the welcome animation's clock, 0 .. 2800 ms
    property real welcomeT: 0
    readonly property bool textShown: welcomeT >= Tut.welcome.textDelayMs
    readonly property bool buttonShown: welcomeT >= Tut.welcome.buttonDelayMs
    readonly property alias welcomeAnim: welcomeAnim

    Component.onCompleted: enter("welcome")
    Component.onDestruction: closeExample()

    function enter(id) {
        step = id
        holding = false
        holdTimer.stop()
        stepTimeout.interval = Tut.stepTimeout(id)
        stepTimeout.restart()
        if (id === "welcome") {
            welcomeT = 0
            welcomeAnim.restart()
        } else if (id === "notifications") {
            postExample()
        } else if (id === "done") {
            stepTimeout.stop()
            completionCheck.play()
            Haptics.play("eos_tutorial_done")
            autoClose.restart()
            return
        }
        if (Tut.timed(id))
            startHold(Tut.hold(id) > 0 ? Tut.hold(id) : Tut.holdMs)
        else
            check()
    }

    function startHold(ms) {
        holding = true
        holdTimer.interval = ms
        holdTimer.restart()
    }

    // the gesture of the step may have been done (also when the step is entered after it)
    function check() {
        if (finished || holding || Tut.timed(step) || Tut.done(step, snap) !== true)
            return
        var h = Tut.hold(step)
        if (h > 0)
            startHold(h)
        else
            advance()
    }

    function advance() {
        holding = false
        // the side button step ends: the assistant that the press opened is closed again
        if (step === "sideButton" && sideMode === "assistant" && Desktop.compositorRoot
                && Desktop.compositorRoot.closeAssistant && assistantShown)
            Desktop.compositorRoot.closeAssistant()
        var n = Tut.next(step)
        if (n === "")
            finish()
        else
            enter(n)
    }

    function finish() {
        if (finished)
            return
        finished = true
        stepTimeout.stop()
        holdTimer.stop()
        autoClose.stop()
        closeExample()
        firstRun.finishTutorial()
        done()
    }

    // ---- the example notification: stock posts "Welcome to your watch." and the stream shows it ----
    DBusInterface {
        id: notifier
        bus: DBus.SessionBus
        service: "org.freedesktop.Notifications"
        path: "/org/freedesktop/Notifications"
        iface: "org.freedesktop.Notifications"
    }
    function postExample() {
        if (exampleId !== 0)
            return
        notifier.typedCall("Notify", [
            { "type": "s", "value": Tut.exampleApp },
            { "type": "u", "value": 0 },
            { "type": "s", "value": "ios-watch" },
            //% "Welcome to your watch."
            { "type": "s", "value": qsTrId("id-tutorial-example-title") },
            { "type": "s", "value": "" },
            { "type": "as", "value": [] },
            { "type": "a{sv}", "value": {} },
            { "type": "i", "value": -1 }
        ], function (id) { tuto.exampleId = id }, function () { tuto.exampleId = 0 })
    }
    function closeExample() {
        if (exampleId === 0)
            return
        notifier.typedCall("CloseNotification", [{ "type": "u", "value": exampleId }])
        exampleId = 0
    }

    // ---- timers ----
    Timer {
        id: stepTimeout
        objectName: "tutorialStepTimeout"
        onTriggered: tuto.finish()
    }
    Timer {
        id: holdTimer
        objectName: "tutorialHoldTimer"
        onTriggered: tuto.advance()
    }
    Timer {
        id: autoClose
        objectName: "tutorialAutoClose"
        interval: Tut.autoCloseMs
        onTriggered: tuto.finish()
    }

    // ---- the welcome ----
    NumberAnimation {
        id: welcomeAnim
        target: tuto
        property: "welcomeT"
        from: 0
        to: Tut.welcome.buttonDelayMs
        duration: Motion.duration(Tut.welcome.buttonDelayMs)
        running: false
        onFinished: tuto.welcomeT = Tut.welcome.buttonDelayMs
    }
    Item {
        id: welcome
        objectName: "tutorialWelcome"
        anchors.fill: parent
        visible: tuto.step === "welcome"

        Rectangle { anchors.fill: parent; color: "#000000" }

        // our greeting: rings open round the logo over 2500 ms
        Item {
            id: greeting
            readonly property real p: Math.min(1, tuto.welcomeT / Tut.welcome.animationMs)
            x: (parent.width - width) / 2
            y: parent.height * 0.5 - height / 2 - Theme.dp(38)
            width: Theme.dp(72)
            height: width
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real q: Math.max(0, Math.min(1, greeting.p * 1.5 - index * 0.2))
                    anchors.centerIn: parent
                    width: greeting.width * (0.4 + 0.6 * q)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Theme.dp(2)
                    border.color: Theme.color.primary
                    opacity: q * (1 - 0.25 * index) * 0.8
                }
            }
            Icon {
                anchors.centerIn: parent
                width: parent.width * 0.42
                height: width
                name: "logo-asteroidos"
                color: Theme.color.onBackground
                opacity: greeting.p
                scale: 0.6 + 0.4 * greeting.p
            }
        }

        Label {
            id: hiLabel
            objectName: "tutorialHi"
            width: parent.width * 0.7
            x: (parent.width - width) / 2
            y: greeting.y + greeting.height + Theme.dp(12) - (tuto.textShown ? 0 : Theme.dp(Tut.welcome.textOffsetDp))
            horizontalAlignment: Text.AlignHCenter
            role: "titleLarge"
            color: Theme.color.onBackground
            opacity: tuto.textShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.duration(300) } }
            Behavior on y { NumberAnimation { duration: Motion.duration(300); easing.type: Easing.OutCubic } }
            //% "Hi there"
            text: qsTrId("id-tutorial-hi-there") + localeManager.changesObserver
        }

        EdgeButton {
            id: startButton
            objectName: "tutorialStart"
            preferredHeight: Theme.dp(Tut.welcome.buttonDp)
            iconName: "ios-arrow-forward"
            visible: tuto.buttonShown
            //% "Start"
            text: ""
            Accessible.name: qsTrId("id-tutorial-start") + localeManager.changesObserver
            onClicked: tuto.enter("splash")
        }
    }

    // ---- "Let's review some navigation basics!" ----
    Item {
        id: splash
        objectName: "tutorialSplash"
        anchors.fill: parent
        visible: tuto.step === "splash"

        Rectangle { anchors.fill: parent; color: "#000000" }

        Icon {
            id: splashIcon
            x: (parent.width - width) / 2
            y: Math.round(parent.height * Tut.hints.splash.top)
            width: Theme.dp(32)
            height: width
            name: "ios-hand"
            color: Theme.color.primary
        }
        Label {
            id: splashTitle
            objectName: "tutorialSplashTitle"
            x: Math.round(parent.width * Tut.hints.splash.side)
            width: parent.width - 2 * x
            y: splashIcon.y + splashIcon.height + Theme.dp(8)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "titleMedium"
            color: Theme.color.onBackground
            //% "Let's review some navigation basics!"
            text: qsTrId("id-tutorial-splash-title") + localeManager.changesObserver
        }
        // Skip sits 4 dp above the Continue button
        TextButton {
            id: skipButton
            objectName: "tutorialSkip"
            x: (parent.width - width) / 2
            y: continueButton.y - height - Theme.dp(Tut.hints.splash.gapDp)
            //% "Skip"
            text: qsTrId("id-tutorial-skip") + localeManager.changesObserver
            onClicked: tuto.finish()
        }
        EdgeButton {
            id: continueButton
            objectName: "tutorialContinue"
            preferredHeight: Theme.dp(Tut.hints.edgeButtonDp)
            visible: parent.visible
            //% "Continue"
            text: qsTrId("id-tutorial-continue") + localeManager.changesObserver
            onClicked: tuto.enter("notifications")
        }
    }

    // ---- the gesture steps: a dim layer, the tip, the hint ----
    Item {
        id: coach
        objectName: "tutorialCoach"
        anchors.fill: parent
        visible: Tut.dimmed(tuto.step)
        // no touch is taken (no area here): the home screen under it is what the user works with

        Rectangle {
            id: dimLayer
            anchors.fill: parent
            color: "#000000"
            opacity: tuto.step === "tilesInfo" ? Tut.dim.face : Tut.dimAlpha(tuto.snap)
            Behavior on opacity { NumberAnimation { duration: Motion.duration(250) } }
        }

        Label {
            id: tip
            objectName: "tutorialTip"
            x: Math.round(parent.width * (tuto.step === "tilesInfo" ? 0.088 : 0.12))
            width: parent.width - 2 * x
            y: Math.round(parent.height * (tuto.step === "tilesInfo" ? 0.06 : 0.1))
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "titleMedium"
            color: Theme.color.onBackground
            text: tuto.tipText(tuto.step)
        }

        Label {
            id: tipBody
            objectName: "tutorialTipBody"
            visible: tuto.step === "tilesInfo"
            x: Math.round(parent.width * 0.088)
            width: parent.width - 2 * x
            y: tip.y + tip.height + Theme.dp(3)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "bodySmall"
            color: Theme.color.onSurfaceVariant
            //% "Widgets are accessed from the watch face & show helpful info from your apps"
            text: qsTrId("id-tutorial-tiles-intro") + localeManager.changesObserver
        }

        TutorialHint {
            id: hint
            objectName: "tutorialHintItem"
            readonly property var spec: Tut.hintFor(tuto.step)
            visible: spec.kind !== "none" && !tuto.holding
            kind: spec.kind === "side" ? "side" : (spec.kind === "none" ? "vertical" : spec.kind)
            dir: spec.dir ? spec.dir : "up"
            running: visible && tuto.displayOn
            // the crown and side hints sit beside the buttons, on the right edge
            x: kind === "crown" ? parent.width - width - Theme.dp(4)
               : (kind === "side" ? parent.width - width - Theme.dp(4) : (parent.width - width) / 2)
            y: kind === "crown" ? (parent.height - height) / 2 - Theme.dp(8)
               : (kind === "side" ? (parent.height - height) / 2 + parent.height * 0.22
                                  : parent.height * 0.5 - height / 2 + Theme.dp(14))
        }

        // the widgets step ends with a check button (an edge button, as stock)
        EdgeButton {
            id: tilesNext
            objectName: "tutorialTilesNext"
            preferredHeight: Theme.dp(Tut.hints.edgeButtonDp)
            visible: tuto.step === "tilesInfo"
            enabled: visible
            iconName: "ios-checkmark"
            text: ""
            //% "Next"
            Accessible.name: qsTrId("id-tutorial-next") + localeManager.changesObserver
            onClicked: tuto.advance()
        }
    }

    // ---- "All set" ----
    Item {
        id: allSet
        objectName: "tutorialAllSet"
        anchors.fill: parent
        visible: tuto.step === "allSet"
        Rectangle { anchors.fill: parent; color: "#000000" }
        SetupCheck {
            id: allSetCheck
            x: (parent.width - width) / 2
            y: parent.height * 0.3 - height / 2
            size: Theme.dp(Tut.hints.checkDp)
            duration: Tut.confirmMs
            Component.onCompleted: play()
            readonly property bool shown: allSet.visible
            onShownChanged: if (shown) play()
        }
        Label {
            objectName: "tutorialAllSetTitle"
            x: Math.round(parent.width * 0.088)
            width: parent.width - 2 * x
            y: allSetCheck.y + allSetCheck.height + Theme.dp(10)
            horizontalAlignment: Text.AlignHCenter
            role: "titleMedium"
            color: Theme.color.onBackground
            //% "All set"
            text: qsTrId("id-tutorial-all-set") + localeManager.changesObserver
        }
    }

    // ---- the end: "Time to explore your watch!" ----
    Item {
        id: completion
        objectName: "tutorialCompletion"
        anchors.fill: parent
        visible: tuto.step === "done"
        Rectangle { anchors.fill: parent; color: "#000000" }
        SetupCheck {
            id: completionCheck
            x: (parent.width - width) / 2
            y: parent.height * 0.3 - height / 2
            size: Theme.dp(Tut.hints.checkDp)
            duration: Tut.completionMs
        }
        Label {
            id: completionTitle
            objectName: "tutorialCompletionTitle"
            x: Math.round(parent.width * 0.052)
            width: parent.width - 2 * x
            y: completionCheck.y + completionCheck.height + Theme.dp(10)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            role: "titleMedium"
            color: Theme.color.onBackground
            //% "Time to explore your watch!"
            text: qsTrId("id-tutorial-explore") + localeManager.changesObserver
        }
        EdgeButton {
            id: confirmButton
            objectName: "tutorialConfirm"
            preferredHeight: Theme.dp(Tut.hints.edgeButtonDp)
            iconName: "ios-checkmark"
            visible: parent.visible
            text: ""
            //% "Done"
            Accessible.name: qsTrId("id-tutorial-done") + localeManager.changesObserver
            onClicked: tuto.finish()
        }
    }

    // ---- the tips ----
    function tipText(id) {
        switch (id) {
        //% "Swipe up for notifications"
        case "notifications": return qsTrId("id-tutorial-swipe-up") + localeManager.changesObserver
        //% "Swipe down for Quick Settings"
        case "quicksettings": return qsTrId("id-tutorial-swipe-down") + localeManager.changesObserver
        //% "Swipe left or right to cycle through widgets"
        case "tilesSwipe": return qsTrId("id-tutorial-tiles-swipe") + localeManager.changesObserver
        //% "Keep swiping left for more widgets"
        case "keepLeft": return qsTrId("id-tutorial-keep-left") + localeManager.changesObserver
        //% "Keep swiping right for more widgets"
        case "keepRight": return qsTrId("id-tutorial-keep-right") + localeManager.changesObserver
        //% "Widgets provide quick access to helpful info"
        case "tilesInfo": return qsTrId("id-tutorial-tiles-info") + localeManager.changesObserver
        //% "Press the crown to return to the watch face"
        case "crownFace": return qsTrId("id-tutorial-crown-face") + localeManager.changesObserver
        //% "From the watch face, press the crown to see apps"
        case "crownApps": return qsTrId("id-tutorial-crown-apps") + localeManager.changesObserver
        case "sideButton": return sideMode === "recents"
            //% "Press side button for recent apps"
            ? qsTrId("id-tutorial-side-recents") + localeManager.changesObserver
            //% "Press and hold side button for Assistant"
            : qsTrId("id-tutorial-side-assistant") + localeManager.changesObserver
        }
        return ""
    }
}
