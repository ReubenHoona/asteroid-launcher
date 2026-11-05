/*
 * Copyright (C) 2026 Reuben Horner <reubarb.scons@gmail.com>
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The call view (src/qml/notifications/IncomingCall.qml) on the mocks of
 * tests/qml/mocks, with a stand-in for lipstick's notification list: which
 * of the phone's call cards it shows. Lipstick restores its stored
 * notifications at start (before the model is populated): a restored call
 * card older than restoredCallMaxMs is no call to show (the phone's removal
 * never arrived while the watch was down), a recent one is; a card arriving
 * later shows as before, its removal hides the view, an action is reported.
 * Run by agents/stalecall/tools/run-incomingcall-qml.sh (qemu-aarch64,
 * offscreen, software Qt Quick), which stages IncomingCall.qml and
 * NotificationButton.qml as module LauncherQml.
 */

import QtQuick
import QtTest
import LauncherTest
import LauncherQml
import org.nemomobile.lipstick

Item {
    id: root
    width: 384
    height: 384

    // what the compositor gives the view
    QtObject {
        id: localeManager
        property string changesObserver: ""
    }

    // a phone notification as lipstick's LipstickNotification shows it
    Component {
        id: cardComponent
        QtObject {
            property int replacesId: 0
            property string summary: "Caller"
            property string body: ""
            property var hints: ({})
            property date timestamp: new Date()
            function actionInvoked(key) { Backend.record("notification", "actionInvoked", [replacesId, key]) }
        }
    }

    Rectangle { anchors.fill: parent; color: "black" }
    Loader {
        id: loader
        anchors.fill: parent
        active: false
        sourceComponent: IncomingCall {}
    }

    TestCase {
        name: "IncomingCall"
        when: windowShown
        property var view: null
        property var model: null

        function init() {
            Backend.reset()
            Lipstick.notificationModel = null
            loader.active = false
            loader.active = true
            tryCompare(loader, "status", Loader.Ready)
            view = loader.item
            model = Lipstick.notificationModel
            verify(model !== null)
            verify(!model.populated)
        }

        // a card with the phone's actions, posted ageMs ago
        function card(id, actions, ageMs) {
            return cardComponent.createObject(root, {
                "replacesId": id,
                "hints": { "x-asteroid-phone-actions": actions },
                "timestamp": new Date(new Date().getTime() - ageMs)
            })
        }
        function displayRequested() {
            return Backend.find("com.nokia.mce", "com.nokia.mce.request.notification_begin_req") !== null
        }

        function test_01_restored_old_ongoing_call_not_shown() {
            // The watch rebooted during a call that ended 10 min ago: lipstick
            // restores the card, the view leaves it as a plain notification
            var n = card(1, "end", 10 * 60000)
            model.add(n)
            verify(view.call === null)
            model.populated = true
            verify(view.call === null)
            compare(view.visible, false)
            compare(model.itemCount, 1)
        }

        function test_02_restored_recent_ongoing_call_shown() {
            // The launcher restarted a minute into a call: in call, as before
            var n = card(2, "end", 60000)
            model.add(n)
            model.populated = true
            verify(view.call === n)
            verify(view.ongoing)
            verify(view.visible)
            verify(!displayRequested())
            // ... until btsyncd closes the card (the phone did not post it again)
            model.remove(n)
            verify(view.call === null)
        }

        function test_03_restored_old_ringing_call_not_shown() {
            var n = card(3, "answer,reject,silence", 5 * 60000)
            model.add(n)
            model.populated = true
            verify(view.call === null)
            verify(!displayRequested())
        }

        function test_04_restored_recent_ringing_call_rings() {
            var n = card(4, "answer,reject,silence", 30000)
            model.add(n)
            model.populated = true
            verify(view.call === n)
            verify(!view.ongoing)
            verify(displayRequested())
        }

        function test_05_live_calls_after_start() {
            model.populated = true
            var ongoing = card(5, "end", 0)
            model.add(ongoing)
            verify(view.call === ongoing)
            verify(view.ongoing)
            model.remove(ongoing)
            verify(view.call === null)
            var ringing = card(6, "answer,reject", 0)
            model.add(ringing)
            verify(view.call === ringing)
            verify(displayRequested())
            view.act("reject")
            verify(view.call === null)
            var a = Backend.find("notification", "actionInvoked")
            verify(a !== null)
            compare(a.args, [6, "reject"])
        }

        function test_06_restored_plain_notification() {
            var n = card(7, "reply,open,mute", 10)
            model.add(n)
            model.populated = true
            verify(view.call === null)
            compare(model.itemCount, 1)
        }
    }
}
