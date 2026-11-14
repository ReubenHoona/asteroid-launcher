/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * More options of a ringing call (calls-04): a scrolling list under the
 * TimeText with the header "Send a message" and the quick replies "On my
 * way!", "I'll call you back" and "Running late"; a chip declines the call
 * and sends that text (stock fragment_incoming_call_more_menu.xml,
 * more_menu_quick_reply_chip.xml, mkq.java:57-209). The "Call option"
 * header with "Answer on phone" waits for the call audio on the watch
 * (calls-12).
 *
 * Layout: top padding 9.38 %, sides 5.2 %, bottom 27.08 % of the screen
 * (VALUES.tsv incoming_call_more_menu_*_padding_percent); headers 15 sp
 * with their baseline 30 dp below the header's top and 14 dp above its
 * bottom; chips 4 dp apart, centred text, surface colour. The crown scrolls
 * the list; a swipe right closes the menu.
 */
Item {
    id: menu
    objectName: "incomingCallMore"
    anchors.fill: parent

    // The text of the chosen quick reply
    signal replyChosen(string text)
    // The menu was swiped away
    signal closeRequested()

    readonly property real topPadding: Math.round(0.0938 * height)
    readonly property real sidePadding: Math.round(0.052 * width)
    readonly property real bottomPadding: Math.round(0.2708 * height)
    readonly property real chipGap: Theme.dp(4)
    readonly property real headerAbove: Theme.dp(30)
    readonly property real headerBelow: Theme.dp(14)
    readonly property alias list: list

    // stock quick_reply_text_1..3 (the dialer's own strings, dialer STRINGS.tsv)
    readonly property var replies: [
        //% "On my way!"
        qsTrId("id-call-reply-1") + localeManager.changesObserver,
        //% "I'll call you back"
        qsTrId("id-call-reply-2") + localeManager.changesObserver,
        //% "Running late"
        qsTrId("id-call-reply-3") + localeManager.changesObserver
    ]

    BackSwipeArea {
        id: swipe
        anchors.fill: parent
        onFinished: {
            var go = committed
            reset()
            if (go)
                menu.closeRequested()
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
                objectName: "moreList"
                anchors.fill: parent
                topMargin: menu.topPadding
                bottomMargin: menu.bottomPadding
                contentWidth: width
                contentHeight: column.height
                boundsBehavior: Flickable.StopAtBounds
                Component.onCompleted: contentY = -topMargin

                Column {
                    id: column
                    x: menu.sidePadding
                    width: list.width - 2 * menu.sidePadding
                    spacing: menu.chipGap

                    Item {
                        id: header
                        objectName: "sendHeader"
                        width: column.width
                        height: menu.headerAbove + menu.headerBelow
                        Label {
                            id: headerLabel
                            width: parent.width
                            y: menu.headerAbove - baselineOffset
                            horizontalAlignment: Text.AlignHCenter
                            role: "labelMedium"
                            color: Theme.color.onSurfaceVariant
                            //% "Send a message"
                            text: qsTrId("id-call-send-message") + localeManager.changesObserver
                        }
                    }

                    Repeater {
                        model: menu.replies
                        delegate: Button {
                            objectName: "reply" + index
                            width: column.width
                            variant: "tonal"
                            centered: true
                            text: modelData
                            onClicked: menu.replyChosen(modelData)
                        }
                    }
                }
            }

            TimeText { }
        }
    }
}
