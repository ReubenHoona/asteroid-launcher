/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import org.asteroid.controls
import org.asteroid.launcher
import "goals.js" as Goals

/* The daily goal celebration (health-fitness-14), as stock's Fitbit GoalAchievedCelebration: when
 * the day's step total crosses the goal (Settings: /org/asteroidos/ux/steps-goal, 10000) a full
 * screen shows the metric's icon, "Goal complete!", the metric's name and the value, with about 4 s
 * of confetti (our own design: the stock Lottie files are out of reach) and two short vibrations. It
 * goes after 10 s, with a tap, a swipe or the crown. Once per goal and day.
 * The steps are read from asteroid-sensorlogd's log (HealthLog, a file watcher: no polling, no timer
 * but its own 2 s debounce) only while the display is on, and once when it comes on; a goal reached
 * with the display off is shown at the next screen on. Not while a call, an alarm, setup or another
 * system surface is up, nor in Bedtime, Theater or Do Not Disturb (it is then dropped for the day:
 * a celebration that comes hours late says nothing). The animation and its timers run only while
 * the screen shows. Fed by the arbiter (`displayOn`, `blocked`, `quiet`). */
Item {
    id: cel
    objectName: "goalCelebration"
    anchors.fill: parent

    /* the display is on */
    property bool displayOn: true
    /* a surface that must not be covered is up */
    property bool blocked: false
    /* Bedtime, Theater or Do Not Disturb */
    property bool quiet: false
    // a clock (the tests move it)
    property var clock: function () { return new Date() }

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    readonly property alias health: log
    readonly property alias hideTimer: hide
    readonly property alias confettiAnimation: confettiAnim
    readonly property alias vibration: buzz
    readonly property bool celebrationsOn: switchValue.value !== false && switchValue.value !== "false"
    // a celebration is waiting for the screen to come on
    property bool pending: false
    // the metric on the screen
    property string metricId: "steps"
    property int value: 0
    property int shows: 0
    readonly property var metric: Goals.metric(metricId)

    // the screen reads the sensor only while it is on
    readonly property bool watching: celebrationsOn && displayOn

    ConfigurationValue { id: switchValue; key: "/org/asteroidos/health/celebrations"; defaultValue: true }
    ConfigurationValue { id: goal; key: "/org/asteroidos/ux/steps-goal"; defaultValue: 10000 }
    // the day (local, "YYYY-MM-DD") a goal was last celebrated on
    ConfigurationValue { id: celebrated; key: "/org/asteroidos/health/celebrated-steps"; defaultValue: "" }

    HealthLog {
        id: log
        sensor: "stepCounter"
        buckets: 1
        active: cel.watching
        onChanged: cel.check()
    }

    onWatchingChanged: if (watching) check()
    onDisplayOnChanged: {
        if (displayOn && pending)
            tryShow()
    }

    /* The total crossed the goal? */
    function check() {
        if (!celebrationsOn)
            return
        var today = Goals.dayKey(clock())
        var total = log.hasData ? log.lastValue : 0
        if (Goals.decide(total, goal.value, celebrated.value, today) !== "celebrate")
            return
        // once for the day, whether or not it shows (a quiet hour drops it)
        celebrated.value = today
        value = total
        pending = true
        tryShow()
    }

    function tryShow() {
        if (!Goals.mayShow({ displayOn: displayOn, blocked: blocked, quiet: quiet })) {
            // a quiet or covered moment drops it, a dark screen keeps it for the next screen on
            if (displayOn)
                pending = false
            return
        }
        pending = false
        shows++
        dialog.open()
    }
    function close() { dialog.close() }

    // the tests and the arbiter: show it now
    function show(total) {
        value = total
        shows++
        dialog.open()
    }

    Dialog {
        id: dialog
        objectName: "celebrationDialog"
        // the 10 s keep the display on
        keepScreenOn: true
        onOpened: {
            hide.restart()
            buzz.restart()
            confettiAnim.restart()
        }
        onClosed: {
            hide.stop()
            buzz.stop()
            confettiAnim.stop()
        }

        // a tap ends it (the swipe and the crown through the dialog and keymap)
        MouseArea {
            anchors.fill: parent
            onClicked: dialog.close()
        }

        // the confetti: our design, a fixed pattern, only while the screen shows
        Item {
            id: confettiLayer
            objectName: "confetti"
            anchors.fill: parent
            readonly property var pieces: Goals.confetti(24)
            readonly property var palette: [Theme.color.primary, Theme.color.tertiary, Theme.color.secondary,
                                            Theme.color.primaryContainer, Theme.color.tertiaryContainer]
            Repeater {
                model: confettiLayer.pieces
                delegate: Rectangle {
                    id: bit
                    required property var modelData
                    width: modelData.size
                    height: Math.max(4, modelData.size / 2)
                    radius: 2
                    color: confettiLayer.palette[modelData.color]
                    x: modelData.x * confettiLayer.width
                    y: -height
                    opacity: 0
                    rotation: 0
                    ParallelAnimation {
                        id: piece
                        running: confettiAnim.running
                        SequentialAnimation {
                            PauseAnimation { duration: modelData.delay }
                            ParallelAnimation {
                                NumberAnimation { target: bit; property: "y"; from: -bit.height
                                                  to: confettiLayer.height; duration: modelData.duration
                                                  easing.type: Easing.InQuad }
                                NumberAnimation { target: bit; property: "rotation"; from: 0; to: 360 * modelData.turns
                                                  duration: modelData.duration }
                                SequentialAnimation {
                                    NumberAnimation { target: bit; property: "opacity"; to: 1; duration: 120 }
                                    PauseAnimation { duration: Math.max(0, modelData.duration - 520) }
                                    NumberAnimation { target: bit; property: "opacity"; to: 0; duration: 400 }
                                }
                            }
                        }
                    }
                }
            }
        }

        // the metric's icon, "Goal complete!", the name, the value
        Column {
            id: content
            objectName: "celebrationContent"
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: Theme.dp(4)

            Icon {
                id: metricIcon
                objectName: "celebrationIcon"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.dp(32)
                height: width
                name: cel.metric ? cel.metric.icon : ""
                color: Theme.color.primary
            }
            Label {
                id: titleLabel
                objectName: "celebrationTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                role: "titleMedium"
                color: Theme.color.onBackground
                //% "Goal complete!"
                text: qsTrId("id-goal-complete") + localeManager.changesObserver
            }
            Label {
                id: nameLabel
                objectName: "celebrationName"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "labelMedium"
                color: Theme.color.onSurfaceVariant
                //% "Steps"
                text: qsTrId("id-goal-steps") + localeManager.changesObserver
            }
            Label {
                id: valueLabel
                objectName: "celebrationValue"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "displaySmall"
                color: Theme.color.primary
                text: Goals.valueText(cel.value, Qt.locale())
            }
        }

        // the 10 s of stock, only while it shows
        Timer {
            id: hide
            interval: Goals.SHOW_MS
            onTriggered: dialog.close()
        }
        // the vibration: a confirmation, again after 260 ms
        SequentialAnimation {
            id: buzz
            ScriptAction { script: Haptics.confirm() }
            PauseAnimation { duration: Goals.BUZZ_GAP_MS }
            ScriptAction { script: Haptics.confirm() }
        }
        // one run of the confetti: about 4 s
        SequentialAnimation {
            id: confettiAnim
            PauseAnimation { duration: Goals.ANIMATION_MS + 1000 }
        }
    }
}
