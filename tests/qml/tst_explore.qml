/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// R5 B-20: stock's "Explore your new watch" notification (sysui one.java c(), posted when the tutorial is skipped:
// fv.java case 18, the welcome screen's skip_tutorial). Skip, or a step that timed out (it ends as Skip does), posts
// it through the notification service: quiet (no preview, no feedback: stock's channel importance 2), app "Tips",
// "Explore your new watch", "Try the tutorial on watch"; the card's own button "Start tutorial" (cardactions.js)
// writes the request Settings' Start tutorial writes and takes the card away (autoCancel); a tutorial that starts
// closes the notice. Finishing the tutorial posts nothing. The texts are stock's strings, without brand names.
// MODE=st (the staged tree, the repo mocks: Backend records the bus calls).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml"
import "st/qml/firstrun/tutorial.js" as Tut
import "st/qml/desktop.js" as Desktop
import "st/qml/cardactions.js" as CA

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject {
        id: firstRun
        property int done: 0
        function finishTutorial() { done++ }
    }
    QtObject { id: gridStub; property int currentVerticalPos: 0; property int currentHorizontalPos: 0 }
    QtObject { id: drawerStub; property bool isOpen: false }
    QtObject { id: recentsStub; property bool isOpen: false }
    QtObject { id: deskStub; property var appDrawer: drawerStub; property var recents: recentsStub
               property var launched: []
               function launchByName(name, from) { var l = launched.slice(); l.push(name); launched = l } }
    QtObject { id: compStub; property bool assistantShown: false; function closeAssistant() {} }

    Component {
        id: fakeCard
        QtObject {
            property var hints: ({})
            property int invoked: 0
            property string lastAction: ""
            signal actionInvoked(string action)
            onActionInvoked: (a) => { invoked++; lastAction = a }
        }
    }
    Component {
        id: cardActions
        CardActions { }
    }
    Component {
        id: actionsComponent
        NotificationActions { width: 384 }
    }

    Loader { id: ld; anchors.fill: parent }

    TestCase {
        name: "ExploreNotice"
        when: windowShown
        property var tu: null

        function start() {
            Desktop.panelsGrid = gridStub
            Desktop.desktop = deskStub
            Desktop.compositorRoot = compStub
            ld.active = false
            ld.setSource(Qt.resolvedUrl("st/qml/firstrun/Tutorial.qml"), {})
            ld.active = true
            tryCompare(ld, "status", Loader.Ready, 20000)
            tu = ld.item
            tu.welcomeAnim.stop()
            wait(20)
            return tu
        }
        function init() {
            Backend.reset()
            Backend.replies["org.freedesktop.Notifications.Notify"] = 77
            firstRun.done = 0
            deskStub.launched = []
        }
        function cleanup() {
            ld.active = false
            tu = null
        }
        function notifies() {
            return Backend.calls.filter(function (c) { return c.method === "org.freedesktop.Notifications.Notify" })
        }
        function explores() {
            return notifies().filter(function (c) { return c.args[3] === "Explore your new watch" })
        }
        function closes() {
            return Backend.calls.filter(function (c) { return c.method === "org.freedesktop.Notifications.CloseNotification" })
        }
        function findNamed(item, name) {
            if (item.objectName === name)
                return item
            for (var i = 0; i < item.children.length; i++) {
                var r = findNamed(item.children[i], name)
                if (r)
                    return r
            }
            return null
        }

        function test_01_skip_posts_the_notice() {
            start()
            tu.enter("splash")
            var skip = findNamed(tu, "tutorialSkip")
            verify(skip)
            wait(100)
            mouseClick(skip)
            tryCompare(firstRun, "done", 1, 2000)
            var e = explores()
            compare(e.length, 1)
            var a = e[0].args
            compare(a[0], "Tips")
            compare(a[1], 0)
            compare(a[2], "ios-watch")
            compare(a[3], "Explore your new watch")
            compare(a[4], "Try the tutorial on watch")
            compare(JSON.stringify(a[5]), "[]")
            var h = a[6]
            compare(h["x-eos-app"], "eos-tutorial")
            compare(h["x-eos-start-tutorial"], true)
            // quiet, as stock's channel importance 2: no banner, no sound or vibration
            compare(h["x-nemo-preview-summary"], undefined)
            compare(h["x-nemo-preview-body"], undefined)
            compare(h["x-nemo-feedback"], undefined)
            compare(a[7], -1)
            // its id is kept to take it away later
            compare(Number(Backend.confGet(Tut.exploreIdKey)), 77)
        }

        function test_02_a_timed_out_step_posts_it_too() {
            start()
            tu.enter("splash")
            tu.stepTimeout.triggered()
            compare(firstRun.done, 1)
            compare(explores().length, 1)
        }

        function test_03_finishing_posts_nothing() {
            start()
            tu.finish()
            compare(firstRun.done, 1)
            compare(explores().length, 0)
            // the end of the last step (its auto close) is a finish, not a skip
            start()
            tu.enter("done")
            tu.autoClose.triggered()
            compare(explores().length, 0)
            // twice: one notice
            start()
            tu.skip()
            tu.skip()
            compare(explores().length, 1)
        }

        function test_04_a_starting_tutorial_closes_the_notice() {
            Backend.confSet(Tut.exploreIdKey, 55)
            start()
            var c = closes()
            compare(c.length, 1)
            compare(c[0].args[0], 55)
            compare(Number(Backend.confGet(Tut.exploreIdKey)), 0)
            // none kept: nothing to close
            Backend.clearCalls()
            start()
            compare(closes().length, 0)
        }

        // ---- the card's own button (cardactions.js, CardActions.qml) ----
        function test_05_the_card_button() {
            verify(CA.offersTutorial(Tut.exploreHints()))
            verify(!CA.offersTutorial({ "x-eos-app": "eos-tutorial" }))
            verify(!CA.offersTutorial({ "x-eos-start-tutorial": true }))
            verify(!CA.offersTutorial({ "x-eos-app": "asteroid-health", "x-eos-start-tutorial": true }))
            verify(CA.offersTutorial({ "x-eos-app": "eos-tutorial.desktop", "x-eos-start-tutorial": "true" }))
            verify(!CA.offersTutorial(null))
            compare(CA.tutorialRequest(1234).key, "/org/asteroidos/launcher/start-tutorial")
            compare(CA.tutorialRequest(1234).value, "tutorial@1234")

            var card = createTemporaryObject(fakeCard, top, { hints: Tut.exploreHints() })
            var acts = createTemporaryObject(cardActions, top, { notification: card })
            compare(acts.buttons.length, 1)
            compare(acts.buttons[0].kind, "tutorial")
            compare(acts.buttons[0].label, "Start tutorial")
            var before = Date.now()
            verify(acts.run("tutorial"))
            var v = String(Backend.confGet("/org/asteroidos/launcher/start-tutorial"))
            verify(/^tutorial@\d+$/.test(v), v)
            verify(Number(v.split("@")[1]) >= before)
            // no app is started: the launcher's own coach
            compare(deskStub.launched.length, 0)
            // the card goes (stock autoCancel)
            compare(card.invoked, 1)
            compare(card.lastAction, "default")
            // an ordinary card: no button, nothing to run
            var plain = createTemporaryObject(fakeCard, top, { hints: { "x-eos-app": "eos-update" } })
            var acts2 = createTemporaryObject(cardActions, top, { notification: plain })
            compare(acts2.buttons.length, 0)
            verify(!acts2.run("tutorial"))
        }

        // the open card's buttons: "Start tutorial" in the launcher's own button row (looked at: /tmp/r5ui-shots)
        function test_06_the_card_drawn() {
            var card = createTemporaryObject(fakeCard, top, { hints: Tut.exploreHints() })
            var acts = createTemporaryObject(actionsComponent, top, { notification: card })
            verify(acts)
            wait(300)
            var b = findNamed(acts, "cardAction")
            verify(b, "the card's own button")
            compare(b.text, "Start tutorial")
            verify(b.visible)
            grabImage(top).save("/tmp/r5ui-shots/b20-card-actions.png")
            mouseClick(b)
            verify(/^tutorial@\d+$/.test(String(Backend.confGet("/org/asteroidos/launcher/start-tutorial"))))
            compare(card.lastAction, "default")
        }
    }
}
