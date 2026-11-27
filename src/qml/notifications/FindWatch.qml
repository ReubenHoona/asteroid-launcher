/*
 * Copyright (C) 2026 eos
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import org.nemomobile.lipstick

/*
 * Find my watch (apps-misc-14, AUDIT-72 D-29): the phone's "find device" (Gadgetbridge: a ring
 * with the found action; asteroid-btsyncd posts it with the hint x-asteroid-find-watch, not
 * resident, its x-nemo-feedback find_my_watch rising to full volume whatever the Ring volume says)
 * as a full screen page over the app or the face, not only a card. Stock's ring is played by
 * GmsCore (not in the image); its words are Find Hub's (com.google.android.apps.adm STRINGS):
 * "Playing sound…" (ringing), "Stop sound" (stop_ring) and "To stop the sound, you can also
 * press the power button on %1$s." (ring_device_message_1; spot_how_to_stop_ringing: "press a
 * button"). The page: the speaker glyph, the title, that note, and the Stop sound edge button.
 *
 * Stop sound, the crown, the side button (keymap.js: stopFindWatch, the Find Hub note) and a swipe
 * away all do the same: the found action of the card. Lipstick then removes the card (it is not
 * resident), which ends its feedback at once (the ring stops on the watch even when the phone has
 * gone), and asteroid-btsyncd tells the phone (feedback found: Gadgetbridge's onFindDevice(false)).
 * The page goes when the card goes (the phone stopped it), as the phone alarm's.
 *
 * The arrival turns the display on and keeps it on while the page is up (mce notification
 * requests, renewed every 25 s), at most ten minutes, except in Theater mode, where only a button
 * turns the screen on (as the phone alarm). The page plays nothing itself: the sound and the
 * vibration are the card's (lipstick plays its x-nemo-feedback). Nothing runs while no alert is
 * shown: the two timers run only with the page up.
 */
Item {
    id: page
    objectName: "findWatch"
    anchors.fill: parent

    // the alert shown, or null
    property QtObject alert: null
    // alerts acted on or given up: not shown again (lipstick ids)
    property var handled: ({})
    // the wall clock in ms (the tests move it)
    property var clock: function () { return Date.now() }
    // the page shows an alert that rings: the crown and the side button stop it (keymap.js)
    readonly property bool shown: alert !== null
    readonly property alias dialog: dialog
    readonly property alias stopButton: edge
    readonly property alias list: flick
    readonly property alias model: findModel
    // how old a restored alert may be (lipstick restores its cards at start): ten minutes, as the
    // phone alarm's, and the time the display is held for one alert
    property int maxAgeMs: 600000

    // Theater mode (modes.h): the screen stays off for the arrival
    readonly property bool screenStaysOff: typeof modes !== "undefined" && modes !== null && modes.theater === true

    function hint(n, key) {
        return n && n.hints ? n.hints[key] : undefined
    }
    // btsyncd's find-my-watch alert: its hint, or (an older btsyncd) a card whose phone actions have
    // found and are not a call's
    function isFindAlert(n) {
        if (n === null || n === undefined)
            return false
        var h = hint(n, "x-asteroid-find-watch")
        if (h === true || h === "true")
            return true
        var a = hint(n, "x-asteroid-phone-actions")
        if (a === undefined || a === null)
            return false
        var list = String(a).split(",")
        return list.indexOf("found") >= 0 && list.indexOf("answer") < 0 && list.indexOf("reject") < 0
    }
    // a find alert not acted on that came in the last ten minutes (an old restored one does not ring)
    function isRinging(n) {
        if (!isFindAlert(n) || handled[n.replacesId])
            return false
        var t = n.timestamp ? n.timestamp.getTime() : clock()
        return clock() - t < maxAgeMs
    }

    function newest(except) {
        for (var i = 0; i < findModel.itemCount; i++) {
            var n = findModel.get(i)
            if (n !== except && isRinging(n))
                return n
        }
        return null
    }

    function show(n) {
        alert = n
        if (!dialog.shown)
            dialog.open()
        displayOn()
        giveUp.restart()
    }

    // done with this one (acted on, removed by the phone, given up): the next, if any
    function next(done) {
        if (done !== null && done !== undefined) {
            var h = handled
            h[done.replacesId] = true
            handled = h
        }
        var n = newest(done)
        alert = null
        if (n !== null)
            show(n)
        else
            dialog.close()
    }

    // Stop sound (the button, the crown, the side button, a swipe away): the card's found action
    function stop() {
        var n = alert
        if (n === null)
            return false
        next(n)
        n.actionInvoked("found")
        return true
    }

    onAlertChanged: if (alert === null) {
        giveUp.stop()
        displayRelease()
    }

    // mce keeps the display on for at most 30 s per request: renewed while the page is up
    function displayOn() {
        if (screenStaysOff)
            return
        mce.typedCall("notification_begin_req",
                      [{ "type": "s", "value": "asteroid-find-watch" },
                       { "type": "i", "value": 30000 },
                       { "type": "i", "value": 5000 }],
                      function () {},
                      function (error, message) { console.log("FindWatch: display on:", error, message) })
    }
    function displayRelease() {
        mce.typedCall("notification_end_req",
                      [{ "type": "s", "value": "asteroid-find-watch" },
                       { "type": "i", "value": 1000 }])
    }

    NotificationListModel {
        id: findModel
        onItemAdded: function (item) {
            if (page.isRinging(item))
                page.show(item)
        }
        onItemRemoved: function (item) {
            if (item === page.alert)
                page.next(item)
        }
        onPopulatedChanged: {
            var n = page.newest(null)
            if (findModel.populated && n !== null && page.alert === null)
                page.show(n)
        }
    }

    DBusInterface {
        id: mce
        bus: DBus.SystemBus
        service: "com.nokia.mce"
        path: "/com/nokia/mce/request"
        iface: "com.nokia.mce.request"
    }

    Timer {
        id: renew
        interval: 25000
        repeat: true
        running: page.shown
        onTriggered: page.displayOn()
    }

    // a phone that never ends the ring must not keep the display on: the page goes, the card stays
    // (its Stop sound button) and so does its sound
    Timer {
        id: giveUp
        interval: page.maxAgeMs
        onTriggered: page.next(page.alert)
    }

    // nothing under the page takes a touch while it rings
    MouseArea {
        anchors.fill: parent
        enabled: page.shown
    }

    Dialog {
        id: dialog
        objectName: "findWatchDialog"
        // a swipe away is the user there: it stops the sound too
        onDismissRequested: page.stop()

        // the words scroll when the text is large (stock's dialog list); the Stop sound button stays at the
        // bottom edge (the M3 alert dialog's edge button), the list ends above it
        Flickable {
            id: flick
            objectName: "findWatchList"
            anchors.fill: parent
            contentWidth: width
            contentHeight: column.y + column.height
            bottomMargin: edge.contentPadding
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.DragOverBounds
            clip: true

            Column {
                id: column
                objectName: "findWatchContent"
                y: Math.round(page.height * 0.125)
                x: Math.round((page.width - width) / 2)
                width: Math.round(page.width * 0.76)
                spacing: Theme.dp(4)

                Icon {
                    objectName: "findWatchIcon"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.dp(32)
                    height: width
                    name: "ms-volume_up"
                    color: Theme.color.primary
                }
                Label {
                    id: title
                    objectName: "findWatchTitle"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    role: "titleMedium"
                    color: Theme.color.onBackground
                    //% "Playing sound…"
                    text: qsTrId("id-findwatch-ringing") + localeManager.changesObserver
                }
                Label {
                    id: note
                    objectName: "findWatchNote"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    role: "bodySmall"
                    color: Theme.color.onSurfaceVariant
                    //% "To stop the sound, you can also press a button on your watch."
                    text: qsTrId("id-findwatch-note") + localeManager.changesObserver
                }
            }
        }

        EdgeButton {
            id: edge
            objectName: "findWatchStop"
            // the speaker crossed out: the label would wrap in the arch; the name is stock's stop_ring
            iconName: "ms-volume_off"
            //% "Stop sound"
            Accessible.name: qsTrId("id-stop-sound") + localeManager.changesObserver
            onClicked: page.stop()
        }
    }
}
