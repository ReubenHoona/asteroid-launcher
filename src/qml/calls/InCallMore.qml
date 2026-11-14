/*
 * Copyright (C) 2026 eos-mainline contributors
 * SPDX-License-Identifier: BSD-3-Clause
 */

import QtQuick
import org.asteroid.controls

/*
 * More options in a call (calls-11): a list under the TimeText, sides
 * 5.2 %, chips 4 dp apart (fragment_ongoing_voice_call_more_menu.xml).
 *   always:           Volume (the + / - screen)
 *   call audio on the watch (calls-12): Keypad (DTMF), the header Audio
 *                     with Speaker (the watch) and Phone, and "Pull call
 *                     audio to watch" while the audio is on the phone.
 * Without watch audio only Volume is offered: nothing else can work.
 * A swipe right closes the menu.
 */
Item {
    id: menu
    objectName: "inCallMore"
    anchors.fill: parent

    // CallAudio of the call (Volume needs btsyncd's call audio object)
    property QtObject audio: null
    readonly property bool watchAudio: audio !== null && audio.available
    readonly property bool onWatch: watchAudio && audio.route === "watch"

    signal volumeRequested()
    signal keypadRequested()
    signal closeRequested()

    readonly property real topPadding: Math.round(0.0938 * height)
    readonly property real sidePadding: Math.round(0.052 * width)
    readonly property real bottomPadding: Math.round(0.2708 * height)
    readonly property real chipGap: Theme.dp(4)
    readonly property real headerAbove: Theme.dp(30)
    readonly property real headerBelow: Theme.dp(14)
    readonly property alias list: list

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

                    Button {
                        objectName: "chipVolume"
                        width: column.width
                        visible: menu.audio !== null && menu.audio.present
                        variant: "tonal"
                        iconName: "ios-volume-up"
                        //% "Volume"
                        text: qsTrId("id-call-volume") + localeManager.changesObserver
                        onClicked: menu.volumeRequested()
                    }

                    Button {
                        objectName: "chipKeypad"
                        width: column.width
                        visible: menu.watchAudio
                        variant: "tonal"
                        iconName: "ios-keypad"
                        //% "Keypad"
                        text: qsTrId("id-call-keypad") + localeManager.changesObserver
                        onClicked: menu.keypadRequested()
                    }

                    Item {
                        objectName: "audioHeader"
                        width: column.width
                        height: visible ? menu.headerAbove + menu.headerBelow : 0
                        visible: menu.watchAudio
                        Label {
                            width: parent.width
                            y: menu.headerAbove - baselineOffset
                            horizontalAlignment: Text.AlignHCenter
                            role: "labelMedium"
                            color: Theme.color.onSurfaceVariant
                            //% "Audio"
                            text: qsTrId("id-call-audio") + localeManager.changesObserver
                        }
                    }

                    Button {
                        objectName: "chipSpeaker"
                        width: column.width
                        visible: menu.watchAudio
                        variant: menu.onWatch ? "filled" : "tonal"
                        centered: true
                        //% "Speaker"
                        text: qsTrId("id-call-audio-speaker") + localeManager.changesObserver
                        onClicked: if (menu.audio) menu.audio.setRoute("watch")
                    }

                    Button {
                        objectName: "chipPhone"
                        width: column.width
                        visible: menu.watchAudio
                        variant: menu.onWatch ? "tonal" : "filled"
                        centered: true
                        //% "Phone"
                        text: qsTrId("id-call-audio-phone") + localeManager.changesObserver
                        onClicked: if (menu.audio) menu.audio.setRoute("phone")
                    }

                    Button {
                        objectName: "chipPull"
                        width: column.width
                        visible: menu.watchAudio && !menu.onWatch
                        variant: "tonal"
                        centered: true
                        //% "Pull call audio to watch"
                        text: qsTrId("id-call-pull-audio") + localeManager.changesObserver
                        onClicked: if (menu.audio) menu.audio.pullToWatch()
                    }
                }
            }

            TimeText { }
        }
    }
}
