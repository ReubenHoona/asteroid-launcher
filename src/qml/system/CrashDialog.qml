/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls
import "system.js" as Sys

/* The system error dialogs of an app, as stock's AppErrorDialog and
 * AppNotRespondingDialog (system-dialogs-misc-01, -03). One layout:
 * a full-screen black dialog, scrolled by the crown, with the title
 * ("%1 keeps stopping" or "%1 isn't responding": titleMedium white, centred,
 * at most 3 lines, 32 dp from the top, 10 dp at the sides), 16 dp, then
 * 52 dp pills (26 dp corners, the dark surface, 4 dp apart, 15 sp text
 * starting at 14 dp, 24 dp icon, 6 dp between icon and text), 40 dp at the
 * bottom (base_error_dialog_padding 10, _top_padding 32, _bottom_padding
 * 40 dp on a 192 dp round watch).
 *   crash: "App info", "Close app" ('Send feedback' only with a report
 *          receiver, there is none; 'Open app again' hidden by default).
 *          Cancelable: a swipe back or the crown closes it. Closes by itself
 *          after 300 s (the dialog's timeout).
 *   anr:   "Close app", "Wait". Not cancelable. The pills take no touch for
 *          the first 1000 ms (BaseErrorDialog.java:67-71).
 * Shown by AppErrors (the crash watcher's second crash within 120 s, the
 * compositor's 5 s ping timeout). No animation runs while it is not up. */
Item {
    id: dialog
    objectName: "appErrorDialog"
    anchors.fill: parent

    /* "crash" or "anr" */
    property string kind: "crash"
    property string appTitle: ""
    property string appKey: ""
    property bool open: false
    readonly property bool shown: open
    readonly property bool cancelable: kind === "crash"
    /* the first 1000 ms after it showed: taps on the pills do nothing */
    readonly property bool locked: lockTimer.running
    readonly property alias list: list
    // the dialog's own timeout (300 s), armed only while it is up
    readonly property int autoCloseMs: closeTimer.interval
    readonly property bool autoCloseArmed: closeTimer.running

    // App info of the crashed app (the dialog closes)
    signal appInfoRequested(string appKey)
    // Close app: a crashed app is already gone, an unresponsive one is killed
    signal closeAppRequested(string appKey)
    // Wait: another 5 s for the unresponsive app
    signal waitRequested(string appKey)
    // it went away, for any reason
    signal dismissed()

    visible: open
    z: 1

    function show(k, title, key) {
        kind = k
        appTitle = title
        appKey = key
        open = true
        list.contentY = -list.topMargin
        lockTimer.restart()
        closeTimer.restart()
    }
    function close() {
        if (!open)
            return
        open = false
        lockTimer.stop()
        closeTimer.stop()
        dismissed()
    }

    // a title with its name in
    readonly property string titleText: kind === "anr"
        //% "%1 isn't responding"
        ? qsTrId("id-app-not-responding").arg(appTitle) + localeManager.changesObserver
        //% "%1 keeps stopping"
        : qsTrId("id-app-keeps-stopping").arg(appTitle) + localeManager.changesObserver

    function press(which) {
        if (locked)
            return
        switch (which) {
        case "info":
            appInfoRequested(appKey)
            break
        case "close":
            closeAppRequested(appKey)
            break
        case "wait":
            waitRequested(appKey)
            break
        }
        close()
    }

    Timer { id: lockTimer; interval: Sys.ERROR_BUTTON_LOCK_MS }
    // one-shot, only while the dialog is up
    Timer { id: closeTimer; interval: Sys.ERROR_AUTO_CLOSE_MS; onTriggered: dialog.close() }

    // the black screen takes every touch
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        MouseArea { anchors.fill: parent }
    }

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        swipeEnabled: dialog.cancelable
        onFinished: {
            var go = committed
            reset()
            if (go && dialog.cancelable)
                dialog.close()
        }

        Item {
            width: parent.width
            height: parent.height
            x: swipe.value

            Rectangle {
                anchors.fill: parent
                color: "#000000"
            }

            Flickable {
                id: list
                objectName: "errorList"
                anchors.fill: parent
                topMargin: Theme.dp(32)
                bottomMargin: Theme.dp(40)
                contentWidth: width
                contentHeight: column.height
                boundsBehavior: Flickable.StopAtBounds
                Component.onCompleted: contentY = -topMargin

                Column {
                    id: column
                    x: Theme.dp(10)
                    width: list.width - 2 * Theme.dp(10)
                    spacing: Theme.dp(4)

                    Label {
                        id: title
                        objectName: "errorTitle"
                        width: column.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        role: "titleMedium"
                        color: "#ffffff"
                        text: dialog.titleText
                        bottomPadding: Theme.dp(12)
                    }

                    // the pills: crash: App info, Close app; anr: Close app, Wait
                    Repeater {
                        model: dialog.kind === "anr" ? ["close", "wait"] : ["info", "close"]
                        delegate: Button {
                            required property string modelData
                            objectName: "errorButton_" + modelData
                            width: column.width
                            variant: "tonal"
                            horizontalPadding: Theme.dp(14)
                            iconSize: Theme.dp(24)
                            iconSpacing: Theme.dp(6)
                            containerColor: Theme.color.surfaceContainer
                            contentColor: "#ffffff"
                            iconColor: "#ffffff"
                            text: modelData === "info"
                                  //% "App info"
                                  ? qsTrId("id-app-info-button") + localeManager.changesObserver
                                  : modelData === "wait"
                                    //% "Wait"
                                    ? qsTrId("id-app-wait") + localeManager.changesObserver
                                    //% "Close app"
                                    : qsTrId("id-app-close") + localeManager.changesObserver
                            iconName: modelData === "info" ? "ios-information-circle-outline"
                                      : modelData === "wait" ? "ios-clock-outline" : "ios-close"
                            onClicked: dialog.press(modelData)
                        }
                    }
                }
            }
        }
    }
}
