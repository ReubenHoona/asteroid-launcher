/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import Nemo.DBus
import org.asteroid.controls
import "../desktop.js" as Desktop
import "hralert.js" as HA

/* The heart rate alert screen (M4 WO-12), as stock's HeartRateAlertInfoActivity (Fitbit 4.01.1 on CP3A:
 * HrAlertService.java:60-110, aaog.java:905-990, aauu.java, aaut.java, zqb.java:225-280, zyy.java:210-218,
 * aaum.java:91-101, aabb.java:557-567). asteroid-sensorlogd's high or low heart rate notification
 * (x-asteroid-category health-alert, daemon/healthMonitor.cpp postAlert) opens it when it arrives, over the app
 * or the face: stock posts the notification and starts the activity with it. Lipstick hands it over
 * (notificationPreviewPresenter.fullScreenRequested; no banner for it) also in Do Not Disturb, Bedtime and
 * Theater (stock's category alarm, lipstick eoscategory.h); the notification stays in the stream, one card, and a
 * tap on the card opens the screen again (Desktop.hrAlert.openFromCard).
 *
 * The screen, a scrolling list as stock's: the heart with a plus (high) or a minus (low) (stock's
 * gs_heart_plus / gs_heart_minus, drawn here: the icon set has no such glyph), "High heart rate", the bpm large
 * ("128 bpm"), the detail "Your heart rate rose above 120 bpm while you appeared to be inactive from 9:40 -
 * 9:50." (the watch's time format) and the edge button that closes the screen (stock's edge button closes the
 * activity, its content is not in the decompiled sources: a check mark here). Stock's "Open" chip under the detail
 * (the alert on the phone app) is shown only for an alert the phone knows of; ours are the watch's, so it is not.
 * Opened by the arrival it closes itself a minute after it came or was last scrolled (stock: 60 s), opened from the
 * card it stays. The arrival turns the display on (mce), except in Theater mode, where only a button does (as the
 * phone alarm). The vibration is the notification's own (lipstick plays it, its x-nemo-feedback).
 * Nothing runs while it is closed; the minute is one single-shot timer, only while the display is on.
 */
Item {
    id: hr
    objectName: "hrAlert"
    anchors.fill: parent

    // the display is on (the arbiter's)
    property bool displayOn: true
    // lipstick's preview presenter (fullScreenRequested); a test sets its own
    property QtObject presenter: typeof notificationPreviewPresenter !== "undefined" ? notificationPreviewPresenter : null
    // the wall clock in ms (the tests move it)
    property var clock: function () { return Date.now() }
    // Theater mode (modes.h): the screen stays off for the arrival
    readonly property bool screenStaysOff: typeof modes !== "undefined" && modes !== null && modes.theater === true

    readonly property bool shown: dialog.shown
    readonly property alias dialog: dialog
    readonly property alias dismissButton: edge
    readonly property alias list: flick
    readonly property alias timer: tick
    // the alert on screen (HA.parse), whether it closes itself, its last touch (ms) and how many were shown
    property var alert: null
    property bool autoDismiss: false
    property real since: 0
    property int shows: 0

    readonly property bool high: alert !== null && alert.kind === "high"
    readonly property string titleText: (alert === null ? ""
                                         : high
                                           //% "High heart rate"
                                           ? qsTrId("id-hralert-high")
                                           //% "Low heart rate"
                                           : qsTrId("id-hralert-low")) + localeManager.changesObserver
    //% "%1 bpm"
    readonly property string bpmText: alert === null ? "" : qsTrId("id-hralert-bpm").arg(alert.bpm) + localeManager.changesObserver
    readonly property string detailText: {
        if (alert === null)
            return ""
        var from = TimeFormat.time(new Date(alert.start))
        var to = TimeFormat.time(new Date(alert.end))
        return (high
                //% "Your heart rate rose above %1 bpm while you appeared to be inactive from %2 - %3."
                ? qsTrId("id-hralert-high-detail")
                //% "Your heart rate fell below %1 bpm while you appeared to be inactive from %2 - %3."
                : qsTrId("id-hralert-low-detail")).arg(alert.threshold).arg(from).arg(to) + localeManager.changesObserver
    }

    // a notification on screen: the arrival (auto: it closes itself) or a tap on its card
    function show(n, auto) {
        var a = n && n.hints ? HA.parse(n.hints) : null
        if (a === null)
            return false
        alert = a
        autoDismiss = auto === true
        since = clock()
        shows++
        flick.contentY = 0
        if (!dialog.shown)
            dialog.open()
        if (autoDismiss && !screenStaysOff)
            requestDisplay()
        arm()
        return true
    }
    function openFromCard(n) { return show(n, false) }
    function close() { dialog.close() }

    // the list was scrolled: the minute starts again
    function touched() {
        if (!dialog.shown || !autoDismiss)
            return
        since = clock()
        arm()
    }

    function arm() {
        tick.stop()
        if (!dialog.shown || !autoDismiss || !displayOn)
            return
        var left = HA.remainingMs(since, clock())
        if (left <= 0) {
            dialog.close()
            return
        }
        tick.interval = left
        tick.restart()
    }
    onDisplayOnChanged: arm()

    Component.onCompleted: Desktop.hrAlert = hr
    Component.onDestruction: if (Desktop.hrAlert === hr) Desktop.hrAlert = null

    Connections {
        target: hr.presenter
        ignoreUnknownSignals: true
        function onFullScreenRequested(notification) { hr.show(notification, true) }
    }

    Timer {
        id: tick
        repeat: false
        onTriggered: hr.arm()
    }

    // mce turns the display on for the arrival (its notification request, as the phone alarm's), at most 10 s
    property bool _holding: false
    function requestDisplay() {
        _holding = true
        mce.typedCall("notification_begin_req",
                      [{ "type": "s", "value": "asteroid-hr-alert" },
                       { "type": "i", "value": 10000 },
                       { "type": "i", "value": 0 }],
                      function () {},
                      function (error, message) { console.log("HrAlert: display on:", error, message) })
    }
    function releaseDisplay() {
        if (!_holding)
            return
        _holding = false
        mce.typedCall("notification_end_req",
                      [{ "type": "s", "value": "asteroid-hr-alert" },
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
        objectName: "hrAlertDialog"
        onClosed: {
            tick.stop()
            hr.releaseDisplay()
        }

        Flickable {
            id: flick
            objectName: "hrAlertList"
            anchors.fill: parent
            contentWidth: width
            contentHeight: column.y + column.height + edge.contentPadding
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.DragOverBounds
            onMovingChanged: if (moving) hr.touched()

            Column {
                id: column
                objectName: "hrAlertContent"
                y: Math.round(hr.height * 0.125)
                x: Math.round((hr.width - width) / 2)
                width: Math.round(hr.width * 0.76)
                spacing: Theme.dp(4)

                // the heart with a plus or a minus (stock gs_heart_plus_vd_theme_24 / gs_heart_minus_vd_theme_24)
                Item {
                    id: icon
                    objectName: "hrAlertIcon"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.dp(32)
                    height: width
                    Icon {
                        anchors.fill: parent
                        name: "ios-heart"
                        color: HA.ACCENT
                    }
                    Rectangle {
                        id: badge
                        objectName: "hrAlertSign"
                        width: Theme.dp(15)
                        height: width
                        radius: width / 2
                        x: parent.width - width + Theme.dp(2)
                        y: parent.height - height + Theme.dp(2)
                        color: Theme.color.background
                        Rectangle {
                            anchors.centerIn: parent
                            width: Theme.dp(9)
                            height: Theme.dp(2)
                            radius: height / 2
                            color: HA.ACCENT
                        }
                        Rectangle {
                            objectName: "hrAlertPlus"
                            visible: hr.high
                            anchors.centerIn: parent
                            width: Theme.dp(2)
                            height: Theme.dp(9)
                            radius: width / 2
                            color: HA.ACCENT
                        }
                    }
                }
                Label {
                    id: title
                    objectName: "hrAlertTitle"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    role: "titleMedium"
                    color: HA.ACCENT
                    text: hr.titleText
                }
                Label {
                    id: bpm
                    objectName: "hrAlertBpm"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    role: "displaySmall"
                    font.features: Theme.tabularNumerals
                    color: HA.ACCENT
                    text: hr.bpmText
                }
                Label {
                    id: detail
                    objectName: "hrAlertDetail"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    role: "bodyMedium"
                    color: Theme.color.onSurface
                    text: hr.detailText
                }
            }
        }

        EdgeButton {
            id: edge
            objectName: "hrAlertDismiss"
            flickable: flick
            iconName: "ms-check"
            containerColor: HA.ACCENT
            contentColor: HA.ON_ACCENT
            //% "Dismiss"
            Accessible.name: qsTrId("id-hralert-dismiss") + localeManager.changesObserver
            onClicked: hr.close()
        }
    }
}
