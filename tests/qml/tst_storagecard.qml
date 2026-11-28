/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

// C-17: the low storage notice's card (lipstick/src/notifications/diskspacenotifier.cpp posts it with
// x-eos-ui-open "app_storage"): its expanded view has stock's "Open app" button (sysui full_view_open_app,
// koi.java: the button of a notification's content intent); running it invokes the card's default action,
// which the notification server turns into the Settings request (NotificationManager::invokeAction ->
// AppWatcher::openSettings, ui/open = "app_storage@<ms>"). The notice is resident: the card stays.
// A card without the hint has no such button. MODE=st (the staged tree, the repo mocks).
import QtQuick
import QtTest
import org.asteroid.controls
import LauncherTest
import "st/qml"
import "st/qml/cardactions.js" as CA

Item {
    id: top
    width: 384
    height: 384

    QtObject { id: localeManager; property string changesObserver: "" }
    QtObject { id: deskStub; property var launched: []
               function launchByName(name, from) { var l = launched.slice(); l.push(name); launched = l } }

    // the hints diskspacenotifier.cpp posts
    readonly property var storageHints: ({
        "category": "x-nemo.system.diskspace",
        "x-eos-ui-open": "app_storage",
        "x-eos-app": "storage",
        "resident": true,
        "x-nemo-user-removable": false
    })

    Component {
        id: fakeCard
        QtObject {
            property var hints: ({})
            property string summary: "Storage space running out"
            property string body: "Some system functions may not work"
            property bool userRemovable: false
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

    TestCase {
        name: "StorageCard"
        when: windowShown

        function init() {
            Backend.reset()
            deskStub.launched = []
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

        function test_01_the_route() {
            compare(CA.settingsRoute(top.storageHints), "app_storage")
            compare(CA.settingsRoute({ "x-eos-ui-open": "updates" }), "updates")
            compare(CA.settingsRoute({ "x-eos-ui-open": "" }), "")
            compare(CA.settingsRoute({ "x-eos-app": "storage" }), "")
            compare(CA.settingsRoute(null), "")
        }
        function test_02_open_app() {
            var card = createTemporaryObject(fakeCard, top, { hints: top.storageHints })
            var acts = createTemporaryObject(cardActions, top, { notification: card })
            compare(acts.buttons.length, 1)
            compare(acts.buttons[0].kind, "settings")
            compare(acts.buttons[0].label, "Open app")
            verify(acts.run("settings"))
            // the default action: the notification server opens Settings on the route, the card stays (resident)
            compare(card.invoked, 1)
            compare(card.lastAction, "default")
            // nothing is started from here (the request's watcher in MainScreen starts Settings)
            compare(deskStub.launched.length, 0)
            compare(acts.lastKind, "settings")
        }
        function test_03_other_cards() {
            var plain = createTemporaryObject(fakeCard, top, { hints: { "x-eos-app": "eos-update" } })
            var acts = createTemporaryObject(cardActions, top, { notification: plain })
            compare(acts.buttons.length, 0)
            verify(!acts.run("settings"))
            compare(plain.invoked, 0)
        }
        function test_04_drawn() {
            var card = createTemporaryObject(fakeCard, top, { hints: top.storageHints })
            var acts = createTemporaryObject(actionsComponent, top, { notification: card })
            verify(acts)
            wait(300)
            var b = findNamed(acts, "cardAction")
            verify(b, "the card's Open app")
            compare(b.text, "Open app")
            verify(b.visible)
            mouseClick(b)
            compare(card.lastAction, "default")
            compare(card.invoked, 1)
        }
    }
}
