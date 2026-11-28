/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.Configuration
import "desktop.js" as Desktop
import "cardactions.js" as CA

/*
 * The launcher's own buttons of a notification card (NotificationActions shows them under the card's text, as the
 * app's own actions): what the hints of the card make of it (cardactions.js).
 *  - "Start" / "End" on sensorlogd's exercise-detect cards (CR-38): writes the Exercise app's start or stop request
 *    and starts asteroid-exercise ("Start" for 'Start tracking?', "End" for 'Finished working out?');
 *  - "Open" on the "Start your day" card: opens the Health app's Morning Brief page;
 *  - "Start tutorial" on the launcher's "Explore your new watch" card (R5 B-20): asks for the tutorial;
 *  - "Open app" on a system notice that names a Settings page (C-17: the low storage notice): the card's default
 *    action, which the notification server turns into the Settings request (the card stays when it is resident).
 * sensorlogd posts the workout offers transient: they live as the banner and the detail view a tap on it opens (the
 * card there is expanded, so the buttons show); they are never in the stream. Running a button takes the card down.
 * Nothing runs until a button is tapped; nothing is polled.
 */
Item {
    id: handler
    visible: false
    width: 0
    height: 0

    property QtObject notification: null
    readonly property var hints: notification && notification.hints ? notification.hints : ({})

    readonly property var offer: CA.exerciseOffer(hints)
    readonly property string page: CA.openPage(hints)
    readonly property bool tutorial: CA.offersTutorial(hints)
    readonly property string settingsRoute: CA.settingsRoute(hints)

    // [{ kind: "exercise" | "open" | "tutorial" | "settings", label }], none for an ordinary card
    readonly property var buttons: {
        var list = []
        if (offer !== null)
            list.push({ kind: "exercise",
                        label: offer.action === "start"
                               //% "Start"
                               ? qsTrId("id-card-start")
                               //% "End"
                               : qsTrId("id-card-end") })
        if (page !== "")
            list.push({ kind: "open",
                        //% "Open"
                        label: qsTrId("id-card-open") })
        if (tutorial)
            list.push({ kind: "tutorial",
                        //% "Start tutorial"
                        label: qsTrId("id-card-start-tutorial") })
        if (settingsRoute !== "")
            list.push({ kind: "settings",
                        //% "Open app"
                        label: qsTrId("id-card-open-app") })
        return list
    }

    // the last button run, for the tests
    property string lastKind: ""
    signal ran(string kind)

    ConfigurationValue { id: startRequest; key: "/org/asteroidos/exercise/start-request"; defaultValue: "" }
    ConfigurationValue { id: stopRequest; key: "/org/asteroidos/exercise/stop-request"; defaultValue: "" }
    ConfigurationValue { id: healthOpen; key: "/org/asteroidos/health/ui/open"; defaultValue: "" }
    ConfigurationValue { id: tutorialStart; key: CA.TUTORIAL_KEY; defaultValue: "" }

    function launch(app) {
        if (Desktop.desktop && Desktop.desktop.launchByName)
            Desktop.desktop.launchByName(app, null)
    }

    function run(kind) {
        var now = Date.now()
        if (kind === "exercise" && offer !== null) {
            var r = CA.exerciseRequest(offer, now)
            if (offer.action === "stop")
                stopRequest.value = r.value
            else
                startRequest.value = r.value
            launch(CA.EXERCISE_APP)
        } else if (kind === "open" && page !== "") {
            healthOpen.value = CA.openRequest(page, now).value
            launch(CA.HEALTH_APP)
        } else if (kind === "tutorial" && tutorial) {
            tutorialStart.value = CA.tutorialRequest(now).value
        } else if (kind === "settings" && settingsRoute !== "") {
            // the default action below: the notification server opens Settings on the route
        } else {
            return false
        }
        lastKind = kind
        ran(kind)
        // the card is done: a non-resident notification goes with its default action
        if (notification && notification.actionInvoked)
            notification.actionInvoked("default")
        return true
    }
}
