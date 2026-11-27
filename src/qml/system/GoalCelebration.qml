/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import Nemo.DBus
import Nemo.Mce
import org.asteroid.controls
import "goals.js" as Goals

/* The full screen celebrations (health-fitness-14, -15; R5 E-05, E-06, E-18), as stock's Fitbit CelebrationActivity
 * (celebration/display/CelebrationActivity.java; manifest: turnScreenOn, showWhenLocked; started by trj.java:115-185
 * with the rules of goals.js mayShow). asteroid-sensorlogd decides and posts them: the main goal reached (its type:
 * steps, calories, distance, floors or Active Zone Minutes, tui.java:505-580), every hour of the reminders' window
 * met, a reminder to move at minute 50 and its hour's 250 steps reached. Lipstick hands the post over
 * (notificationPreviewPresenter.fullScreenRequested: x-asteroid-category "celebration" is a full screen category,
 * eoscategory.h; no banner, and the transient post leaves no card).
 *
 * The screens (stock's layouts, the Fitbit Lottie and colours out of reach: our design for the confetti):
 *   a goal (GoalAchievedCelebration):  the metric's icon, "Goal complete!", the metric's name, the value
 *   a reminder (tsa.java f(): HourlyReminderToMoveMessage): the ring of the hour's steps of 250 round the hourly
 *       activity icon, "Reminder to move", "N steps left\nthis hour"
 *   its goal reached (tsa.java e(): HourlyReminderToMoveCelebration): "Reminder to move" small, 12 dp, the full
 *       ring, 8 dp, "Goal complete!", "250/250"
 * The arrival turns the display on (mce, as stock's turnScreenOn) and keeps it on for the 10 s it shows; a tap, a
 * swipe or the crown ends it sooner. Not in Bedtime, Theater or Do Not Disturb, on the charger, off the wrist, with
 * Celebrations off, nor over a call, an alarm, setup or another system surface (it is dropped then, as stock's).
 * A goal's screen vibrates twice (its post has no feedback of its own); a reminder's vibration is its post's
 * (lipstick plays it). Nothing runs while no celebration shows: no timer, no reading. Fed by the arbiter
 * (`displayOn`, `blocked`, `quiet`). */
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
    // lipstick's preview presenter (fullScreenRequested); a test sets its own
    property QtObject presenter: typeof notificationPreviewPresenter !== "undefined" ? notificationPreviewPresenter : null

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    readonly property alias hideTimer: hide
    readonly property alias confettiAnimation: confettiAnim
    readonly property alias vibration: buzz
    readonly property bool celebrationsOn: switchValue.value !== false && switchValue.value !== "false"
    readonly property bool charging: chargerType.valid && chargerType.type !== MceChargerType.None
    readonly property bool offWrist: offBodyKnown.value === true && offBody.value === true
    // a celebration waiting for the display the arrival asked for
    property var pending: null
    // the celebration on the screen (Goals.parse), how many were shown
    property var current: null
    property int shows: 0
    readonly property string kind: current ? current.kind : ""
    readonly property bool isGoal: kind === "goal"
    readonly property bool isReminder: kind === "rtm" || kind === "rtm-done"
    readonly property var metric: isGoal ? Goals.metric(current.metric) : null
    // a distance goal in miles or kilometres: the phone's unit system (asteroid-btsyncd's
    // /org/asteroidos/settings/imperial-units, R5 E-35; stock takes the account's units), else the locale's
    ConfigurationValue {
        id: units
        key: "/org/asteroidos/settings/imperial-units"
        defaultValue: cel.localeImperial(localeManager.localeRevision)
    }
    // the locale's measurement system (evaluated again after a language change: the revision is its argument)
    function localeImperial(revision) { return Qt.locale().measurementSystem !== Locale.MetricSystem }
    readonly property bool imperial: units.value === true || units.value === "true"

    ConfigurationValue { id: switchValue; key: "/org/asteroidos/health/celebrations"; defaultValue: true }
    ConfigurationValue { id: offBody; key: "/org/asteroidos/sensors/off-body"; defaultValue: false }
    ConfigurationValue { id: offBodyKnown; key: "/org/asteroidos/sensors/off-body-available"; defaultValue: false }
    MceChargerType { id: chargerType }

    Connections {
        target: cel.presenter
        ignoreUnknownSignals: true
        function onFullScreenRequested(notification) {
            if (notification && notification.hints)
                cel.offer(Goals.parse(notification.hints))
        }
    }

    /* A celebration has come: on the screen now, or once the display it asked for is on; dropped when it may not
     * show (goals.js mayShow) */
    function offer(c) {
        if (!c)
            return false
        if (!Goals.mayShow({ blocked: blocked, quiet: quiet, charging: charging, offWrist: offWrist,
                             enabled: celebrationsOn }))
            return false
        if (!displayOn) {
            pending = c
            requestDisplay()
            return true
        }
        present(c)
        return true
    }
    onDisplayOnChanged: {
        if (displayOn && pending !== null) {
            var c = pending
            pending = null
            present(c)
        }
    }

    function present(c) {
        current = c
        shows++
        if (dialog.shown)
            dialog.opened()
        else
            dialog.open()
    }
    function close() { dialog.close() }

    // the tests and the arbiter: show this one now (a parsed celebration, goals.js parse)
    function show(c) {
        present(c)
    }

    // the texts of the screen
    //% "Goal complete!"
    readonly property string goalCompleteText: qsTrId("id-goal-complete") + localeManager.changesObserver
    //% "Reminder to move"
    readonly property string reminderText: qsTrId("id-reminder-to-move") + localeManager.changesObserver
    readonly property string nameText: {
        if (!isGoal)
            return ""
        switch (current.metric) {
        //% "Steps"
        case "steps": return qsTrId("id-goal-steps") + localeManager.changesObserver
        //% "Calories"
        case "calories": return qsTrId("id-goal-calories") + localeManager.changesObserver
        //% "Distance"
        case "distance": return qsTrId("id-goal-distance") + localeManager.changesObserver
        //% "Floors"
        case "floors": return qsTrId("id-goal-floors") + localeManager.changesObserver
        //% "Active Zone Min"
        case "azm": return qsTrId("id-goal-azm") + localeManager.changesObserver
        //% "Hourly Activity"
        case "hourly": return qsTrId("id-goal-hourly") + localeManager.changesObserver
        }
        return ""
    }
    readonly property var formats: ({
        //% "%1 cal"
        cal: qsTrId("id-goal-cal-value"),
        //% "%1 floors"
        floors: qsTrId("id-goal-floors-value"),
        //% "%1 Zone Mins"
        azm: qsTrId("id-goal-azm-value"),
        //% "%1 hr"
        hours: qsTrId("id-goal-hours-value"),
        //% "%1 km"
        km: qsTrId("id-goal-km-value"),
        //% "%1 mi"
        mi: qsTrId("id-goal-mi-value")
    })
    readonly property string valueText: isGoal ? Goals.valueText(current, Qt.locale(), imperial, formats) + localeManager.changesObserver : ""
    readonly property string leftText: {
        if (kind !== "rtm")
            return ""
        //% "%n step(s) left\nthis hour"
        return qsTrId("id-rtm-steps-left", current.left) + localeManager.changesObserver
    }
    readonly property string ratioText: kind === "rtm-done" ? current.goal + "/" + current.goal : ""

    // mce turns the display on for the arrival (its notification request, as the heart rate alert's), at most 10 s;
    // the dialog keeps it on while it shows
    property bool _holding: false
    function requestDisplay() {
        _holding = true
        mce.typedCall("notification_begin_req",
                      [{ "type": "s", "value": "asteroid-celebration" },
                       { "type": "i", "value": 10000 },
                       { "type": "i", "value": 0 }],
                      function () {},
                      function (error, message) { console.log("GoalCelebration: display on:", error, message) })
    }
    function releaseDisplay() {
        if (!_holding)
            return
        _holding = false
        mce.typedCall("notification_end_req",
                      [{ "type": "s", "value": "asteroid-celebration" },
                       { "type": "i", "value": 1000 }])
    }
    DBusInterface {
        id: mce
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    Dialog {
        id: dialog
        objectName: "celebrationDialog"
        // the 10 s keep the display on
        keepScreenOn: true
        onOpened: {
            hide.restart()
            buzz.stop()
            if (cel.isGoal)
                buzz.start()
            confettiAnim.restart()
        }
        onClosed: {
            hide.stop()
            buzz.stop()
            confettiAnim.stop()
            cel.releaseDisplay()
        }

        // a tap ends it (the swipe and the crown through the dialog and keymap)
        MouseArea {
            anchors.fill: parent
            onClicked: dialog.close()
        }

        // the confetti: our design, a fixed pattern, made only while the screen is up (24 pieces and their
        // animations are not built at launcher start) and animated only while it shows; a goal reached (a goal, its
        // hour's reminder goal), not a reminder to move
        Loader {
            id: confettiLoader
            objectName: "confettiLoader"
            anchors.fill: parent
            active: dialog.active && cel.kind !== "rtm"
            sourceComponent: Component {
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
            }
        }

        // a goal: the metric's icon, "Goal complete!", the name, the value
        Column {
            id: content
            objectName: "celebrationContent"
            visible: cel.isGoal
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
                text: cel.goalCompleteText
            }
            Label {
                id: nameLabel
                objectName: "celebrationName"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "labelMedium"
                color: Theme.color.onSurfaceVariant
                text: cel.nameText
            }
            Label {
                id: valueLabel
                objectName: "celebrationValue"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "displaySmall"
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Theme.dp(16)
                color: Theme.color.primary
                text: cel.valueText
            }
        }

        // a reminder to move: (its goal reached: the label first) the ring, the title, the steps
        Column {
            id: reminder
            objectName: "reminderContent"
            visible: cel.isReminder
            anchors.centerIn: parent
            width: parent.width * 0.76

            Label {
                id: reminderLabel
                objectName: "reminderLabel"
                visible: cel.kind === "rtm-done"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                role: "labelMedium"
                color: Theme.color.onSurfaceVariant
                text: cel.reminderText
            }
            Item { width: 1; height: Theme.dp(12); visible: reminderLabel.visible }
            CircularProgressIndicator {
                id: ring
                objectName: "reminderRing"
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.dp(72)
                height: width
                displayOn: cel.displayOn && dialog.active
                strokeWidth: Theme.dp(6)
                color: Theme.color.primary
                progress: Goals.ringProgress(cel.current)

                // stock's ring has the hourly activity icon inside (gs_fitbit_hourly_activity)
                Icon {
                    objectName: "reminderIcon"
                    anchors.centerIn: parent
                    width: Theme.dp(28)
                    height: width
                    name: "eos-health-hourly"
                    color: Theme.color.primary
                }
            }
            Item { width: 1; height: Theme.dp(8) }
            Label {
                id: reminderTitle
                objectName: "reminderTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                role: "titleMedium"
                color: Theme.color.onBackground
                text: cel.kind === "rtm-done" ? cel.goalCompleteText : cel.reminderText
            }
            Label {
                id: reminderValue
                objectName: "reminderValue"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                role: cel.kind === "rtm-done" ? "titleLarge" : "bodyMedium"
                color: cel.kind === "rtm-done" ? Theme.color.primary : Theme.color.onSurfaceVariant
                text: cel.kind === "rtm-done" ? cel.ratioText : cel.leftText
            }
        }

        // the 10 s of stock, only while it shows
        Timer {
            id: hide
            interval: Goals.SHOW_MS
            onTriggered: dialog.close()
        }
        // the vibration of a goal: a confirmation, again after 260 ms
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
